## What and why

<!-- What does this change, and why? Link the issue if there is one ("Fixes #123"). -->

## How I tested it

<!-- Steps you took, and on which macOS version and Mac (Apple Silicon / Intel). -->

- [ ] `swift test --build-system native` passes
- [ ] The app builds and runs (`scripts/build-app.sh debug`)
- [ ] Screenshots attached for UI changes (with personal details cropped out)

## Removal safety

<!-- Only if this touches scanning or removing files. -->

- [ ] Doesn't widen what can be removed, or explains why and adds tests
- [ ] User data still goes to the Trash, and personal items still start unselected
