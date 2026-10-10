//! PostgreSQL database backend using tokio-postgres.

use crate::db::Database;
use crate::introspect::postgres as intro;
use crate::model::{Column, ConnectionConfig, DbType, ResultSet, Schema, Table, TableKind};
use async_trait::async_trait;
use std::sync::Arc;
use tokio::sync::Mutex;
use tokio_postgres::{Client, NoTls};

pub struct PostgresDb {
    config: ConnectionConfig,
    client: Arc<Mutex<Option<Client>>>,
}

impl PostgresDb {
    pub fn new(config: ConnectionConfig) -> Self {
        Self {
            config,
            client: Arc::new(Mutex::new(None)),
        }
    }

    fn build_connect_string(&self) -> String {
        let password = self
            .config
            .password_env
            .as_ref()
            .and_then(|env| std::env::var(env).ok())
            .unwrap_or_default();

        format!(
            "host={} port={} dbname={} user={} password={}",
            self.config.host, self.config.port, self.config.database, self.config.user, password
        )
    }
}

#[async_trait]
impl Database for PostgresDb {
    async fn connect(&mut self) -> anyhow::Result<()> {
        let conn_str = self.build_connect_string();

        // Pre-flight TCP check: gives a much better error message than
        // tokio-postgres's generic "invalid connection string"
        let tcp_result = tokio::time::timeout(
            std::time::Duration::from_secs(5),
            tokio::net::TcpStream::connect(format!("{}:{}", self.config.host, self.config.port)),
        )
        .await;

        match tcp_result {
            Ok(Ok(_)) => {
                // TCP port is open — proceed with full PG connection
            }
            Ok(Err(e)) => {
                let host = &self.config.host;
                let port = self.config.port;
                let lower = format!("{}", e).to_lowercase();
                let hint = if lower.contains("refused") {
                    format!(
                        "Connection refused at {}:{}. Is PostgreSQL running? Check: pg_isready -h {} -p {}",
                        host, port, host, port
                    )
                } else if lower.contains("timed out") || lower.contains("timeout") {
                    format!(
                        "Connection to {}:{} timed out. Check firewall, network, or if the server is up.",
                        host, port
                    )
                } else if lower.contains("unreachable") || lower.contains("network") {
                    format!(
                        "Network unreachable for {}:{}. Check your network connection and VPN.",
                        host, port
                    )
                } else {
                    format!("TCP connection to {}:{} failed: {}", host, port, e)
                };
                return Err(anyhow::anyhow!("{}", hint));
            }
            Err(_) => {
                return Err(anyhow::anyhow!(
                    "Connection to {}:{} timed out after 5 seconds. The host may be unreachable or firewalled.",
                    self.config.host, self.config.port
                ));
            }
        }

        // TCP is fine — now do the actual PostgreSQL handshake
        let (client, connection) = tokio_postgres::connect(&conn_str, NoTls)
            .await
            .map_err(|e| {
                let host = &self.config.host;
                let port = self.config.port;
                let db = &self.config.database;
                let user = &self.config.user;
                let err_str = format!("{}", e);
                let lower = err_str.to_lowercase();

                // Provide specific guidance based on the error type
                let hint = if lower.contains("password") || lower.contains("authentication") || lower.contains("sasl") {
                    format!("Authentication failed for user '{}'. Check the password (set PGPASSWORD env var).", user)
                } else if lower.contains("database") && (lower.contains("not") || lower.contains("exist")) {
                    format!("Database '{}' does not exist on {}:{}.", db, host, port)
                } else if lower.contains("permission") || lower.contains("denied") {
                    format!("Permission denied for user '{}' on database '{}'.", user, db)
                } else {
                    format!("PostgreSQL handshake failed at {}:{} (db: {}, user: {}): {}", host, port, db, user, e)
                };

                anyhow::anyhow!("{}", hint)
            })?;

        // Spawn the connection handler
        tokio::spawn(async move {
            if let Err(e) = connection.await {
                eprintln!("PostgreSQL connection error: {}", e);
            }
        });

        *self.client.lock().await = Some(client);
        Ok(())
    }

    async fn server_version(&self) -> anyhow::Result<String> {
        let client = self.client.lock().await;
        let client = client.as_ref().ok_or_else(|| anyhow::anyhow!("Not connected"))?;
        let row = client.query_one(intro::SERVER_VERSION, &[]).await?;
        Ok(row.get(0))
    }

    async fn introspect(&self) -> anyhow::Result<Vec<Schema>> {
        let client_guard = self.client.lock().await;
        let client = client_guard
            .as_ref()
            .ok_or_else(|| anyhow::anyhow!("Not connected"))?;

        // Get schemas
        let schema_rows = client.query(intro::LIST_SCHEMAS, &[]).await?;
        let mut schemas = Vec::new();

        for schema_row in &schema_rows {
            let schema_name: String = schema_row.get("name");

            // Get tables in this schema
            let table_rows = client
                .query(&intro::list_tables(&schema_name), &[])
                .await?;
            let mut tables = Vec::new();

            for table_row in &table_rows {
                let table_name: String = table_row.get("table_name");
                let relkind: String = table_row.get("table_kind");
                let comment: Option<String> = table_row.get("comment");

                let kind = match relkind.as_str() {
                    "r" => TableKind::Table,
                    "v" => TableKind::View,
                    "m" => TableKind::MaterializedView,
                    "f" => TableKind::ForeignTable,
                    "p" => TableKind::PartitionedTable,
                    _ => TableKind::Table,
                };

                // Get columns
                let col_rows = client
                    .query(&intro::list_columns(&schema_name, &table_name), &[])
                    .await?;
                let mut columns = Vec::new();

                // Get primary keys
                let pk_rows = client
                    .query(&intro::list_primary_keys(&schema_name, &table_name), &[])
                    .await?;
                let pk_columns: Vec<String> = pk_rows.iter().map(|r| r.get("column_name")).collect();

                for col_row in &col_rows {
                    let col_name: String = col_row.get("column_name");
                    columns.push(Column {
                        name: col_name.clone(),
                        type_spec: col_row.get("type_spec"),
                        nullable: col_row.get("nullable"),
                        is_primary_key: pk_columns.contains(&col_name),
                        default_value: {
                            let dv: String = col_row.get("default_value");
                            if dv.is_empty() { None } else { Some(dv) }
                        },
                        position: col_row.get("column_position"),
                        comment: {
                            let c: String = col_row.get("comment");
                            if c.is_empty() { None } else { Some(c) }
                        },
                    });
                }

                tables.push(Table {
                    name: table_name,
                    kind,
                    schema: schema_name.clone(),
                    columns,
                    comment: comment.filter(|c| !c.is_empty()),
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
        let client_guard = self.client.lock().await;
        let client = client_guard
            .as_ref()
            .ok_or_else(|| anyhow::anyhow!("Not connected"))?;

        let start = std::time::Instant::now();

        // Get column descriptions first
        let stmt = client.prepare(sql).await?;
        let column_names: Vec<String> = stmt
            .columns()
            .iter()
            .map(|c| c.name().to_string())
            .collect();

        let rows = client.query(&stmt, &[]).await?;
        let elapsed = start.elapsed();

        let mut result = ResultSet::new(column_names);
        result.execution_time_ms = elapsed.as_millis() as u64;

        for row in &rows {
            let mut row_data = Vec::new();
            for (i, col) in stmt.columns().iter().enumerate() {
                let value = format_cell(&row, i, col.type_());
                row_data.push(value);
            }
            result.rows.push(row_data);
        }
        result.row_count = result.rows.len();

        Ok(result)
    }

    async fn execute(&self, sql: &str) -> anyhow::Result<u64> {
        let client_guard = self.client.lock().await;
        let client = client_guard
            .as_ref()
            .ok_or_else(|| anyhow::anyhow!("Not connected"))?;
        let count = client.execute(sql, &[]).await?;
        Ok(count)
    }

    fn db_type(&self) -> DbType {
        DbType::Postgres
    }

    fn config(&self) -> &ConnectionConfig {
        &self.config
    }
}

/// Format a cell value from a tokio-postgres row into an Option<String>.
/// Uses the column's OID to determine the type, with graceful fallbacks.
fn format_cell(
    row: &tokio_postgres::Row,
    idx: usize,
    pg_type: &tokio_postgres::types::Type,
) -> Option<String> {
    use tokio_postgres::types::Type;

    // Fast NULL check: try to get as Option<String> — if the value is NULL,
    // this returns Ok(None). But other types may fail to decode as String,
    // so we can't rely on try_get alone. Instead, check by type.
    let result: Option<String> = match *pg_type {
        Type::BOOL => row.try_get::<_, Option<bool>>(idx).ok().flatten().map(|v| v.to_string()),
        Type::INT2 => row.try_get::<_, Option<i16>>(idx).ok().flatten().map(|v| v.to_string()),
        Type::INT4 => row.try_get::<_, Option<i32>>(idx).ok().flatten().map(|v| v.to_string()),
        Type::INT8 => row.try_get::<_, Option<i64>>(idx).ok().flatten().map(|v| v.to_string()),
        Type::FLOAT4 => row.try_get::<_, Option<f32>>(idx).ok().flatten().map(|v| v.to_string()),
        Type::FLOAT8 => row.try_get::<_, Option<f64>>(idx).ok().flatten().map(|v| v.to_string()),
        Type::TEXT | Type::VARCHAR | Type::NAME | Type::BPCHAR => {
            row.try_get::<_, Option<String>>(idx).ok().flatten()
        }
        Type::JSON | Type::JSONB => {
            row.try_get::<_, Option<serde_json::Value>>(idx)
                .ok()
                .flatten()
                .map(|v| v.to_string())
        }
        Type::BYTEA => row
            .try_get::<_, Option<Vec<u8>>>(idx)
            .ok()
            .flatten()
            .map(|v| format!("\\x{}", hex_encode(&v))),
        Type::TIMESTAMP => row
            .try_get::<_, Option<chrono::NaiveDateTime>>(idx)
            .ok()
            .flatten()
            .map(|v| v.to_string()),
        Type::TIMESTAMPTZ => row
            .try_get::<_, Option<chrono::DateTime<chrono::Utc>>>(idx)
            .ok()
            .flatten()
            .map(|v| v.to_string()),
        Type::DATE => row
            .try_get::<_, Option<chrono::NaiveDate>>(idx)
            .ok()
            .flatten()
            .map(|v| v.to_string()),
        Type::UUID => {
            // UUID without the uuid crate: read as string (tokio-postgres can decode UUID as String in text mode)
            // or as raw bytes
            row.try_get::<_, Option<String>>(idx)
                .ok()
                .flatten()
                .or_else(|| {
                    row.try_get::<_, Option<Vec<u8>>>(idx)
                        .ok()
                        .flatten()
                        .map(|v| {
                            if v.len() == 16 {
                                format!(
                                    "{:02x}{:02x}{:02x}{:02x}-{:02x}{:02x}-{:02x}{:02x}-{:02x}{:02x}-{:02x}{:02x}{:02x}{:02x}{:02x}{:02x}",
                                    v[0], v[1], v[2], v[3], v[4], v[5], v[6], v[7],
                                    v[8], v[9], v[10], v[11], v[12], v[13], v[14], v[15]
                                )
                            } else {
                                hex_encode(&v)
                            }
                        })
                })
        }
        Type::NUMERIC => {
            // NUMERIC is returned as bytes in binary format; try text representation
            row.try_get::<_, Option<String>>(idx)
                .ok()
                .flatten()
                .or_else(|| {
                    row.try_get::<_, Option<Vec<u8>>>(idx)
                        .ok()
                        .flatten()
                        .map(|v| String::from_utf8_lossy(&v).to_string())
                })
        }
        Type::OID => row.try_get::<_, Option<u32>>(idx).ok().flatten().map(|v| v.to_string()),
        // Arrays: try as Vec<String> first, then as raw text
        _ if pg_type.name().starts_with('_') => {
            row.try_get::<_, Option<Vec<String>>>(idx)
                .ok()
                .flatten()
                .map(|v| format!("{{{}}}", v.join(", ")))
                .or_else(|| row.try_get::<_, Option<String>>(idx).ok().flatten())
        }
        _ => {
            // Generic fallback: try as string, then as bytes
            row.try_get::<_, Option<String>>(idx)
                .ok()
                .flatten()
                .or_else(|| {
                    row.try_get::<_, Option<Vec<u8>>>(idx)
                        .ok()
                        .flatten()
                        .map(|v| String::from_utf8_lossy(&v).to_string())
                })
                .or(Some(format!("<{}>", pg_type.name())))
        }
    };

    result
}

fn hex_encode(bytes: &[u8]) -> String {
    bytes.iter().map(|b| format!("{:02x}", b)).collect()
}
