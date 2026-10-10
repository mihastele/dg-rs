//! SQLite introspection queries.
//!
//! Reverse-engineered from JetBrains DataGrip's `SqliteIntrospector` classes.
//! SQLite introspection uses `sqlite_master`, `PRAGMA table_info()`, etc.

/// List all tables and views from sqlite_master.
/// From DataGrip: `SqliteIntrospector$SqliteSchemaRetriever`
pub const LIST_OBJECTS: &str = r#"
SELECT type, name, tbl_name, sql
FROM sqlite_master
WHERE name NOT LIKE 'sqlite_%'
ORDER BY type, name
"#;

/// Get column info for a table using PRAGMA.
/// From DataGrip: `SqliteIntroQueries$ColumnInfo`
pub fn pragma_table_info(table: &str) -> String {
    format!("PRAGMA table_info(\"{table}\")")
}

/// Get foreign key info for a table.
/// From DataGrip: `SqliteIntroQueries$ForeignKeyInfo`
pub fn pragma_foreign_key_list(table: &str) -> String {
    format!("PRAGMA foreign_key_list(\"{table}\")")
}

/// Get index list for a table.
/// From DataGrip: `SqliteIntroQueries$IndexInfo`
pub fn pragma_index_list(table: &str) -> String {
    format!("PRAGMA index_list(\"{table}\")")
}

/// Get index column info.
/// From DataGrip: `SqliteIntroQueries$IndexColumnInfo`
pub fn pragma_index_info(index: &str) -> String {
    format!("PRAGMA index_info(\"{index}\")")
}

/// Get the SQLite version.
pub const SQLITE_VERSION: &str = "SELECT sqlite_version()";

/// List attached databases.
pub const PRAGMA_DATABASE_LIST: &str = "PRAGMA database_list";
