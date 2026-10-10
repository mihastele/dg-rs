# Reverse Engineering Research Notes

## Source: JetBrains DataGrip 2025.3.4

**Location analyzed:** `C:\Program Files\JetBrains\DataGrip 2025.3.4\plugins\DatabaseTools\lib\`

### Key JARs

| JAR | Purpose | Size |
|-----|---------|------|
| `database-plugin.jar` | Core database plugin (4,281 classes) | ~43k entries |
| `modules/intellij.database.dialects.postgres.jar` | PostgreSQL dialect | Contains `PgIntroQueries.sql` (60KB) |
| `modules/intellij.database.dialects.postgresbase.jar` | Shared PG base (CockroachDB, GreenPlum) | |
| `modules/intellij.database.dialects.sqlite.jar` | SQLite dialect | |
| `modules/intellij.database.core.impl.jar` | Core introspection engine | |

### PostgreSQL Introspection Architecture

DataGrip's PG introspection uses a **two-level caching system**:

1. **L1 (Level 1) cache**: Lists all object OIDs + names in one query (`L1_ListAllExistentObjects`, `L1_ListAllMajorNames`)
2. **L2 (Level 2) cache**: Full object details, loaded on demand per schema

#### Template System

The SQL in `PgIntroQueries.sql` uses DataGrip's template engine:

```sql
-- Version guard: use column only on PG >= 9.1
#V91: rolreplication #: false #. is_replication

-- Version guard: use column only on PG >= 12.0  
#V120: false #: T.relhasoids #. as table_with_oids

-- Incremental sync: filter by transaction age
#INC> where pg_catalog.age(T.xmin) <= #TXAGE

-- Fragment: filter by specific names
#FRAG> and T.relname in ( :[*f_names] )
```

#### Key Query Categories (84 named queries in PgIntroQueries.sql)

| Category | Queries | Purpose |
|----------|---------|---------|
| Server info | `ServerStartupTime`, `IsSuperUser`, `CurrentXid`, `StateNumber` | Connection health, permissions |
| Databases | `ListDatabases` | Show all DBs on server |
| Schemas | `ListSchemas` | Schema tree top level |
| Tables | `RetrieveTables`, `RetrieveForeignTables` | Tables, views, matviews, foreign tables, partitioned tables |
| Columns | `RetrieveColumns`, `RetrieveStructAttributes` | Column metadata with types, defaults, nullability |
| Constraints | `RetrieveConstraints`, `RetrieveExistentConstraints` | PK, FK, UNIQUE, CHECK constraints |
| Indexes | `RetrieveIndices`, `RetrieveIndexColumns` | Index definitions |
| Routines | `RetrieveRoutines`, `RetrieveFunctionSources` | Stored procedures, functions + source code |
| Triggers | `RetrieveTriggers` | Trigger definitions |
| Views | `RetrieveViewSources` | View DDL |
| Sequences | `RetrieveSequences`, `RetrieveSequences10` | SERIAL/IDENTITY sequences |
| Types | `RetrieveDataTypes`, `RetrieveEnumLabels` | Custom types, enums |
| Extensions | `RetrieveExtensions`, `RetrieveExtensionMembers` | PG extensions (PostGIS, etc.) |
| Roles | `RetrieveRoles` | Users, groups, permissions |
| Security | `RetrieveSecurityPolicies` | Row-level security policies |
| L1 Cache | `L1_ListAllExistentObjects`, `L1_ListAllMajorNames`, `L1_RetrieveColumnNames` | Fast incremental sync |

### What We Ported to Rust

In `src/introspect/postgres.rs`, we ported the essential queries:

- `LIST_SCHEMAS` ← `ListSchemas` (simplified, PG 12+)
- `list_tables()` ← `RetrieveTables` (simplified, PG 12+)
- `list_columns()` ← `RetrieveColumns` (simplified, PG 12+)
- `list_primary_keys()` ← From `RetrieveConstraints` (contype = 'p')
- `LIST_DATABASES` ← `ListDatabases`
- `SERVER_VERSION` ← `version()`
- `IS_SUPERUSER` ← `IsSuperUser`

### SQLite Introspection

From `SqliteIntrospector$SqliteSchemaRetriever` (68KB class!):

- Uses `sqlite_master` table for object discovery
- Uses `PRAGMA table_info()`, `PRAGMA foreign_key_list()`, `PRAGMA index_list()`, `PRAGMA index_info()`
- Caches results and supports incremental refresh

Ported to `src/introspect/sqlite.rs`.

### REA (Reverse Engineer Anything) Usage

We used [REA](https://github.com/morluto/rea) — an MCP server for reverse
engineering with AI agents — as the methodology reference. REA provides:

- **MCP tools** for Ghidra/Hopper binary analysis
- **Java bytecode analysis** for JVM apps
- **Electron/JS app** inspection
- **Website** analysis

For DataGrip (a Java app), the key REA workflow would be:
1. Point REA at `database-plugin.jar`
2. REA decompiles classes → understand introspection pipeline
3. Extract SQL templates → port to Rust

We did this manually (extract jar → read .sql resources → read class strings)
because the SQL files were directly extractable as resources.

### Other Dialects Available (not yet ported)

The same jar contains introspection for:
- MySQL/MariaDB (`intellij.database.dialects.mysqlbase.jar`)
- MSSQL (`intellij.database.dialects.mssql.jar`)
- Oracle (proprietary, not in DataGrip by default)
- MongoDB (`intellij.database.dialects.mongo.jar`)
- Cassandra, ClickHouse, Snowflake, Redshift, BigQuery, DB2, H2, Hive, Vertica, Exasol, DynamoDB, Couchbase, CockroachDB, GreenPlum

Each has its own `*IntroQueries` class/SQL file following the same template pattern.

### DataGrip's Connection Strings (from dataSourcesHistory)

Found in `%APPDATA%\JetBrains\DataGrip2026.1\dataSourcesHistory\`:

```xml
<jdbc-url>jdbc:postgresql://localhost:5432/vuenest</jdbc-url>
<driver-ref>postgresql</driver-ref>
<jdbc-driver>org.postgresql.Driver</jdbc-driver>
<secret-storage>master_key</secret-storage>
```

Passwords are stored in the JetBrains keychain (`master_key` storage),
not in plaintext XML.

### Files in this Directory

- `DataGrip_PgIntroQueries.sql` — Full 60KB PostgreSQL introspection SQL (84 queries)
- `CRoachIntroQueries.sql` — CockroachDB introspection (15KB)
- `GPlumIntroQueries.sql` — GreenPlum introspection (44KB)
- `RsIntroQueries.sql` — Redshift introspection (40KB)
- `CassIntroQueries.sql` — Cassandra introspection (4KB)

All extracted from JetBrains DataGrip 2025.3.4. These are reference materials
for building compatible introspection in datagrip-rs. The query *patterns*
are what we port; the SQL itself is not copied verbatim into the codebase
(we write idiomatic Rust/SQL instead).
