# Contributing

Thanks for helping! Issues and pull requests are welcome in English or Turkish.

## Getting started

```sh
swift build && swift test
./yap.sh          # build and install to /Applications for a real test
```

The code is split in three parts:

- `Sources/FingerKitCore`: pure logic (gesture recognition, settings, conflicts). Covered by tests in `Tests/`.
- `Sources/FingerKit`: the menu bar app (AppKit + SwiftUI): event taps, windows, permissions.
- `Sources/CMultitouch`: a tiny C bridge to macOS's private `MultitouchSupport` framework.

Code comments are in Turkish; feel free to write yours in English.

## Translations

UI text lives in `Paket/Diller/<language>.lproj/Localizable.strings`. The key (left side) is the original Turkish text; only change the right side.

- Fix a translation: edit the right-hand side and open a pull request.
- Add a language: copy `en.lproj` to `<code>.lproj`, translate it, and add the code to `CFBundleLocalizations` in `Paket/Info.plist`.
- After changing UI text in Swift, run `python3 Araclar/dilleri-denetle.py`: it lists any string that is missing in a language. CI runs the same check.

## Releasing (maintainers)

1. Update the version in `Paket/Info.plist` (`CFBundleShortVersionString`, `CFBundleVersion`) and add a section to `CHANGELOG.md`.
2. Commit, then tag: `git tag v0.2.0 && git push --tags`. GitHub Actions builds the universal zip and creates the release.
3. Update `version` and `sha256` in the Homebrew cask (`enisaytac/homebrew-tap`, `Casks/fingerkit.rb`); the SHA-256 is in the release notes.
