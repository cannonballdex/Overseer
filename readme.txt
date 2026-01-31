# Overseer

Overseer is a Lua-based MacroQuest plugin to manage quests, agents, and related UI tooling for EverQuest. It provides a settings system, persistent quest database (SQLite), an ImGui-based UI, and utilities for configuration and file handling.

Version: 5.0 Beta

## Table of Contents

- [Features](#features)
- [Status](#status)
- [Requirements](#requirements)
- [Installation](#installation)
- [Quick Start / Usage](#quick-start--usage)
- [Configuration](#configuration)
- [Database](#database)
- [Testing](#testing)
- [Development notes](#development-notes)
- [Contributing](#contributing)
- [License](#license)

## Features

- Quest and agent management with statistics and ordering
- Persisted quest database using SQLite
- Settings with automatic migration from older formats
- ImGui-based UI with controls and tools (including a "Run Unit Tests" button)
- Utilities bundled: LIP (Lightweight INI Parser), rxi-json, argparse, io utilities

## Status

This repository is marked as "5.0 Beta". Core functionality appears implemented and includes settings migration logic and unit test hooks. The README is intentionally compact; see "Development notes" for items to consider improving.

## Requirements

- MacroQuest (mq) with Lua environment and ImGui integration
- LuaJIT (for ffi) — typically provided by MacroQuest
- lfs (LuaFileSystem) — the repo attempts to ensure this via the included PackageMan hook
- lsqlite3 (lsqlite3 library) — used for persisting the quest database
- Platform: Windows is expected (some code uses the Windows Kernel32 CreateDirectoryA via ffi)

Note: The plugin's `init.lua` contains helper logic to `require` and install packages via `mq/PackageMan` if not present. In many cases those dependencies will be installed automatically when Overseer starts.

## Installation

Option A — Manual
1. Place the `overseer` plugin files into your MacroQuest lua directory. Typical structure:
   - <mq.luaDir>/overseer/*.lua
   - <mq.luaDir>/overseer/lib/*
   - <mq.luaDir>/overseer/utils/*

2. Start MacroQuest and load the plugin (or restart MQ so it picks up Lua files).

Option B — PackageMan (if available)
- Overseer attempts to auto-install `luafilesystem` and `lsqlite3` using `mq/PackageMan`. Ensure `PackageMan` is available in your MQ installation.

## Quick Start / Usage

- Load Overseer via your usual MacroQuest Lua loading mechanism (e.g. placed in the MQ lua directory).
- Open the UI to interact with Overseer (overseerui) — the UI exposes settings, database controls, and a "Run Unit Tests" button.
- If the plugin cannot find dependencies it will try to install them via PackageMan. Check logs for output.

## Configuration

- Settings are stored and managed by `overseer_settings.lua` with migration support in `overseer_settings_legacy.lua`.
- Default paths are computed in `utils/io_utils.lua`. Per-lua-file data directory is created underneath the MQ lua path, e.g.:
  - data dir: `<mq.luaDir>/overseer/data`

- Many settings are available via the UI. The code also exposes utility functions for reading/writing INI-style configuration via `lib/LIP.lua`.

## Database

- Overseer persists known quests in a SQLite3 DB (via `lsqlite3`).
- On startup the plugin will decide whether to copy a shared DB to a per-character DB based on row counts (see `init.lua` and the `get_quest_count`/`ensure_perchar_db` logic).
- If you see errors opening the DB, ensure `lsqlite3` is installed and accessible to the MQ Lua environment.

## Testing

- The UI includes a "Run Unit Tests" button which triggers `tests.RunTests()` (if present).
- You can also invoke test functions programmatically via the Lua console if required.

## Development notes / Known considerations

- io_utils uses LuaJIT FFI to call `CreateDirectoryA` (Kernel32). The declared prototype in the code may not match the system/WinAPI signature exactly; lfs.mkdir is also used in places. Consider standardizing on `lfs.mkdir` for portability and simplicity, or ensure the ffi prototype matches the WinAPI signature exactly to avoid undefined behavior.
- Path normalization: the code normalizes backslashes to forward slashes and lowercases paths in a few helpers. On case-sensitive hosts this could be surprising; this behavior is intended for MQ on Windows but document or adapt when running elsewhere.
- Sorting: some ordering logic uses a simple O(n^2) algorithm. For larger lists consider using `table.sort()` with a comparator for performance.
- Third-party libraries included:
  - rxi-json (MIT) — included in `utils/json.lua` (license header included)
  - argparse (MIT) — included in `utils/argparse.lua`
  - LIP (INI parser) — included in `lib/LIP.lua` (license header present)
- README/Docs: The repository's top-level readme is minimal. Expanding documentation (usage examples, screenshots, config reference) is recommended.

## Contributing

- Bug reports, feature requests, and pull requests are welcome.
- When submitting PRs, include test coverage for behavioral changes where applicable.
- Respect third-party licenses and keep attributions intact for included libraries.

## Troubleshooting

- If Overseer fails to start due to missing Lua modules, check MQ logs — PackageMan may attempt an automatic install. You can manually install `luafilesystem` and `lsqlite3` for your MQ Lua runtime if needed.
- If database operations fail, confirm `lsqlite3` is present and that the MQ process has write permissions to the data directory `<mq.luaDir>/overseer/data`.
- If you encounter crashes related to FFI calls (CreateDirectoryA), consider switching to `lfs.mkdir` as a safer alternative.

## License

The project includes code under permissive licenses (see headers in `utils/json.lua`, `utils/argparse.lua`, etc.). The rest of the project is distributed under the MIT License (if that is your intended license). Please add a top-level `LICENSE` file to the repository if you want to make the license explicit.

## Contact / Author

Cannonballdex — repository: `cannonballdex/Overseer`
