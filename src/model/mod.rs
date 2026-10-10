//! Core data model for database objects.
//! Inspired by DataGrip's introspection model (reverse-engineered from
//! `PgIntroQueries.sql` and the `*Introspector` classes).

use serde::{Deserialize, Serialize};

/// A database connection configuration.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ConnectionConfig {
    pub name: String,
    pub db_type: DbType,
    pub host: String,
    pub port: u16,
    pub database: String,
    pub user: String,
    /// Password is loaded from env var or OS keychain at runtime, never stored here.
    pub password_env: Option<String>,
    /// For SQLite: path to the database file.
    pub file_path: Option<String>,
}

impl ConnectionConfig {
    pub fn postgres(host: &str, port: u16, database: &str, user: &str) -> Self {
        Self {
            name: format!("{}@{}", user, host),
            db_type: DbType::Postgres,
            host: host.to_string(),
            port,
            database: database.to_string(),
            user: user.to_string(),
            password_env: Some("PGPASSWORD".to_string()),
            file_path: None,
        }
    }

    pub fn sqlite(name: &str, file_path: &str) -> Self {
        Self {
            name: name.to_string(),
            db_type: DbType::Sqlite,
            host: String::new(),
            port: 0,
            database: file_path.to_string(),
            user: String::new(),
            password_env: None,
            file_path: Some(file_path.to_string()),
        }
    }

    pub fn connection_string(&self) -> String {
        match self.db_type {
            DbType::Postgres => format!(
                "postgres://{}:{}@{}:{}/{}",
                self.user, "***", self.host, self.port, self.database
            ),
            DbType::Sqlite => format!("sqlite://{}", self.file_path.as_deref().unwrap_or("")),
            DbType::MySql => format!(
                "mysql://{}:{}@{}:{}/{}",
                self.user, "***", self.host, self.port, self.database
            ),
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum DbType {
    Postgres,
    Sqlite,
    MySql,
}

impl std::fmt::Display for DbType {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            DbType::Postgres => write!(f, "PostgreSQL"),
            DbType::Sqlite => write!(f, "SQLite"),
            DbType::MySql => write!(f, "MySQL"),
        }
    }
}

/// A schema in the database.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Schema {
    pub name: String,
    pub tables: Vec<Table>,
}

/// A table (or view, materialized view, foreign table, partitioned table).
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Table {
    pub name: String,
    pub kind: TableKind,
    pub schema: String,
    pub columns: Vec<Column>,
    pub comment: Option<String>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum TableKind {
    Table,
    View,
    MaterializedView,
    ForeignTable,
    PartitionedTable,
}

impl TableKind {
    pub fn icon(&self) -> &'static str {
        match self {
            TableKind::Table => "📋",
            TableKind::View => "👁",
            TableKind::MaterializedView => "📦",
            TableKind::ForeignTable => "🌐",
            TableKind::PartitionedTable => "🗂",
        }
    }

    pub fn label(&self) -> &'static str {
        match self {
            TableKind::Table => "table",
            TableKind::View => "view",
            TableKind::MaterializedView => "matview",
            TableKind::ForeignTable => "ftable",
            TableKind::PartitionedTable => "ptable",
        }
    }
}

/// A column in a table.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Column {
    pub name: String,
    pub type_spec: String,
    pub nullable: bool,
    pub is_primary_key: bool,
    pub default_value: Option<String>,
    pub position: i32,
    pub comment: Option<String>,
}

/// A query result set.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ResultSet {
    pub columns: Vec<String>,
    pub rows: Vec<Vec<Option<String>>>,
    pub row_count: usize,
    pub execution_time_ms: u64,
    pub statement_tag: Option<String>,
}

impl ResultSet {
    pub fn new(columns: Vec<String>) -> Self {
        Self {
            columns,
            rows: Vec::new(),
            row_count: 0,
            execution_time_ms: 0,
            statement_tag: None,
        }
    }
}
