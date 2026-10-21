# Unsigned iPhone diagnostic build

This is a fixed-script diagnostic prototype, not a finished teleprompter.

- Built for iPhone arm64. Minimum OS: iOS 17.
- Apple compilation and macOS JavaScriptCore smoke checks passed.
- Not yet installed or tested on an iPhone.
- Requires personal signing before installation; tapping the IPA in Safari does not install it.
- Real offline Mandarin recognition, PiP and simultaneous recording audio remain unverified.
- No Apple account, signing certificate, API key, personal script or device log is included.
- The app itself does not upload audio. Its diagnostic logs remain on the device unless the user exports them.

Verify `SHA256SUMS.txt` before installation. Source code is in `App/`.
