//! TUI module - ratatui-based terminal UI.
//!
//! Layout (DataGrip-inspired):
//! ┌─────────────────────────────────────────────────────────────┐
//! │ datagrip-rs │ postgres@localhost │ 12.3 │ 3 tables          │  ← status bar
//! ├──────────────┬──────────────────────────────────────────────┤
//! │ Schema Tree  │                                              │
//! │ ▸ public     │         SQL Editor / Results Grid            │
//! │   📋 users   │                                              │
//! │   📋 orders  │   ┌─────────────────────────────────────┐  │
//! │   👁 v_revenue│  │ SELECT * FROM users LIMIT 10;       │  │
//! │ ▸ app        │  └─────────────────────────────────────┘  │
//! │   ...        │   ┌─────────────────────────────────────┐  │
//! │              │   │ id │ name    │ email               │  │
//! │ [+ New Conn] │   │────┼─────────┼─────────────────────│  │
//! │ [⚙ Settings] │   │ 1  │ Alice   │ alice@example.com   │  │
//! │              │   │ 2  │ Bob     │ bob@example.com     │  │
//! │              │   └─────────────────────────────────────┘  │
//! ├──────────────┴──────────────────────────────────────────────┤
//! │ > _  (SQL input)                                  [F5: Run]  │  ← input bar
//! └─────────────────────────────────────────────────────────────┘

pub mod app;
pub mod export;
pub mod widgets;
