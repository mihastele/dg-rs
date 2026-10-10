//! SQLite database backend using rusqlite (bundled).

use crate::db::Database;
use crate::introspect::sqlite as intro;
use crate::model::{Column, ConnectionConfig, DbType, ResultSet, Schema, Table, TableKind};
use async_trait::async_trait;
use rusqlite::Connection;
use std::sync::{Arc, Mutex};

pub struct SqliteDb {
    config: ConnectionConfig,
    conn: Arc<Mutex<Option<Connection>>>,
}

impl SqliteDb {
    pub fn new(config: ConnectionConfig) -> Self {
        Self {
            config,
            conn: Arc::new(Mutex::new(None)),
        }
    }
}

#[async_trait]
impl Database for SqliteDb {
    async fn connect(&mut self) -> anyhow::Result<()> {
        let path = self
            .config
            .file_path
            .as_deref()
            .ok_or_else(|| anyhow::anyhow!("SQLite: no file path configured"))?;

        let conn = Connection::open(path)?;
        // Enable foreign keys
        conn.execute("PRAGMA foreign_keys = ON", [])?;
        *self.conn.lock().unwrap() = Some(conn);
        Ok(())
    }

    async fn server_version(&self) -> anyhow::Result<String> {
        let conn_guard = self.conn.lock().unwrap();
        let conn = conn_guard.as_ref().ok_or_else(|| anyhow::anyhow!("Not connected"))?;
        let version: String = conn.query_row(intro::SQLITE_VERSION, [], |r| r.get(0))?;
        Ok(format!("SQLite {}", version))
    }

    async fn introspect(&self) -> anyhow::Result<Vec<Schema>> {
        let conn_guard = self.conn.lock().unwrap();
        let conn = conn_guard.as_ref().ok_or_else(|| anyhow::anyhow!("Not connected"))?;

        // SQLite has one implicit schema: "main"
        let mut stmt = conn.prepare(intro::LIST_OBJECTS)?;
        let rows = stmt.query_map([], |row| {
            Ok((
                row.get::<_, String>(0)?, // type
                row.get::<_, String>(1)?, // name
                row.get::<_, String>(2)?, // tbl_name
                row.get::<_, Option<String>>(3)?, // sql
            ))
        })?;

        let mut tables = Vec::new();

        for row in rows {
            let (obj_type, name, _tbl_name, _sql) = row?;

            let kind = match obj_type.as_str() {
                "table" => TableKind::Table,
                "view" => TableKind::View,
                _ => continue, // Skip indexes, triggers for now
            };

            // Get columns via PRAGMA
            let col_stmt = format!(r#"PRAGMA table_info("{}")"#, name.replace('"', ""));
            let mut col_prep = conn.prepare(&col_stmt)?;
            let col_rows = col_prep.query_map([], |r| {
                Ok(Column {
                    name: r.get(1)?,
                    type_spec: r.get::<_, String>(2)?,
                    nullable: r.get::<_, i32>(3)? == 0,
                    is_primary_key: r.get::<_, i32>(5)? > 0,
                    default_value: r.get::<_, Option<String>>(4)?,
                    position: r.get(0)?,
                    comment: None,
                })
            })?;

            let columns: Vec<Column> = col_rows.collect::<Result<_, _>>()?;

            tables.push(Table {
                name,
                kind,
                schema: "main".to_string(),
                columns,
                comment: None,
            });
        }

        Ok(vec![Schema {
            name: "main".to_string(),
            tables,
        }])
    }

    async fn query(&self, sql: &str) -> anyhow::Result<ResultSet> {
        let conn_guard = self.conn.lock().unwrap();
        let conn = conn_guard.as_ref().ok_or_else(|| anyhow::anyhow!("Not connected"))?;

        let start = std::time::Instant::now();

        let mut stmt = conn.prepare(sql)?;
        let column_names: Vec<String> = stmt
            .column_names()
            .iter()
            .map(|s| s.to_string())
            .collect();

        let col_count = stmt.column_count();
        let mut result = ResultSet::new(column_names);

        let rows = stmt.query_map([], |row| {
            let mut values = Vec::with_capacity(col_count);
            for i in 0..col_count {
                let val: rusqlite::types::Value = row.get(i)?;
                values.push(Some(format_sqlite_value(&val)));
            }
            Ok(values)
        })?;

        for row in rows {
            result.rows.push(row?);
        }

        result.row_count = result.rows.len();
        result.execution_time_ms = start.elapsed().as_millis() as u64;

        Ok(result)
    }

    async fn execute(&self, sql: &str) -> anyhow::Result<u64> {
        let conn_guard = self.conn.lock().unwrap();
        let conn = conn_guard.as_ref().ok_or_else(|| anyhow::anyhow!("Not connected"))?;
        let count = conn.execute(sql, [])?;
        Ok(count as u64)
    }

    fn db_type(&self) -> DbType {
        DbType::Sqlite
    }

    fn config(&self) -> &ConnectionConfig {
        &self.config
    }
}

fn format_sqlite_value(val: &rusqlite::types::Value) -> String {
    use rusqlite::types::Value;
    match val {
        Value::Null => "NULL".to_string(),
        Value::Integer(i) => i.to_string(),
        Value::Real(f) => f.to_string(),
        Value::Text(s) => s.clone(),
        Value::Blob(b) => format!("<{} bytes>", b.len()),
    }
}
