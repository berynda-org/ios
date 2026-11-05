# Berynda for iOS

Native SwiftUI client for iOS and iPadOS 17+. The current vertical slice is:

`launch → catalog/search → work → edition → native reader`

The catalog never presents source formats. It opens the canonical
`readable_file_id` returned for an edition. The backend selects it for mobile
using `TXT/Markdown → EPUB → PDF`; DJVU is excluded because the app does not
render it. MIME type remains an internal renderer detail.

The native reader renders TXT/Markdown, EPUB, and PDF. PDF delivery follows
the server contract: a small permitted source, an extracted single-page PDF,
or a server-rendered page image. If file/page download rights are absent, the
client always uses the rendered-image path even if a less restrictive server
configuration advertises client delivery. Digital publications are rendered
with the stable Readium 3.11.0 toolkit, which is pinned exactly in
`project.yml`; its internal state does not expose a format chooser.

Remote subresources embedded in a publication are blocked to prevent tracking
and data exfiltration. External links require an explicit reader tap and must
use HTTPS. Publication bytes are held in protected temporary storage, excluded
from backup, and removed when the reader closes.

## Generate and build on macOS

```sh
brew install xcodegen
xcodegen generate --spec project.yml
swift test --package-path BeryndaCore
xcodebuild \
  -project Berynda.xcodeproj \
  -scheme Berynda \
  -sdk iphonesimulator \
  -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO build
```

Debug builds use `http://127.0.0.1:8000/api/v1/`; Release builds use the fixed
`https://berynda.org/api/v1/` origin. Do not add a user-editable API host.

The Xcode project is generated from `project.yml` so it remains reviewable and
reproducible in this Windows-hosted repository. CI is the authoritative Xcode
build until the workspace is opened on macOS.

The API implementation and mobile representation-selection contract remain in
the main [Berynda repository](https://github.com/akrivonos/berynda). This
repository contains the native client and its client-side contract fixtures.
