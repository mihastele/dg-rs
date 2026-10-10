---- RetrieveSchemas3 ----
SELECT keyspace_name, durable_writes, toJson(replication) as replication
FROM system_schema.keyspaces;

---- RetrieveVirtualSchemas ----
SELECT keyspace_name
FROM system_virtual_schema.keyspaces;

---- RetrieveSchemas2 ----
SELECT keyspace_name, durable_writes, strategy_class, strategy_options
FROM system.schema_keyspaces;

---- RetrieveTables3----
SELECT table_name AS name,
       comment,
       bloom_filter_fp_chance,
       toJson(caching) as caching,
       #V38: cdc, #.
       toJson(compaction) as compaction,
       toJson(compression) as compression,
       crc_check_chance,
       dclocal_read_repair_chance,
       default_time_to_live,
       speculative_retry,
       #V401: additional_write_policy, #.
       gc_grace_seconds,
       max_index_interval,
       memtable_flush_period_in_ms,
       min_index_interval,
       read_repair_chance
FROM system_schema.tables
WHERE keyspace_name = ?;

---- RetrieveVirtualTables4 ----
SELECT table_name AS name,
       comment
FROM system_virtual_schema.tables
WHERE keyspace_name = ?;

---- RetrieveVirtualColumns4 ----
SELECT column_name as name,
       table_name,
       clustering_order,
       kind,
       position,
       type
FROM system_virtual_schema.columns
WHERE keyspace_name = ?;

---- RetrieveTables2 ----
SELECT columnfamily_name AS name,
       comment,
       bloom_filter_fp_chance,
       caching,
       compaction_strategy_class,
       compaction_strategy_options,
       compression_parameters,
       default_time_to_live,
       speculative_retry,
       gc_grace_seconds,
       max_index_interval,
       memtable_flush_period_in_ms,
       min_index_interval,
       read_repair_chance
FROM system.schema_columnfamilies
WHERE keyspace_name = ?;

---- RetrieveMatViews ----
SELECT view_name AS name,
       comment,
       base_table_name,
       bloom_filter_fp_chance,
       toJson(caching) as caching,
       #V38: cdc, #.
       toJson(compaction) as compaction,
       toJson(compression) as compression,
       crc_check_chance,
       dclocal_read_repair_chance,
       default_time_to_live,
       speculative_retry,
       #V401: additional_write_policy, #.
       gc_grace_seconds,
       max_index_interval,
       memtable_flush_period_in_ms,
       min_index_interval,
       read_repair_chance,
       where_clause
FROM system_schema.views
WHERE keyspace_name = ?;

---- RetrieveColumns2 ----
SELECT column_name as name,
       validator,
       columnfamily_name as table_name,
       type,
       index_name,
       index_options,
       index_type,
       component_index as position
FROM system.schema_columns
WHERE keyspace_name = ?;

---- RetrieveColumns3 ----
SELECT column_name as name, table_name, type, kind, clustering_order, position
FROM system_schema.columns
WHERE keyspace_name = ?;

---- RetrieveIndices2 ----
SELECT index_name as name
FROM system."IndexInfo"
WHERE table_name = ?;

---- RetrieveIndices3 ----
SELECT index_name AS name, table_name, kind, toJson(options) as options
FROM system_schema.indexes
WHERE keyspace_name = ?;

---- RetrieveTriggers ----
SELECT trigger_name AS name,
       #V30: table_name,
       toJson(options) as options
       #: columnfamily_name as table_name,
       trigger_options as options
       #.
#V30:FROM system_schema.triggers
#:FROM system.schema_triggers
#.
WHERE keyspace_name = ?;

---- RetrieveFunctions ----
SELECT function_name AS name,
       argument_types,
       argument_names,
       body,
       called_on_null_input,
       language,
       return_type
#V30:FROM system_schema.functions
#:FROM system.schema_functions
#.
WHERE keyspace_name = ?;

---- RetrieveAggregates ----
SELECT aggregate_name AS name,
       #V30: argument_types as signature,
       #: signature,
       #.
       final_func,
       return_type,
       state_func,
       state_type
#V30:FROM system_schema.aggregates
#:FROM system.schema_aggregates
#.
WHERE keyspace_name = ?;

---- RetrieveObjectTypes ----
SELECT type_name AS name, field_names, field_types
#V30:FROM system_schema.types
#:FROM system.schema_usertypes
#.
WHERE keyspace_name = ?;

---- RetrieveRoles22 ----
SELECT role AS name, can_login, is_superuser
FROM system_auth.roles;

---- RetrieveRoles21 ----
SELECT name, super as is_superuser
FROM system_auth.users;
