# Object Builder save and import fixes

This patched build is based on upstream Object Builder 0.6.0 and labelled
`0.6.0-savefix.2`. It uses a separate application ID and preferences so it can
coexist with an older installation. Launch `ObjectBuilder.exe` and open your
DAT/SPR project and server items as usual.

## Horizontal animation strips

With the object set to Width 1, Height 1, Layers 1, Pattern X/Y/Z 1 and
Animations 17, drag a 544x32 PNG onto the texture editor. Frames are imported
left to right automatically. The existing 32x544 vertical layout also works.
The frame count remains controlled by the object's Animations setting.

Larger frames keep their tile orientation, and each animation frame retains
its pattern/layer grid. Only the selected frame group is replaced; the other
group is preserved. Existing combined idle/walking sheets remain supported.
Invalid dimensions now list complete, deduplicated sizes, such as
`32x544, 544x32`, instead of mixing widths and heights.

## What changed

- DAT, SPR, server definitions, server binary and OTFI are written to staging
  files before any destination is replaced. Existing files are moved aside as
  rollback copies instead of being deleted first.
- A failed replacement rolls back files already replaced and reopens the SPR
  reader without discarding edited objects or sprites. If rollback itself is
  blocked, the error identifies the retained recovery folders.
- SPR serialization reads source sprites strictly. Read failures and malformed
  run lengths abort the save; display error icons cannot be serialized.
- Failed saves keep dirty state and always dismiss the saving progress dialog.
  Successful Compile As changes the active project to the saved paths.
- The old asynchronous raw-copy shortcut has been removed; save completion now
  means all project writes and replacements have finished.

## Build and test

Use Apache Flex 4.16.1 with its required OSMF/font dependencies and a completed
AIR SDK installation. Run the scripts in PowerShell 7 or later. Java 17 and AIR
51.4.1.2 were used for this build.

```powershell
./scripts/build-windows.ps1 -FlexSdk C:/path/to/flex -AirSdk C:/path/to/air
./scripts/test-save-windows.ps1 -AirSdk C:/path/to/air
./scripts/test-save-windows.ps1 -AirSdk C:/path/to/air -Fixture C:/path/to/copy-of-project
python ./scripts/test-sprite-sheet-windows.py --air-sdk C:/path/to/air --image C:/path/to/544x32.png
python ./scripts/package-windows.py --air-sdk C:/path/to/air --java-home C:/path/to/jdk --output C:/path/to/new-output-folder
```

The AIR regression harness exercises successful saves, invalid server exports,
a closed sprite reader, overlapping destinations, malformed sprite data, and a
real Windows lock on the OTB file after earlier outputs have been replaced.
It verifies rollback hashes, retained edits, reopening, retry, and another save.
An optional fixture is copied into a fresh test directory before use; originals
are never modified. Test results are retained under `bin-debug/save-test-*`.

## Validation of 0.6.0-savefix.2

- 64 sprite-sheet checks passed, including all 17 frames of a supplied 544x32
  PNG. Imported ARGB bytes and OBD round-trip bytes matched each original frame.
- Vertical layouts, static images, non-square multi-tile frames, patterns,
  layers, unchanged idle groups, combined idle/walking imports, and rejected
  dimensions were covered.
- All 48 full-project save checks passed again, including file-lock rollback
  and retry with a copied 69,791-sprite project.
- Main application, embedded worker and regression harnesses compiled with the
  same toolchain. Python/PowerShell syntax checks and `git diff --check` passed.
- The private input PNG and project assets are not included in the repository.

## Previous save-fix validation (0.6.0-savefix.1)

- Windows synthetic regression suite: 48 checks passed.
- Full-project regression suite: 48 checks passed using a copied 69,791-sprite,
  13,671-client-item project. The original fixture was not changed.
- Client item properties, sprite edits, OTB flags and XML names survived the
  failed-save/retry sequence and were verified after reloading saved files.
- Packaged-app smoke test: loaded all five project files; forced a Windows OTB
  sharing violation; observed the error and dismissed saving overlay; confirmed
  every original file hash was unchanged; released the lock and saved again in
  the same editor session. DAT, SPR, OTB and OTFI were byte-identical after retry;
  XML content was unchanged, with only attribute element ordering normalized.
- Build scripts passed PowerShell/Python syntax validation; `git diff --check`
  passed. No game-server deployment or live gameplay test was performed.

## Limits and recovery

No filesystem API can atomically replace five separate files. If the process or
computer stops during the short commit phase, `.objectbuilder-save-*` folders
beside the destination files retain originals and staging files with a
`RECOVERY.txt` note. Preserve those folders until the project is recovered and
verified. A normal handled save failure attempts rollback automatically.

The portable bundle has a local development AIR signature, not an upstream
release signature or a trusted Windows publisher certificate.
