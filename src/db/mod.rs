//! Database connection abstraction.
//! Trait-based so we can support Postgres, SQLite, MySQL behind one interface.

use crate::model::{ConnectionConfig, DbType, ResultSet, Schema};
use async_trait::async_trait;

pub mod postgres;
pub mod sqlite;

#[async_trait]
pub trait Database: Send {
    /// Test the connection.
    async fn connect(&mut self) -> anyhow::Result<()>;

    /// Get server version info.
    async fn server_version(&self) -> anyhow::Result<String>;

    /// List all schemas with their tables.
    async fn introspect(&self) -> anyhow::Result<Vec<Schema>>;

    /// Execute a query and return results.
    async fn query(&self, sql: &str) -> anyhow::Result<ResultSet>;

    /// Execute a statement that doesn't return rows (DDL, etc.)
    async fn execute(&self, sql: &str) -> anyhow::Result<u64>;

    /// Get the database type.
    fn db_type(&self) -> DbType;

    /// Get the connection config.
    fn config(&self) -> &ConnectionConfig;
}

/// Factory: create a database connection from config.
pub async fn create_connection(
    config: &ConnectionConfig,
) -> anyhow::Result<Box<dyn Database>> {
    match config.db_type {
        DbType::Postgres => {
            let mut db = postgres::PostgresDb::new(config.clone());
            db.connect().await?;
            Ok(Box::new(db))
        }
        DbType::Sqlite => {
            let mut db = sqlite::SqliteDb::new(config.clone());
            db.connect().await?;
            Ok(Box::new(db))
        }
        DbType::MySql => anyhow::bail!("MySQL support coming in v0.2"),
    }
}
