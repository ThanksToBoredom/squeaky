import CYara
import Foundation

/// A compiled set of YARA rules, backed by the vendored libyara.
///
/// Compiled rules are immutable, and libyara supports scanning with the same rules from
/// several threads at once, so `matches(file:)` can be called concurrently.
final class YaraRules: @unchecked Sendable {
    private var rules: UnsafeMutablePointer<YR_RULES>?
    /// Compiler errors, e.g. a rule using a module we don't build. Rules that compiled still work.
    private(set) var compileErrors: [String] = []

    private static let initialised: Bool = yr_initialize() == ERROR_SUCCESS

    /// Compiles each source separately so private helper rules (`Macho`, `Dylib`, …) with the
    /// same names in different files don't clash. Returns nil if nothing compiled.
    static func compile(_ sources: [(name: String, text: String)]) -> [YaraRules] {
        guard initialised else { return [] }
        return sources.compactMap { YaraRules(name: $0.name, text: $0.text) }
    }

    private init?(name: String, text: String) {
        var compiler: UnsafeMutablePointer<YR_COMPILER>?
        guard yr_compiler_create(&compiler) == ERROR_SUCCESS, let compiler else { return nil }
        defer { yr_compiler_destroy(compiler) }

        let errors = ErrorSink()
        let unmanaged = Unmanaged.passRetained(errors)
        defer { unmanaged.release() }
        yr_compiler_set_callback(compiler, { level, _, line, _, message, userData in
            guard level == YARA_ERROR_LEVEL_ERROR, let userData, let message else { return }
            let sink = Unmanaged<ErrorSink>.fromOpaque(userData).takeUnretainedValue()
            sink.messages.append("line \(line): \(String(cString: message))")
        }, unmanaged.toOpaque())

        let failures = text.withCString { yr_compiler_add_string(compiler, $0, nil) }
        compileErrors = errors.messages.map { "\(name): \($0)" }
        guard failures == 0 else { return nil }

        var compiled: UnsafeMutablePointer<YR_RULES>?
        guard yr_compiler_get_rules(compiler, &compiled) == ERROR_SUCCESS else { return nil }
        rules = compiled
    }

    deinit {
        if let rules { yr_rules_destroy(rules) }
    }

    /// Names of the rules that match the file. Private rules never show up here.
    func matches(file url: URL, timeout: Int32 = 10) -> [String] {
        guard let rules else { return [] }
        let sink = MatchSink()
        let unmanaged = Unmanaged.passRetained(sink)
        defer { unmanaged.release() }
        _ = url.path.withCString { path in
            yr_rules_scan_file(rules, path, SCAN_FLAGS_FAST_MODE, { _, message, data, userData in
                if message == CALLBACK_MSG_RULE_MATCHING, let data, let userData {
                    let rule = data.assumingMemoryBound(to: YR_RULE.self)
                    if let identifier = rule.pointee.identifier {
                        Unmanaged<MatchSink>.fromOpaque(userData).takeUnretainedValue()
                            .names.append(String(cString: identifier))
                    }
                }
                return CALLBACK_CONTINUE
            }, unmanaged.toOpaque(), timeout)
        }
        return sink.names
    }

    private final class ErrorSink { var messages: [String] = [] }
    private final class MatchSink { var names: [String] = [] }
}
