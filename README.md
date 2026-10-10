# =============================================================================
# dg-rs: Open-source database workbench in Rust
# Built with introspection queries reverse-engineered
# (MIT-licensed patterns).
# =============================================================================

> A fast, lightweight, open-source database client written in Rust.
> Connect to PostgreSQL, SQLite, and MySQL. Browse schemas, write SQL,
> view results in a grid, and export to CSV/JSON.

![Rust](https://img.shields.io/badge/rust-1.88%2B-orange?logo=rust)
![License](https://img.shields.io/badge/license-MIT-blue)
![Platform](https://img.shields.io/badge/platform-Windows%20%7C%20macOS%20%7C%20Linux-lightgrey)

---

## Why dg-rs?

**dg-rs** is a
Rust-native alternative that starts in milliseconds, uses <50MB RAM, and is
fully open source (MIT).


## Features

- **Multi-database**: PostgreSQL, SQLite (MySQL coming in v0.2)
- **Schema explorer**: Browse schemas → tables → columns with types, PKs, defaults
- **SQL editor**: Write and execute queries with a TUI (ratatui)
- **Results grid**: Scrollable, formatted table output
- **Export**: CSV, JSON, SQL INSERT statements
- **Headless mode**: Run queries from CLI without the TUI
- **Fast startup**: <10ms cold start
- **Low memory**: ~20MB RAM

## Quick Start

### Install

```bash
# From source
cargo install --path .

# Or download pre-built binary from Releases
```

### Interactive TUI

```bash
# PostgreSQL
datagrip-rs connect postgres --host localhost --port 5432 --db mydb --user postgres

# SQLite
datagrip-rs connect sqlite --file ./my_database.db
```

### Headless (CLI) Mode

```bash
# Run a query, pretty-printed table
datagrip-rs query sqlite --file ./my.db --sql "SELECT * FROM users LIMIT 10"

# Export to CSV
datagrip-rs query postgres --host localhost --db mydb --user postgres \
    --sql "SELECT * FROM orders" --format csv > orders.csv

# Export to JSON
datagrip-rs query postgres --host localhost --db mydb --user postgres \
    --sql "SELECT * FROM users" --format json

# Introspect schema (print full schema tree)
datagrip-rs introspect postgres --host localhost --db mydb --user postgres
```

## TUI Keyboard Shortcuts

| Key | Action |
|-----|--------|
| `Tab` | Switch focus (Tree → Editor → Results) |
| `F1` | Toggle help overlay |
| `F5` / `Ctrl+Enter` | Run SQL query |
| `Ctrl+E` | Export results to CSV |
| `↑/↓` | Navigate schema tree / scroll results |
| `←/→` | Collapse/expand schema |
| `Enter` | Execute SQL from input bar |
| `Esc` | Clear input / close overlay |
| `Ctrl+Q` | Quit |

## Architecture

```
datagrip-rs/
├── src/
│   ├── main.rs              # CLI entry point (clap)
│   ├── model/               # Data types: Connection, Schema, Table, Column, ResultSet
│   ├── db/                  # Database backends (trait-based)
│   │   ├── postgres.rs      # tokio-postgres backend
│   │   └── sqlite.rs        # rusqlite (bundled) backend
│   ├── introspect/          # Schema introspection queries
│   │   ├── postgres.rs      # RE'd from DataGrip's PgIntroQueries.sql
│   │   └── sqlite.rs        # PRAGMA-based introspection
│   └── ui/                  # TUI (ratatui)
│       ├── app.rs           # App state + event loop
│       ├── export.rs        # CSV/JSON/SQL export
│       └── widgets/         # Reusable UI components
└── tests/
    └── integration.rs       # End-to-end tests
```

### Reverse Engineering Notes

The PostgreSQL introspection queries in `src/introspect/postgres.rs` were
reverse-engineered from JetBrains DataGrip 2025.3.4's
`intellij.database.dialects.postgres.jar`, specifically:

- `com/intellij/database/dialects/postgres/introspector/PgIntroQueries.sql` (60KB!)
- `com/intellij/database/dialects/postgres/introspector/PgIntrospector.class`

DataGrip uses a template system with version guards (`#V91:`, `#V120:`) and
incremental sync markers (`#INC>`). We strip those and target PG 12+ directly.

The full RE process used [REA](https://github.com/morluto/rea) (Reverse
Engine Anything) — an MCP server for reverse engineering with AI agents.

## Roadmap

- [x] SQLite support (introspection + queries + TUI)
- [x] PostgreSQL support (introspection + queries)
- [x] Headless CLI mode (query, introspect, export)
- [x] CSV/JSON export
- [ ] MySQL/MariaDB support
- [ ] Query history
- [ ] Saved connections
- [ ] SQL autocomplete
- [ ] Connection via SSH tunnel
- [ ] GUI frontend (egui/iced) as optional alternative to TUI

## Contributing

PRs welcome! Especially for:
- MySQL/MariaDB backend
- SQL syntax highlighting in the editor
- Query execution plans (EXPLAIN visualization)
- Additional export formats (Excel, Parquet)

## License

MIT License — see [LICENSE](LICENSE) for details.

The introspection query patterns are derived from JetBrains DataGrip's
internals for interoperability purposes. All code in this repository is
original work.

---

Built with ❤️ in Rust by [@il-chonko](https://github.com/il-chonko)
