# Overseer

Overseer is a MacroQuest (MQ) Lua plugin that automates and monitors in-game quest rotation, reward collection, and optional local quest-data ingestion. It provides a configurable ImGui UI, a CLI for scripted control, and an optional local SQLite database to speed lookups and enable validation.

This README gives a practical overview, installation steps, usage examples, configuration guidance, safety notes about database writes, and development pointers.

---

## Table of contents

- Overview
- Features
- Requirements
- Installation
- Quick start
- UI tour
- CLI commands and examples
- Important settings (what they do)
- Database behavior & safety (must-read)
- Logging & troubleshooting
- Development & contributing
- License

---

## Overview

Overseer helps automate:
- Periodic quest rotations and runs
- Claiming quest rewards (configurable)
- Selecting quests by priority (level/duration/rarity/type)
- Optionally storing and validating known quest reward data in a local DB

It is designed to be safe-by-default: DB writes and aggressive debug modes are opt-in and guarded to avoid accidental data corruption.

---

## Features

- ImGui-based UI with multiple tabs: Status, Settings, Actions, Stats (plus Test when enabled)
- Persistent settings per character or global (INI)
- Optional SQLite DB of known quests (faster lookups, validation)
- Test and validation modes to preview or ingest quest data
- Logging at multiple levels including Trace for deep debugging
- Command-line interface via `/mqoverseer` for automation and scripting

---

## Requirements

- MacroQuest (MQ) with Lua and ImGui support
- The MQ Lua environment used by your setup (this project uses MQ's Lua + ImGui)
- Optional: sqlite3 bindings if you plan to use the local DB features

---

## Installation

1. Clone the repository into your MQ scripts directory:
   - Example: `git clone https://github.com/cannonballdex/Overseer.git Overseer`
2. Ensure any required Lua modules used by the repository are on MQ's Lua path.
3. Start MacroQuest and run:
   - `/lua run overseer` (or add to your auto-load scripts)

---

## Quick start

1. Start Overseer and open the UI.
2. In the Settings tab -> General:
   - Toggle "Load known quests from database" if you have a populated DB and want fast lookups.
3. If you're only exploring, leave all DB-write debug options off (safe default).
4. Use the Actions tab to run a full cycle (`Run Full Cycle`) or preview the next rotation.
5. To inspect differences between live UI values and DB values, enable `Validate Quest Reward Data` (this is a dry-run unless you enable DB update flags).

---

## UI tour

- Status (formerly General): shows next quest completion, rotation, character info, and common quick actions.
- Settings: grouped sections for General, Rewards, Quest Priority, Debug/Test options.
- Actions: run manual cycles, run unit tests, or trigger special flows.
- Stats: runtime metrics and historical statistics.
- Test: appears only when Test Mode is enabled and contains ingestion/validation controls.

Note: ImGui allows tab reordering; you can drag the Status tab back to the first position or disable reordering in code.

---

## CLI commands (examples)

Overseer exposes multiple commands through `/mqoverseer`. A few useful examples:

- Toggle DB usage:
  - `/mqoverseer useDatabase false`
- Toggle adding quests to DB (debug):
  - `/mqoverseer addToDatabase true`
- Toggle validation mode:
  - `/mqoverseer validateQuestRewardData true`
- Run a full automated cycle:
  - `/mqoverseer runFullCycle`
- Output current quest details:
  - `/mqoverseer outputQuestDetails`
- Add/remove specific quests:
  - `/mqoverseer addSpecificQuest "Quest Name"`
  - `/mqoverseer removeSpecificQuest "Quest Name"`

See `overseer_settings_commands.lua` for the full command list.

---

## Important settings (what they do)

- Settings.General.useQuestDatabase
  - true: load quest details from local DB (fast)
  - false: parse the in-game Overseer UI for current quest data (fresh but slower)
  - When toggled the UI logs an informative warning/info message.

- Settings.Debug.processFullQuestRewardData (Add Quests to Database)
  - When enabled, Overseer will insert new quests discovered during parsing into the DB. Intended for controlled ingestion. Default: false.

- Settings.Debug.validateQuestRewardData (Validate Quest Reward Data)
  - When enabled, Overseer compares the DB value vs currently displayed reward XP and logs discrepancies. Default: false.

- Settings.Debug.updateQuestDatabaseOnValidate
  - When true and validation finds a mismatch, Overseer will update the DB entry. Default: false.

- Settings.General.rewards.claimRewards
  - Controls whether rewards are automatically claimed via MQ2Rewards. Use with care.

Notes
- Many debug flags are intentionally non-persistent by default to avoid accidental writes. See "Database behavior & safety" below.

---

## Database behavior & safety (READ THIS CAREFULLY)

Overseer supports an optional local quest DB. Because DB writes can be destructive or misleading, follow these rules:

- Default policy: DB writes are opt-in and guarded.
  - New-quest ingestion requires `Add Quests to Database`.
  - Updates on validation require `Update DB on validate`.
- Recommended workflow:
  1. Enable `Validate Quest Reward Data` (dry-run) to log differences.
  2. Inspect the log output for unexpected values (zeros, huge numbers).
  3. If results look correct, either enable `Add Quests to Database` for ingestion or `Update DB on validate` to apply changes.
- Batch & preview:
  - Prefer buffering changes during a run and applying them as a batch at the cycle end. (The codebase can be extended to support a preview/confirm flow if desired.)
- Persistence of debug flags:
  - Legacy initializer may reset some debug flags on startup to avoid accidental persistence. If you want a debug flag to persist, change the initializer deliberately and understand the risk.
- XP variance across characters:
  - Quest reward XP often varies by character level or level cap. Avoid blind overwrites of a single numeric XP field. Consider switching to per-level or per-cap storage (JSON field or separate table) before enabling large-scale ingestion across characters.
- Backups:
  - Before performing any bulk DB writes/migrations, make a DB backup.

---

## Logging & troubleshooting

- Use Settings -> General -> Log Level to increase verbosity. `Trace` provides very detailed diagnostics.
- Typical log messages:
  - Info when switching DB usage.
  - "EXP VIOLATION" when stored DB value and current UI value differ.
  - Warnings when UI elements are not ready and actions are skipped.
- Troubleshooting tips:
  - If tabs appear in unexpected order, ImGui remembers reordering—drag them back or remove/recreate ImGui settings (`imgui.ini`) to reset.
  - If the UI fails to render or errors on load, check MQ logs for Lua syntax or module require failures.
  - If DB writes occur unexpectedly, verify that `processFullQuestRewardData` or `updateQuestDatabaseOnValidate` are false and that Test Mode isn't re-enabling them.

---

## Development & contributing

- Code layout (high level):
  - `overseer.lua` — core automation and parsing logic
  - `overseerui.lua` — ImGui UI
  - `overseer_settings.lua` / `overseer_settings_legacy.lua` — settings load/save and legacy migration
  - `overseer_settings_commands.lua` — CLI command handlers
  - `database.lua` or equivalent DB module — DB access
  - `overseer.utils.logger` — logging helper
- Testing:
  - Add unit tests for parsing and string utilities; run tests via UI Actions -> Run Unit Tests (if present).
- DB schema changes:
  - When adding per-level XP or changing schema, include:
    - Migration code that safely upgrades existing DBs
    - Automated DB backup before first write after upgrade
    - Tests or a preview/confirm UI to inspect proposed changes
- PR checklist:
  - Describe functional changes, DB migrations, and backup steps
  - Keep debug-write flags transient unless explicitly required to be persistent
  - Update README and any in-UI help text for new behavior

---

## Examples

- Set log level to Trace via Lua console:
```lua
Settings.General.logLevel = 6 -- Trace
settings.SetLogLevel(6)
settings.SaveSettings()
```

- Disable DB usage and run a full cycle:
```
/mqoverseer useDatabase false
/mqoverseer runFullCycle
```

---

## License

Add your preferred license here (e.g., MIT, Apache-2.0). Please include a LICENSE file in the repo.

---

## Help & contact

Open an issue on the project repo for bugs and feature requests. For implementation help or to propose changes, submit a PR with clear migration steps if DB changes are included.

---

If you'd like, I can:
- Open a PR that replaces the current README.md with this version,
- Produce a shorter QuickStart-only README,
- Or tweak this draft to match the exact tone/content of your previous README—tell me what you want copied back and I'll integrate it.
