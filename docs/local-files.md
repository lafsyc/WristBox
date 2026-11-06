# Android local installation files

The mobile Applications page has Installed apps and Local files sections. Local
files are enumerated by `WristLocalFiles.kt` on a single background executor;
metadata stays on the device and is never sent to the account or store service.

Access is explicitly granted by the phone user:

- Android 11+ can enable `MANAGE_EXTERNAL_STORAGE` in system settings to scan
  primary shared storage. Protected app directories are not part of the scan.
- All supported Android versions can grant read access to selected directories
  using `ACTION_OPEN_DOCUMENT_TREE`; grants are persisted. Android 11+ restricts
  choosing certain roots, including Download, so keep the individual system
  file picker available.
- A selected folder switches scanning to granted folders. The source menu can
  switch between shared storage and granted folders, or revoke folder grants.

The scanner collects RPK/BIN filenames, size, directory, and modification time.
Newest-first is **modification time**, not a verified browser download timestamp.
Search and format/date/order filters are local. Scans stop after 30 seconds,
100,000 entries, 2,000 matching files, or depth 32; the UI reports partial results.
These bounds are checked between filesystem/provider operations, not a hard
timeout interrupting a stalled document provider.

An explicit install copies the selected file to a unique private
`cache/local-install` directory, with a 64 MiB streaming limit. Original files
are not changed. Copies older than seven days are cleaned on subsequent imports;
failed copies are removed immediately. The installation queue uses the copy so
moving the original download does not interrupt a queued transfer.

`analyzeLocalPackage` checks bytes rather than trusting suffixes: Vela application
containers use application installation, and recognized Vela watchface binaries
use watchface installation. Firmware, unknown payloads, missing identifiers,
empty files, and files above the size limit are rejected. Existing watchface
installation policy and device acknowledgements remain authoritative.

Validation includes mocked Android channel/UI tests for filtering and denied
access, backend routing tests for RPK/renamed-BIN/watchface/firmware/invalid bytes,
and mobile navigation regression tests. Real OEM permission screens, document
providers and physical watchface transfers require phone/band testing.

References:
- https://developer.android.com/training/data-storage/manage-all-files
- https://developer.android.com/training/data-storage/shared/documents-files

Any future store submission needs to review that store's current requirements
for all-files access and disclose the local-file management feature accurately.
