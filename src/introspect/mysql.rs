//! MySQL/MariaDB introspection queries.
//!
//! Reverse-engineered from JetBrains DataGrip's `MysqlBaseIntroQueries.class`
//! (71KB Kotlin class in `intellij.database.dialects.mysqlbase.jar`).
//!
//! DataGrip uses `information_schema` queries for MySQL introspection,
//! with `#SCHEMAS` template placeholders and `?` bind parameters.
//! We simplify these for direct use.

/// List all schemas (databases) on the server, excluding system schemas by default.
/// From DataGrip: `retrieveSchemas` → `List Schemas`
///
/// ```sql
/// select schema_name, default_collation_name
/// from information_schema.schemata
/// ```
pub const LIST_SCHEMAS: &str = r#"
SELECT schema_name AS name, default_collation_name AS collation
FROM information_schema.schemata
WHERE schema_name NOT IN ('information_schema', 'performance_schema', 'mysql', 'sys')
ORDER BY schema_name
"#;

/// List ALL schemas including system ones (for full introspection).
pub const LIST_ALL_SCHEMAS: &str = r#"
SELECT schema_name AS name, default_collation_name AS collation
FROM information_schema.schemata
ORDER BY schema_name
"#;

/// List all tables and views in a schema (database).
/// From DataGrip: `processTablesAndViews` → `Retrieve Tables and Views`
///
/// ```sql
/// select T.table_name as table_name,
///        T.table_type as table_type,
///        T.table_comment as table_comment,
///        T.engine as engine,
///        T.table_collation as table_collation,
///        T.create_options as create_options,
///        V.definer as view_definer
/// from information_schema.tables T
/// left join information_schema.views V
///   on T.table_schema = V.table_schema and T.table_name = V.table_name
/// where T.table_schema = ?
/// ```
pub fn list_tables(schema: &str) -> String {
    format!(
        r#"
SELECT T.table_name AS table_name,
       T.table_type AS table_type,
       T.table_comment AS table_comment,
       T.engine AS engine,
       T.table_collation AS table_collation,
       T.auto_increment AS auto_increment,
       V.definer AS view_definer
FROM information_schema.tables T
LEFT JOIN information_schema.views V
  ON T.table_schema = V.table_schema AND T.table_name = V.table_name
WHERE T.table_schema = '{schema}'
ORDER BY T.table_type, T.table_name
"#
    )
}

/// List columns for all tables in a schema.
/// From DataGrip: `processColumns` → `Retrieve Columns`
///
/// ```sql
/// select ordinal_position, column_name, column_type, column_default,
///        generation_expression, table_name, column_comment,
///        is_nullable, extra, collation_name
/// from information_schema.columns
/// where table_schema = ?
/// order by table_name, ordinal_position
/// ```
pub fn list_columns(schema: &str) -> String {
    format!(
        r#"
SELECT ordinal_position AS ordinal_position,
       column_name AS column_name,
       column_type AS column_type,
       column_default AS column_default,
       generation_expression AS generation_expression,
       table_name AS table_name,
       column_comment AS column_comment,
       is_nullable AS is_nullable,
       extra AS extra,
       collation_name AS collation_name
FROM information_schema.columns
WHERE table_schema = '{schema}'
ORDER BY table_name, ordinal_position
"#
    )
}

/// List columns for a specific table (more efficient for single-table lookup).
pub fn list_columns_for_table(schema: &str, table: &str) -> String {
    format!(
        r#"
SELECT ordinal_position AS ordinal_position,
       column_name AS column_name,
       column_type AS column_type,
       column_default AS column_default,
       generation_expression AS generation_expression,
       column_comment AS column_comment,
       is_nullable AS is_nullable,
       extra AS extra,
       collation_name AS collation_name
FROM information_schema.columns
WHERE table_schema = '{schema}'
  AND table_name = '{table}'
ORDER BY ordinal_position
"#
    )
}

/// List primary keys for tables in a schema.
/// Derived from DataGrip's `processConstraints` + `processConstraintColumns`
/// using `information_schema.table_constraints` + `key_column_usage`.
pub fn list_primary_keys(schema: &str) -> String {
    format!(
        r#"
SELECT kcu.table_name AS table_name,
       kcu.column_name AS column_name,
       kcu.ordinal_position AS ordinal_position
FROM information_schema.table_constraints tc
JOIN information_schema.key_column_usage kcu
  ON tc.constraint_name = kcu.constraint_name
 AND tc.table_schema = kcu.table_schema
 AND tc.table_name = kcu.table_name
WHERE tc.constraint_type = 'PRIMARY KEY'
  AND tc.table_schema = '{schema}'
ORDER BY kcu.table_name, kcu.ordinal_position
"#
    )
}

/// List all constraints (PK, FK, UNIQUE, CHECK).
/// From DataGrip: `processConstraints` → `Retrieve Constraints`
///
/// ```sql
/// select c.constraint_name, c.constraint_schema, c.table_name,
///        c.constraint_type, 'YES' as enforced
/// from information_schema.table_constraints c
/// where c.table_schema = ?
/// ```
pub fn list_constraints(schema: &str) -> String {
    format!(
        r#"
SELECT c.constraint_name,
       c.constraint_schema,
       c.table_name,
       c.constraint_type
FROM information_schema.table_constraints c
WHERE c.table_schema = '{schema}'
ORDER BY c.table_name, c.constraint_type, c.constraint_name
"#
    )
}

/// List foreign keys.
/// From DataGrip: `processForeignKeys` → `Retrieve Foreign Keys`
///
/// ```sql
/// select r.constraint_name, kcu.table_name, kcu.column_name,
///        kcu.referenced_table_schema, kcu.referenced_table_name,
///        kcu.referenced_column_name,
///        r.match_option, r.update_rule, r.delete_rule
/// from information_schema.referential_constraints r
/// join information_schema.key_column_usage kcu ...
/// ```
pub fn list_foreign_keys(schema: &str) -> String {
    format!(
        r#"
SELECT r.constraint_name,
       kcu.table_name,
       kcu.column_name,
       kcu.referenced_table_schema,
       kcu.referenced_table_name,
       kcu.referenced_column_name,
       r.update_rule,
       r.delete_rule
FROM information_schema.referential_constraints r
JOIN information_schema.key_column_usage kcu
  ON r.constraint_name = kcu.constraint_name
 AND r.constraint_schema = kcu.constraint_schema
WHERE r.constraint_schema = '{schema}'
ORDER BY kcu.table_name, r.constraint_name, kcu.ordinal_position
"#
    )
}

/// List indexes.
/// From DataGrip: `processIndices` → `Retrieve Indices`
///
/// ```sql
/// select table_name, index_name, index_comment, index_type,
///        non_unique, column_name, sub_part, collation, expression
/// from information_schema.statistics
/// where table_schema = ? and index_schema = ?
/// order by index_schema, table_name, index_name, index_type, seq_in_index
/// ```
pub fn list_indices(schema: &str) -> String {
    format!(
        r#"
SELECT table_name,
       index_name,
       index_type,
       non_unique,
       column_name,
       seq_in_index,
       index_comment
FROM information_schema.statistics
WHERE table_schema = '{schema}'
  AND index_schema = '{schema}'
ORDER BY table_name, index_name, seq_in_index
"#
    )
}

/// Get server version.
pub const SERVER_VERSION: &str = "SELECT VERSION()";

/// Get server variables.
/// From DataGrip: `queryExtraHandler` → `@@authentication_policy`, `lower_case_table_names`, etc.
pub const SERVER_VARIABLES: &str = r#"
SELECT @@version AS version,
       @@version_comment AS version_comment,
       @@lower_case_table_names AS lower_case_table_names,
       @@default_authentication_plugin AS auth_plugin
"#;

/// List all databases (alias for LIST_SCHEMAS, simpler).
pub const LIST_DATABASES: &str = r#"
SELECT schema_name AS name
FROM information_schema.schemata
ORDER BY schema_name
"#;

/// List routines (stored procedures and functions).
/// From DataGrip: `Retrieve All Major Names` — routines union
///
/// ```sql
/// select routine_schema as schema_name, routine_name as major_name,
///        case when ROUTINE_TYPE like 'P%' then 'P'
///             when ROUTINE_TYPE like 'F%' then 'F'
///        end as routine_kind
/// from information_schema.routines
/// where routine_schema in (#SCHEMAS)
/// ```
pub fn list_routines(schema: &str) -> String {
    format!(
        r#"
SELECT routine_name,
       routine_type,
       data_type AS return_type,
       routine_definition
FROM information_schema.routines
WHERE routine_schema = '{schema}'
ORDER BY routine_type, routine_name
"#
    )
}

/// List triggers.
/// From DataGrip: `processTriggers` → `Retrieve Triggers`
///
/// ```sql
/// select trigger_name, event_object_table, event_manipulation,
///        action_timing, definer
/// from information_schema.triggers
/// where trigger_schema = ?
/// ```
pub fn list_triggers(schema: &str) -> String {
    format!(
        r#"
SELECT trigger_name,
       event_object_table,
       event_manipulation,
       action_timing,
       action_statement
FROM information_schema.triggers
WHERE trigger_schema = '{schema}'
ORDER BY trigger_name
"#
    )
}

/// List views with their definitions.
/// From DataGrip: `processViews` → `Retrieve Views with Sources`
pub fn list_views(schema: &str) -> String {
    format!(
        r#"
SELECT table_name, view_definition
FROM information_schema.views
WHERE table_schema = '{schema}'
ORDER BY table_name
"#
    )
}
