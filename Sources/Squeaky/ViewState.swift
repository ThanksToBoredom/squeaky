import SwiftUI

/// Drop-in replacement for `@State`.
///
/// In the macOS 27 SDK `@State` is implemented as a macro whose plugin only ships
/// with Xcode, so it can't expand when building with the Command Line Tools alone.
/// This wraps the underlying `State` storage directly; SwiftUI discovers nested
/// dynamic properties, so it behaves identically.
@propertyWrapper
struct ViewState<Value>: DynamicProperty {
    private let storage: State<Value>

    init(wrappedValue: Value) {
        storage = State(initialValue: wrappedValue)
    }

    var wrappedValue: Value {
        get { storage.wrappedValue }
        nonmutating set { storage.wrappedValue = newValue }
    }

    var projectedValue: Binding<Value> { storage.projectedValue }
}
