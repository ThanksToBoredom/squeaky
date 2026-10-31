# Contributing to Squeaky

Thanks for helping out! Bug reports, ideas and pull requests are all welcome. Squeaky deletes files
on people's Macs, so changes are held to a careful standard: please read the safety rules below
before touching anything that scans or removes files.

## Reporting bugs and ideas

- **Bugs:** open an issue with your macOS version, Mac model (Apple Silicon or Intel), Squeaky
  version, what you did, what you expected and what happened. Screenshots help, but crop out
  anything personal (file names, app lists).
- **Ideas:** open an issue describing the problem first, before writing a large pull request, so we
  can agree on the approach.
- **Security issues** (for example a way to make Squeaky delete files it shouldn't): please don't
  open a public issue. Report it privately via the repository's **Security → Report a
  vulnerability** page.

## Getting set up

You need macOS 15 or later and Swift 6. The Command Line Tools are enough; Xcode is optional.

```sh
git clone https://github.com/ThanksToBoredom/squeaky.git
cd squeaky
scripts/create-signing-cert.sh   # once: a local signing certificate, so permissions survive rebuilds
scripts/build-app.sh debug       # builds build/Squeaky.app
open build/Squeaky.app
```

Run the tests before opening a pull request:

```sh
swift test --build-system native
```

The `--build-system native` flag is needed with the Command Line Tools on current macOS versions (see
*Toolchain notes* in the README). The README also documents the debug-only snapshot mode, which drives
the app through its screens and saves screenshots; it's the quickest way to check UI changes.

## Making a change

1. Fork the repository and create a branch from `main` (for example `fix/review-scroll` or
   `feature/login-items`). `main` is protected: all changes go through a pull request.
2. Keep pull requests small and focused on one thing. Unrelated clean-ups belong in their own PR.
3. Match the surrounding code: its naming, comment density and SwiftUI idioms. Use `@ViewState`
   instead of `@State` (see `ViewState.swift` for why).
4. Add or update tests in `Tests/SqueakyTests` for logic changes, especially anything that decides
   what gets removed.
5. Make sure `swift test --build-system native` passes and the app builds without new warnings.
6. Open the pull request and fill in the template: what changed, why, and how you tested it.
   Include before/after screenshots for UI changes.

Commit messages: a short summary line in the imperative mood ("Fix…", "Add…"), optionally a
`fix:`/`feat:`/`docs:` prefix, and a body explaining *why* when it isn't obvious.

## Safety rules for anything that removes files

These are non-negotiable, and reviewers will check them:

- **Never widen what can be removed** without a clear reason and tests. Every removal goes through
  `FileUtils.isSafeToRemove`, which only allows items inside the user's home folder (never the
  well-known folders themselves) and app bundles in `/Applications`. Don't bypass it.
- **Prefer the Trash.** Only regenerable data (caches, logs, the Trash itself) may be deleted
  permanently; anything the user created or installed goes to the Trash so it can be put back.
- **Nothing is removed without confirmation**, and anything that could be personal data (large
  files, old downloads, leftovers, launch items) starts **unselected**.
- **No root.** Squeaky doesn't run anything with administrator rights itself. Apps owned by root are
  handed to Finder, which asks for the password. Never build shell commands from file names; pass
  paths as arguments.
- **No network, no telemetry.** Squeaky works entirely offline and doesn't collect data. Changes that
  add network access need to be discussed in an issue first.

## Third-party code and artwork

Only add code or artwork whose licence allows it (MIT, BSD, Apache and similar), keep its licence
file and credit it in the README. Vendored code lives in its own folder with a note on where it came
from (see `Sources/CYara/VENDORED.md`).

## Licence

By contributing, you agree that your contributions are licensed under the project's
[MIT licence](LICENSE).
