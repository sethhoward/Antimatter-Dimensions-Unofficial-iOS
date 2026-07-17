# Infinity Dimensions for iOS

How much antimatter can you make? Infinity? Start with a single dimension producing antimatter, then unlock new dimensions, each multiplying the one before it. Push past infinity — then do it again.

A native SwiftUI + JavaScriptCore port of the original web game by [Hevipelle (IvarK)](https://github.com/IvarK/AntimatterDimensionsSourceCode), used under the [MIT License](LICENSE). The game logic runs headlessly in JavaScriptCore; SwiftUI renders the interface natively for iPhone and iPad.

## Building & Running from Source

The full iOS source lives in this repository. There are **no package-manager or external dependencies** — the game engine (`AntiMatter/Resources/game-core-bundle.js`) is prebuilt and bundled, so you only need Xcode.

### Requirements

- macOS with **Xcode 26 or later** (the project builds against the iOS 26 SDK)
- An iPhone or iPad running **iOS 26 or later**, or the iOS Simulator
- An Apple ID for code signing (a free one works — see the iCloud note below)

### Steps

1. Clone this repository.
2. Open `AntiMatter.xcodeproj` in Xcode.
3. Select the **AntiMatter** target → **Signing & Capabilities** tab:
   - Set **Team** to your own Apple ID / development team.
   - Change the **Bundle Identifier** to something unique to you (e.g. `com.yourname.infinitydimensions`). The bundled identifier belongs to the original developer and won't sign under your team.
4. Choose your connected device (or a Simulator) as the run destination.
5. Press **Run** (⌘R). Xcode builds, installs, and launches the app. It appears on the home screen as **Infinity**.

### Sideloading with a free Apple ID

Free (personal) Apple accounts can't provision iCloud, so the bundled **iCloud Key-Value Storage** capability will block signing. To sideload without a paid Apple Developer account, do one of:

- In **Signing & Capabilities**, remove the **iCloud** capability, **or**
- Delete `AntiMatter/AntiMatter.entitlements` and clear **Code Signing Entitlements** under Build Settings.

This only disables cross-device iCloud save sync — local saves and everything else work normally. Note that apps signed with a free account expire after 7 days and must be re-installed.

### Notes

- Universal — runs on both iPhone and iPad.
- Saves are stored locally on device. iCloud sync is opt-in (Options → iCloud) and requires a paid Apple Developer account with the iCloud capability enabled.

## Bug Reports & Feature Requests

Found a bug or have a suggestion? [Open an issue](../../issues/new/choose) and include:

- **Device** — iPhone or iPad model
- **iOS version**
- **What happened** — describe the issue
- **What you expected** — describe the correct behavior
- **Steps to reproduce** — how can we trigger the bug?
- **Screenshot** — if it helps show the problem
- **Exported save** — go to Options > Export Save to Clipboard and paste it in your issue. This is the single most helpful thing you can include — it lets us load your exact game state and reproduce the bug directly

## FAQ

**Where is the source code?**
Right here — this repository contains the full iOS source. See [Building & Running from Source](#building--running-from-source) above to build and sideload it yourself.

## License

Released under the [MIT License](LICENSE). This is a port of [Antimatter Dimensions](https://github.com/IvarK/AntimatterDimensionsSourceCode) by Hevipelle (IvarK), which is also MIT licensed; the original copyright notice is preserved in the [LICENSE](LICENSE) file.

## Links

- [Official AD App Store](https://apps.apple.com/us/app/antimatter-dimensions/id6738206800) 
