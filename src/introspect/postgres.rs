//! PostgreSQL introspection queries.
//!
//! Reverse-engineered from JetBrains DataGrip's `PgIntroQueries.sql`
//! (found in `intellij.database.dialects.postgres.jar`).
//!
//! DataGrip uses a template system with `#V91:`, `#V120:` version guards and
//! `#INC>` incremental-sync markers. We strip those and target PG 12+ directly,
//! which covers ~99% of real deployments.

/// List all non-system schemas.
/// From DataGrip: `ListSchemas`
pub const LIST_SCHEMAS: &str = r#"
SELECT nspname AS name
FROM pg_catalog.pg_namespace
WHERE nspname NOT LIKE 'pg_%'
  AND nspname != 'information_schema'
ORDER BY CASE WHEN nspname = current_schema() THEN 0 ELSE 1 END, nspname
"#;

/// List all tables/views in a schema.
/// From DataGrip: `RetrieveTables` — simplified for PG 12+
pub fn list_tables(schema: &str) -> String {
    format!(
        r#"
SELECT T.relname AS table_name,
       T.relkind AS table_kind,
       pg_catalog.pg_get_userbyid(T.relowner) AS owner,
       obj_description(T.oid, 'pg_class') AS comment
FROM pg_catalog.pg_class T
WHERE T.relnamespace = (
    SELECT oid FROM pg_catalog.pg_namespace WHERE nspname = '{schema}'
)
  AND T.relkind IN ('r', 'm', 'v', 'f', 'p')
ORDER BY T.relkind, T.relname
"#
    )
}

/// List columns for a table.
/// From DataGrip: `RetrieveColumns` — simplified for PG 12+
pub fn list_columns(schema: &str, table: &str) -> String {
    format!(
        r#"
SELECT C.attnum AS column_position,
       C.attname AS column_name,
       pg_catalog.format_type(C.atttypid, C.atttypmod) AS type_spec,
       NOT C.attnotnull AS nullable,
       COALESCE(pg_catalog.pg_get_expr(D.adbin, D.adrelid), '') AS default_value,
       COALESCE(col_description(C.attrelid, C.attnum), '') AS comment
FROM pg_catalog.pg_class T
JOIN pg_catalog.pg_attribute C ON T.oid = C.attrelid
LEFT JOIN pg_catalog.pg_attrdef D ON (C.attrelid, C.attnum) = (D.adrelid, D.adnum)
WHERE T.relnamespace = (SELECT oid FROM pg_catalog.pg_namespace WHERE nspname = '{schema}')
  AND T.relname = '{table}'
  AND C.attnum > 0
  AND NOT C.attisdropped
ORDER BY C.attnum
"#
    )
}

/// List primary key columns for a table.
pub fn list_primary_keys(schema: &str, table: &str) -> String {
    format!(
        r#"
SELECT a.attname AS column_name
FROM pg_catalog.pg_constraint con
JOIN pg_catalog.pg_class rel ON rel.oid = con.conrelid
JOIN pg_catalog.pg_namespace nsp ON nsp.oid = rel.relnamespace
JOIN pg_catalog.pg_attribute a ON a.attrelid = con.conrelid AND a.attnum = ANY(con.conkey)
WHERE con.contype = 'p'
  AND nsp.nspname = '{schema}'
  AND rel.relname = '{table}'
ORDER BY array_position(con.conkey, a.attnum)
"#
    )
}

/// List all databases on the server.
/// From DataGrip: `ListDatabases`
pub const LIST_DATABASES: &str = r#"
SELECT datname AS name,
       pg_catalog.pg_get_userbyid(datdba) AS owner,
       datistemplate AS is_template
FROM pg_catalog.pg_database
ORDER BY CASE WHEN datname = current_database() THEN 0 ELSE 1 END, datname
"#;

/// Get server version.
/// From DataGrip: `ServerStartupTime` + version detection
pub const SERVER_VERSION: &str = "SELECT version()";

/// Check if current user is superuser.
/// From DataGrip: `IsSuperUser`
pub const IS_SUPERUSER: &str = r#"
SELECT usesuper FROM pg_user WHERE usename = current_user
"#;

/// List schemas (simplified version that works for introspection).
/// From DataGrip: `ListSchemas`
pub const LIST_SCHEMAS_SIMPLE: &str = r#"
SELECT schema_name
FROM information_schema.schemata
WHERE schema_name NOT LIKE 'pg_%'
  AND schema_name != 'information_schema'
ORDER BY schema_name
"#;

/// List tables using information_schema (portable, works on any PG version).
pub const LIST_TABLES_INFO_SCHEMA: &str = r#"
SELECT table_schema, table_name, table_type
FROM information_schema.tables
WHERE table_schema NOT IN ('pg_catalog', 'information_schema')
ORDER BY table_schema, table_type, table_name
"#;

/// List columns using information_schema (portable).
pub const LIST_COLUMNS_INFO_SCHEMA: &str = r#"
SELECT table_schema, table_name, column_name, data_type, is_nullable, column_default, ordinal_position
FROM information_schema.columns
WHERE table_schema NOT IN ('pg_catalog', 'information_schema')
ORDER BY table_schema, table_name, ordinal_position
"#;
