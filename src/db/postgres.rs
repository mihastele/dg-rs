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
        let (client, connection) = tokio_postgres::connect(&conn_str, NoTls).await?;

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
fn format_cell(
    row: &tokio_postgres::Row,
    idx: usize,
    pg_type: &tokio_postgres::types::Type,
) -> Option<String> {
    use tokio_postgres::types::Type;

    // Check for NULL first via try_get on the raw bytes
    let is_null = row.try_get::<_, Option<String>>(idx).ok().flatten().is_none()
        && row.try_get::<_, Option<i64>>(idx).ok().flatten().is_none()
        && row.try_get::<_, Option<bool>>(idx).ok().flatten().is_none();

    if is_null && row.try_get::<_, Option<Vec<u8>>>(idx).ok().flatten().is_none() {
        return None;
    }

    let result: Option<String> = match *pg_type {
        Type::BOOL => row.get::<_, Option<bool>>(idx).map(|v| v.to_string()),
        Type::INT2 => row.get::<_, Option<i16>>(idx).map(|v| v.to_string()),
        Type::INT4 => row.get::<_, Option<i32>>(idx).map(|v| v.to_string()),
        Type::INT8 => row.get::<_, Option<i64>>(idx).map(|v| v.to_string()),
        Type::FLOAT4 => row.get::<_, Option<f32>>(idx).map(|v| v.to_string()),
        Type::FLOAT8 => row.get::<_, Option<f64>>(idx).map(|v| v.to_string()),
        Type::TEXT | Type::VARCHAR | Type::NAME => row.get::<_, Option<String>>(idx),
        Type::JSON | Type::JSONB => {
            row.get::<_, Option<serde_json::Value>>(idx)
                .map(|v| v.to_string())
        }
        Type::BYTEA => row
            .get::<_, Option<Vec<u8>>>(idx)
            .map(|v| format!("\\x{}", hex_encode(&v))),
        Type::TIMESTAMP => row
            .get::<_, Option<chrono::NaiveDateTime>>(idx)
            .map(|v| v.to_string()),
        Type::TIMESTAMPTZ => row
            .get::<_, Option<chrono::DateTime<chrono::Utc>>>(idx)
            .map(|v| v.to_string()),
        Type::DATE => row
            .get::<_, Option<chrono::NaiveDate>>(idx)
            .map(|v| v.to_string()),
        Type::UUID => {
            // UUID as bytes, format manually
            row.get::<_, Option<Vec<u8>>>(idx).map(|v| {
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
        }
        // NUMERIC comes as bytes - decode as text
        Type::NUMERIC => row
            .get::<_, Option<Vec<u8>>>(idx)
            .map(|v| String::from_utf8_lossy(&v).to_string()),
        _ => {
            // Fallback: try as text, then as bytes
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
    };

    result
}

fn hex_encode(bytes: &[u8]) -> String {
    bytes.iter().map(|b| format!("{:02x}", b)).collect()
}
