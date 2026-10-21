# Third-party source references

The diagnostic prototype was developed after inspecting Reeb:
https://github.com/aiwithenoch/reebopensource
Commit: 172b8b0abff6ff301767fa8fd2a680560fefe1d3

Reeb is MIT licensed, Copyright (c) 2026 Enoch Ansong.
The snapshot in evidence/upstream retains its own LICENSE. The native PiP
sample-buffer approach is informed by that source and Apple's public APIs.
Reeb's speech tracker, English Whisper model and dependency tree are not used
in the diagnostic app. The text alignment core and diagnostic lifecycle are
new implementations.

To preserve attribution for any overlapping PiP rendering implementation,
the Reeb license also applies as a notice to those portions:

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

JavaScriptCore, Speech, AVFoundation, AVKit, SwiftUI and UIKit are system
frameworks, not redistributed dependencies. The build workflow uses pinned
GitHub checkout/upload-artifact actions under their respective licenses.
