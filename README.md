# LogixMouseMapper

Tiny macOS menu bar app for remapping MX Master mouse buttons.

## What it does

- Runs as a background menu bar app (no dock icon).
- Captures global `other mouse` button presses.
- Lets you map each configured button entry to actions like Mission Control, App Expose, Back/Forward, Copy/Paste, and more.
- Lets you manage button entries from `Manage Buttons`:
  - `Learn New Button...` opens a dedicated screen that shows the last pressed raw button, includes a name field, and an `Add Entry` button.
  - `Remove Entry` deletes any configured entry.
- Starts with no button entries on first launch, so you explicitly add what you want.
- Stores mappings in `UserDefaults`.

## Run during development

```bash
swift run
```

On first launch, macOS should prompt for Accessibility permission. This permission is required for global button remapping.

## Build a `.app`

```bash
./scripts/build-app.sh
open ./dist/LogixMouseMapper.app
```

## Notes

- If remapping does not work, open menu item `Open Accessibility Settings` and ensure `LogixMouseMapper` is enabled.
- `Pass Through (Default)` keeps native button behavior.
