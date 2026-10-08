# libyara (vendored)

Source: https://github.com/VirusTotal/yara, tag v4.5.8 (BSD-3-Clause, see COPYING).

Copied: `libyara/*.c`, `libyara/*.h`, `libyara/include/yara.h`, `libyara/include/yara/*.h`, the
`hash`, `math`, `time`, `console` and `string` modules, and `proc/mach.c`. `modules/module_list` is
trimmed to those modules, and `include/module.modulemap` is added so Swift can `import CYara`.
Nothing else is modified.

The `hash` module uses CommonCrypto (`HAVE_COMMONCRYPTO_COMMONCRYPTO_H`), so no OpenSSL is needed.
Squeaky uses libyara to evaluate Apple's own XProtect rules, read from the system at scan time.
