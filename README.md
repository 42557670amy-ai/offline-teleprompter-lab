# Offline Teleprompter Lab

An iPhone diagnostic prototype for Mandarin voice-follow prompting in a
Picture-in-Picture window. It investigates whether prompting can continue
while a separate camera app records video with normal audio.

**Status: unsigned iPhone build compiled; not yet iPhone-tested. Cross-app microphone
coexistence is an open question, not a supported-feature claim.**

## Scope

- System Mandarin speech recognition, strictly on-device; unsupported offline
  recognition fails visibly instead of falling back to a server.
- Character-level script alignment for skips, rereading and revised partial
  transcripts. The same JS file runs in Node tests and Apple JavaScriptCore.
- Sample-buffer Picture-in-Picture rendering, no camera capture or sound output.
- Explicit audio-interruption handling; no background timer repeatedly taking
  audio focus away from another app.
- Local diagnostic events for audio buffers, recognition, position and PiP.
  Nothing is uploaded by the app. Logs are exported only on user request.

The prototype deliberately uses a fixed, non-personal test script. Script
editing and migration will follow only after the key platform experiment.

## Test and build

No third-party app dependencies are required.

```sh
node tests/matcher.test.cjs
node scripts/generate-project.cjs
```

On macOS with Xcode:

```sh
swift scripts/check-jsc.swift App/matcher.js
xcodebuild -project PromptLab.xcodeproj -scheme PromptLab \
  -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' \
  -derivedDataPath build/DerivedData CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO build
```

The GitHub Actions workflow runs only on standard macOS runners in a public
repository, times out after 15 minutes, and keeps small artifacts for one day.
It does not use Apple credentials or produce a provisioned installation.
An unsigned IPA must be personally signed before it can run on an iPhone.
Free personal signing has renewal requirements; this project does not claim
to remove them.

The Node tests use synthetic text inputs, not recorded speech. They cannot
establish real acoustic latency, recognition accuracy, background lifetime,
camera-app compatibility or final-recording audio quality.

## Device acceptance

Test offline recognition first, then PiP over the home screen, then a real
recording in the target camera app. Verify both the changing script position
and normal audio in the saved recording. A changing PiP frame counter alone
is not evidence that microphone capture continues.

Logs contain recognized words and remain local. Do not post personal logs,
scripts, account credentials, signing certificates or provisioning profiles
to this repository.

## License and credits

MIT, with attribution to Reeb for the inspected PiP implementation. See
`LICENSE` and `THIRD_PARTY_NOTICES.md`. The English Whisper dependency and
speech tracker from Reeb are not included.

## Download the unsigned diagnostic

See [dist/](dist/README.md) for the test IPA, SHA-256 checksum and installation status. The build is unsigned and is not an App Store installation.

Commit author metadata on main uses a GitHub no-reply address. The one-time, manually triggered cleanup workflow must run privately and preserves the exact code tree.
