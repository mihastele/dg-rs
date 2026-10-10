//! MySQL/MariaDB database backend using mysql_async.

use crate::db::Database;
use crate::introspect::mysql as intro;
use crate::model::{Column, ConnectionConfig, DbType, ResultSet, Schema, Table, TableKind};
use async_trait::async_trait;
use mysql_async::prelude::*;
use mysql_async::{Pool, Row};
use std::sync::Arc;
use tokio::sync::Mutex;

pub struct MysqlDb {
    config: ConnectionConfig,
    pool: Arc<Mutex<Option<Pool>>>,
}

impl MysqlDb {
    pub fn new(config: ConnectionConfig) -> Self {
        Self {
            config,
            pool: Arc::new(Mutex::new(None)),
        }
    }

    fn build_opts(&self) -> mysql_async::Opts {
        let password = self
            .config
            .password_env
            .as_ref()
            .and_then(|env| std::env::var(env).ok())
            .unwrap_or_default();

        mysql_async::OptsBuilder::default()
            .ip_or_hostname(&self.config.host)
            .tcp_port(self.config.port)
            .db_name(Some(&self.config.database))
            .user(Some(&self.config.user))
            .pass(Some(password))
            .into()
    }
}

#[async_trait]
impl Database for MysqlDb {
    async fn connect(&mut self) -> anyhow::Result<()> {
        // Pre-flight TCP check for better error messages
        let tcp_result = tokio::time::timeout(
            std::time::Duration::from_secs(5),
            tokio::net::TcpStream::connect(format!("{}:{}", self.config.host, self.config.port)),
        )
        .await;

        match tcp_result {
            Ok(Ok(_)) => {}
            Ok(Err(e)) => {
                let lower = format!("{}", e).to_lowercase();
                let hint = if lower.contains("refused") {
                    format!(
                        "Connection refused at {}:{}. Is MySQL running? Check: docker ps | grep mysql",
                        self.config.host, self.config.port
                    )
                } else {
                    format!(
                        "TCP connection to {}:{} failed: {}",
                        self.config.host, self.config.port, e
                    )
                };
                return Err(anyhow::anyhow!("{}", hint));
            }
            Err(_) => {
                return Err(anyhow::anyhow!(
                    "Connection to {}:{} timed out after 5 seconds.",
                    self.config.host, self.config.port
                ));
            }
        }

        let opts = self.build_opts();
        let pool = Pool::new(opts);

        // Test the connection
        let mut conn = pool.get_conn().await.map_err(|e| {
            let err_str = format!("{}", e);
            let lower = err_str.to_lowercase();
            if lower.contains("access denied") || lower.contains("authentication") {
                anyhow::anyhow!(
                    "Authentication failed for user '{}'. Check the password (set MYSQL_PWD env var).",
                    self.config.user
                )
            } else if lower.contains("unknown database") {
                anyhow::anyhow!(
                    "Database '{}' does not exist on {}:{}.",
                    self.config.database, self.config.host, self.config.port
                )
            } else {
                anyhow::anyhow!(
                    "MySQL connection failed at {}:{} (db: {}, user: {}): {}",
                    self.config.host, self.config.port, self.config.database, self.config.user, e
                )
            }
        })?;

        // Return connection to pool
        drop(conn);

        *self.pool.lock().await = Some(pool);
        Ok(())
    }

    async fn server_version(&self) -> anyhow::Result<String> {
        let pool_guard = self.pool.lock().await;
        let pool = pool_guard
            .as_ref()
            .ok_or_else(|| anyhow::anyhow!("Not connected"))?;
        let mut conn = pool.get_conn().await?;
        let version: Option<String> = conn.query_first(intro::SERVER_VERSION).await?;
        Ok(version.unwrap_or_else(|| "unknown".to_string()))
    }

    async fn introspect(&self) -> anyhow::Result<Vec<Schema>> {
        let pool_guard = self.pool.lock().await;
        let pool = pool_guard
            .as_ref()
            .ok_or_else(|| anyhow::anyhow!("Not connected"))?;
        let mut conn = pool.get_conn().await?;

        // Get all schemas
        let schema_rows: Vec<Row> = conn.query(intro::LIST_SCHEMAS).await?;
        let mut schemas = Vec::new();

        for schema_row in &schema_rows {
            let schema_name: String = schema_row.get::<String, _>("name").unwrap_or_default();

            // Get tables in this schema
            let table_rows: Vec<Row> = conn
                .query(intro::list_tables(&schema_name))
                .await?;

            // Get ALL columns for the schema at once (efficient)
            // Filter out system schemas for columns to avoid massive result sets
            let schema_lower = schema_name.to_lowercase();
            if schema_lower == "information_schema"
                || schema_lower == "performance_schema"
                || schema_lower == "mysql"
                || schema_lower == "sys"
            {
                // For system schemas, still get columns but they're less interesting
                // Skip for performance — we already have the table list
                schemas.push(Schema {
                    name: schema_name.clone(),
                    tables: table_rows
                        .iter()
                        .map(|tr| {
                            let tn: String = tr.get::<String, _>("table_name").unwrap_or_default();
                            let tt: String = tr.get::<String, _>("table_type").unwrap_or_default();
                            let tc: Option<String> = tr.get::<Option<String>, _>("table_comment").flatten();
                            Table {
                                name: tn,
                                kind: if tt.contains("VIEW") {
                                    TableKind::View
                                } else {
                                    TableKind::Table
                                },
                                schema: schema_name.clone(),
                                columns: Vec::new(), // Skip columns for system schemas
                                comment: tc.filter(|c| !c.is_empty() && c != "VIEW"),
                            }
                        })
                        .collect(),
                });
                continue;
            }

            let col_rows: Vec<Row> = conn
                .query(intro::list_columns(&schema_name))
                .await?;


            // Get primary keys
            let pk_rows: Vec<Row> = conn
                .query(intro::list_primary_keys(&schema_name))
                .await?;

            // Build PK lookup: (table_name, column_name) -> is_pk
            let mut pk_set: std::collections::HashSet<(String, String)> =
                std::collections::HashSet::new();
            for pk_row in &pk_rows {
                let t: String = pk_row.get::<String, _>("table_name").unwrap_or_default();
                let c: String = pk_row.get::<String, _>("column_name").unwrap_or_default();
                pk_set.insert((t, c));
            }

            // Group columns by table
            let mut cols_by_table: std::collections::HashMap<String, Vec<Column>> =
                std::collections::HashMap::new();
            for col_row in &col_rows {
                // Row::get<T, I>(&self, index) -> Option<T>
                // When T = String, NULL in DB becomes None (which unwrap_or_default turns into "")
                // When T = Option<String>, NULL becomes Some(None)→None, actual value becomes Some(Some(v))→Some(v)
                let table_name: String = col_row.get::<String, _>("table_name").unwrap_or_default();
                let col_name: String = col_row.get::<String, _>("column_name").unwrap_or_default();
                let is_nullable: String = col_row.get::<String, _>("is_nullable").unwrap_or_else(|| "YES".to_string());
                let extra: String = col_row.get::<String, _>("extra").unwrap_or_default();

                let col = Column {
                    name: col_name.clone(),
                    // column_type is never NULL in information_schema, so String is fine
                    type_spec: col_row.get::<String, _>("column_type").unwrap_or_default(),
                    nullable: is_nullable == "YES",
                    is_primary_key: pk_set.contains(&(table_name.clone(), col_name.clone())),
                    // column_default CAN be NULL — use Option<String> to distinguish
                    default_value: col_row.get::<Option<String>, _>("column_default").flatten()
                        .filter(|s| !s.is_empty()),
                    // ordinal_position is never NULL
                    position: col_row.get::<i64, _>("ordinal_position").unwrap_or(0) as i32,
                    // column_comment CAN be NULL/empty
                    comment: col_row.get::<Option<String>, _>("column_comment").flatten()
                        .filter(|c| !c.is_empty()),
                };
                // Mark auto_increment in type_spec
                let mut col = col;
                if extra.contains("auto_increment") {
                    col.type_spec = format!("{} AUTO_INCREMENT", col.type_spec);
                }
                cols_by_table.entry(table_name).or_default().push(col);
            }

            let mut tables = Vec::new();
            for table_row in &table_rows {
                let table_name: String = table_row.get::<String, _>("table_name").unwrap_or_default();
                let table_type: String = table_row.get::<String, _>("table_type").unwrap_or_default();
                // table_comment is Option<String> since it can be NULL or empty
                let comment: Option<String> = table_row.get::<Option<String>, _>("table_comment").flatten();

                let kind = if table_type.contains("VIEW") {
                    TableKind::View
                } else {
                    TableKind::Table
                };

                let columns = cols_by_table.remove(&table_name).unwrap_or_default();

                tables.push(Table {
                    name: table_name,
                    kind,
                    schema: schema_name.clone(),
                    columns,
                    comment: comment.filter(|c| !c.is_empty() && c != "VIEW"),
                });
            }

            schemas.push(Schema {
                name: schema_name,
                tables,
            });
        }

        Ok(schemas)
    }

    async fn query(&self, sql: &str) -> anyhow::Result<ResultSet> {
        let pool_guard = self.pool.lock().await;
        let pool = pool_guard
            .as_ref()
            .ok_or_else(|| anyhow::anyhow!("Not connected"))?;
        let mut conn = pool.get_conn().await?;

        let start = std::time::Instant::now();

        // Use query::<Row, _> to get raw rows, then extract columns from first row
        let rows: Vec<Row> = conn.query(sql).await?;
        let elapsed = start.elapsed();

        // Get column names from the first row (or empty if no rows)
        let column_names: Vec<String> = if let Some(first) = rows.first() {
            first.columns().iter().map(|c| c.name_str().to_string()).collect()
        } else {
            // For empty result sets, try to get column names from the query
            // mysql_async doesn't expose column metadata for empty results easily,
            // so we use a prepared statement approach
            let mut stmt = conn.prep(sql).await?;
            stmt.columns()
                .iter()
                .map(|c| c.name_str().to_string())
                .collect()
        };

        let mut result = ResultSet::new(column_names);
        result.execution_time_ms = elapsed.as_millis() as u64;

        for row in &rows {
            let mut row_data = Vec::new();
            for i in 0..row.len() {
                let value = format_mysql_cell(row, i);
                row_data.push(value);
            }
            result.rows.push(row_data);
        }
        result.row_count = result.rows.len();

        Ok(result)
    }

    async fn execute(&self, sql: &str) -> anyhow::Result<u64> {
        let pool_guard = self.pool.lock().await;
        let pool = pool_guard
            .as_ref()
            .ok_or_else(|| anyhow::anyhow!("Not connected"))?;
        let mut conn = pool.get_conn().await?;
        // exec_drop returns () — use exec_first with a wrapper to get affected rows
        // or use the QueryResult directly
        use mysql_async::prelude::Queryable;
        let _: mysql_async::Result<()> = conn.exec_drop(sql, ()).await;
        // Get affected rows from last insert/exec — mysql_async doesn't return it from exec_drop
        // Use a separate query to get the count
        let affected: Option<u64> = conn
            .query_first("SELECT ROW_COUNT()")
            .await
            .ok()
            .flatten();
        Ok(affected.unwrap_or(0))
    }

    fn db_type(&self) -> DbType {
        DbType::MySql
    }

    fn config(&self) -> &ConnectionConfig {
        &self.config
    }
}

/// Format a cell value from a mysql_async Row into an Option<String>.
fn format_mysql_cell(row: &Row, idx: usize) -> Option<String> {
    use mysql_async::Value;

    // mysql_async's get_opt returns Option<Result<Value, FromValueError>>
    let val: Option<Result<Value, _>> = row.get_opt(idx);

    match val {
        None => None,
        Some(Ok(Value::NULL)) => None,
        Some(Ok(v)) => Some(format_mysql_value(&v)),
        Some(Err(_)) => {
            // Fallback: try as string
            let s: Option<String> = row.get(idx);
            s
        }
    }
}

fn format_mysql_value(v: &mysql_async::Value) -> String {
    use mysql_async::Value;
    match v {
        Value::NULL => "NULL".to_string(),
        Value::Bytes(b) => String::from_utf8_lossy(b).to_string(),
        Value::Int(i) => i.to_string(),
        Value::UInt(u) => u.to_string(),
        Value::Float(f) => f.to_string(),
        Value::Double(d) => d.to_string(),
        Value::Date(y, m, d, hh, mm, ss, _micros) => {
            format!(
                "{:04}-{:02}-{:02} {:02}:{:02}:{:02}",
                y, m, d, *hh, *mm, *ss
            )
        }
        Value::Time(neg, days, hh, mm, ss, micros) => {
            let total_secs = (*days as u64) * 86400
                + (*hh as u64) * 3600
                + (*mm as u64) * 60
                + (*ss as u64);
            let sign = if *neg { "-" } else { "" };
            format!(
                "{}{:02}:{:02}:{:02}{}",
                sign,
                total_secs / 3600,
                (total_secs % 3600) / 60,
                total_secs % 60,
                if *micros > 0 {
                    format!(".{:06}", micros)
                } else {
                    String::new()
                }
            )
        }
    }
}
