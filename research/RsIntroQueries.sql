---- ListDatabases ----
select (D.#DBIDCOLUMN)::bigint as id,
       D.datname as name,
       #SHARING.pg_get_userbyid(D.datdba) as "owner",
       D.datallowconn as is_allow_connections,
       D.datistemplate as is_template
from #SHARING.pg_database D
    left join #SHARING.svv_redshift_databases RD on D.datname = RD.database_name
where RD.database_type is null or RD.database_type = 'local'
order by case when D.datname = #SHARING.current_database() then -1::bigint else (D.#DBIDCOLUMN)::bigint end
;


---- RetrieveAllSharedDatabases ----
select (D.#DBIDCOLUMN)::bigint as id,
       D.datname as name,
       #SHARING.pg_get_userbyid(D.datdba) as "owner",
       D.datallowconn as is_allow_connections,
       DS.share_name as datashare_name,
       DS.producer_account as datashare_account,
       DS.producer_namespace as datashare_namespace,
       RD.database_type
from #SHARING.pg_database D
    left join #SHARING.svv_redshift_databases RD on D.datname = RD.database_name
    left join #SHARING.svv_datashares DS on D.datname = DS.consumer_database
where RD.database_type = 'shared' or RD.database_type = 'shared via data catalog'
;


---- ListExistentDatabaseComments ----
select D.objoid id
from pg_catalog.pg_description D
where D.classoid in (
  'pg_catalog.pg_language'::regclass,
  'pg_catalog.pg_cast'::regclass
)
;

---- RetrieveDatabaseComments ----
select D.objoid id, case
    when 'pg_catalog.pg_language'::regclass = classoid then 'L'
    when 'pg_catalog.pg_cast'::regclass = classoid then 'C'
  end as kind,
  D.objsubid sub_id, D.description
from pg_catalog.pg_description D
where classoid in (
  'pg_catalog.pg_language'::regclass,
  'pg_catalog.pg_cast'::regclass
)
#INC> and pg_catalog.age(D.xmin) <= #TXAGE


---- DatabaseComment ----
select D.description
from pg_catalog.pg_database N
  left join pg_catalog.pg_description D on N.oid = D.objoid and D.classoid = 'pg_catalog.pg_database'::regclass
where datname = :database_name
;


---- ListExistentLanguages ----
select oid from pg_catalog.pg_language
;

---- ListLanguages ----
select l.oid as id, l.xmin state_number, lanname as name, lanpltrusted as trusted,
       h.proname as handler, hs.nspname as handlerSchema,
       v.proname as validator, vs.nspname as validatorSchema
from pg_catalog.pg_language l
    left join pg_catalog.pg_proc h on h.oid = lanplcallfoid
    left join pg_catalog.pg_namespace hs on hs.oid = h.pronamespace
    left join pg_catalog.pg_proc v on v.oid = lanvalidator
    left join pg_catalog.pg_namespace vs on vs.oid = v.pronamespace
#INC> where pg_catalog.age(l.xmin) <= #TXAGE
order by lanname
;


---- RetrieveDatashares ----
select share_id as datashare_id,
       share_name as datashare_name,
       pg_catalog.pg_get_userbyid(share_owner) as "owner",
       is_publicaccessible as is_public_accessible,
       managed_by as manager_name
from pg_catalog.svv_datashares
where source_database = :database_name
;


---- ListSchemas ----
select N.oid::bigint as id,
       N.xmin as state_number,
       N.nspname as name,
       D.description,
       pg_catalog.pg_get_userbyid(N.nspowner) as "owner"
from pg_catalog.pg_namespace N
  left outer join pg_catalog.pg_external_schema ES on N.oid = ES.esoid
  left join pg_catalog.pg_description D on N.oid = D.objoid
  where ES.esoid is null
order by case when N.nspname = pg_catalog.current_schema() then -1::bigint else N.oid::bigint end
;

---- RetrieveSharedSchemas ----
select schema_name
from #SHARING.svv_redshift_schemas
where database_name = :database_name and schema_type = 'shared'
;

---- RetrieveSharedViaDataCatalogSchemas ----
select case when schemaname = '<NO_SCHEMA>'
            then case when strpos(tablename, '.') > 0 then split_part(tablename, '.', 1) end
            else schemaname
       end as schema_name,
       bool_and(schemaname = '<NO_SCHEMA>') as no_schema_only
from pg_catalog.svv_external_tables
where redshift_database_name = :database_name
group by schema_name
;

---- RetrieveExternalSchemas ----
select S.nspname as schema_name,
       S.oid as schema_id,
       S.xmin as state_number,
       ES.esdbname as database_name,
       ES.eskind as schema_kind,
       ES.esoptions as schema_options,
       D.description,
       pg_catalog.pg_get_userbyid(S.nspowner) as "owner"
from pg_catalog.pg_external_schema ES
       left join pg_catalog.pg_namespace S on ES.esoid = S.oid
       left join pg_catalog.pg_description D on S.oid = D.objoid
;


---- RetrievePermissions ----
select pg_catalog.has_table_privilege('pg_catalog.pg_user_info', 'select') user_ext

---- RetrieveUsers ----
select usesysid as user_id, usename as user_name,
  usesuper is_super, usecreatedb can_createdb,
  #[USER_EXT]: case when useconnlimit = 'UNLIMITED' then -1 ELSE useconnlimit::int end #: null #. conn_limit,
  valuntil::timestamp::text valid_until, '{' || pg_catalog.array_to_string(useconfig, :array_delimiter) || '}' config
from #[USER_EXT]: pg_catalog.pg_user_info #: pg_catalog.pg_user #.
;

---- RetrieveExistentGroups ----
select grosysid from pg_catalog.pg_group
;

---- RetrieveGroups ----
select groname, grosysid, grolist from pg_catalog.pg_group
#INC>  where pg_catalog.age(xmin) <= #TXAGE
;


---- StateNumber ----
select pg_catalog.int8in(pg_catalog.xidout(L.transaction)) as transaction_id
from pg_catalog.pg_locks L
where L.transaction is not null
order by pg_catalog.age(L.transaction) desc
limit 1
;


---- CurrentXid ----
select pg_catalog.xidin(pg_catalog.int8out(pg_catalog.age(pg_catalog.xidin(pg_catalog.int8out(3)))::bigint + 3)) as current_txid
;


---- ListExistentSchemaComments ----
select D.objoid id, D.objsubid sub_id
from pg_catalog.pg_description D
  join pg_catalog.pg_class C on D.objoid = C.oid
where C.relnamespace = pg_catalog.oid(:schema_id) and C.relkind != 'c' and D.classoid = 'pg_catalog.pg_class'::regclass
union all
select T.oid id, D.objsubid
from pg_catalog.pg_description D
  join pg_catalog.pg_type T on T.oid = D.objoid
  left join pg_catalog.pg_class C on T.typrelid = C.oid
where T.typnamespace = pg_catalog.oid(:schema_id) and (C.relkind = 'c' or C.relkind is null)
union all
select T.oid id, D.objsubid
from pg_catalog.pg_description D
  join pg_catalog.pg_type T on T.typrelid = D.objoid
  left join pg_catalog.pg_class C on T.typrelid = C.oid
where T.typnamespace = pg_catalog.oid(:schema_id) and (C.relkind = 'c' or C.relkind is null)
union all
select D.objoid id, D.objsubid
from pg_catalog.pg_description D
  join pg_catalog.pg_constraint C on D.objoid = C.oid
where C.connamespace = pg_catalog.oid(:schema_id) and D.classoid = 'pg_catalog.pg_constraint'::regclass
union all
select D.objoid id, D.objsubid
from pg_catalog.pg_description D
  join pg_catalog.pg_proc P on P.oid = D.objoid
where P.pronamespace = pg_catalog.oid(:schema_id) and D.classoid = 'pg_catalog.pg_proc'::regclass
union all
select D.objoid id, D.objsubid
from pg_catalog.pg_description D
  join pg_catalog.pg_operator O on O.oid = D.objoid
where O.oprnamespace = pg_catalog.oid(:schema_id) and D.classoid = 'pg_catalog.pg_operator'::regclass
;


---- RetrieveSchemaComments ----
select D.objoid id, C.relkind as kind, D.objsubid sub_id, D.description
from pg_catalog.pg_description D
  join pg_catalog.pg_class C on D.objoid = C.oid
where C.relnamespace = pg_catalog.oid(:schema_id) and C.relkind != 'c' and D.classoid = 'pg_catalog.pg_class'::regclass
#INC> and pg_catalog.age(D.xmin) <= #TXAGE
union all
select T.oid id, 'T' as kind, D.objsubid sub_id, D.description
from pg_catalog.pg_description D
  join pg_catalog.pg_type T on T.oid = D.objoid
  left join pg_catalog.pg_class C on T.typrelid = C.oid
where T.typnamespace = pg_catalog.oid(:schema_id) and (C.relkind = 'c' or C.relkind is null)
#INC> and pg_catalog.age(D.xmin) <= #TXAGE
union all
select T.oid id, 'T' as kind, D.objsubid sub_id, D.description
from pg_catalog.pg_description D
  join pg_catalog.pg_type T on T.typrelid = D.objoid
  left join pg_catalog.pg_class C on T.typrelid = C.oid
where T.typnamespace = pg_catalog.oid(:schema_id) and (C.relkind = 'c' or C.relkind is null)
#INC> and pg_catalog.age(D.xmin) <= #TXAGE
union all
select D.objoid id, cast(translate(C.contype, 'pufc', 'kkxz') as "char") as kind, D.objsubid sub_id, D.description
from pg_catalog.pg_description D
  join pg_catalog.pg_constraint C on D.objoid = C.oid
where C.connamespace = pg_catalog.oid(:schema_id) and D.classoid = 'pg_catalog.pg_constraint'::regclass
#INC> and pg_catalog.age(D.xmin) <= #TXAGE
union all
select D.objoid id, 'F' as kind, D.objsubid sub_id, D.description
from pg_catalog.pg_description D
  join pg_catalog.pg_proc P on P.oid = D.objoid
where P.pronamespace = pg_catalog.oid(:schema_id) and D.classoid = 'pg_catalog.pg_proc'::regclass
#INC> and pg_catalog.age(D.xmin) <= #TXAGE
union all
select D.objoid id, 'O' as kind, D.objsubid sub_id, D.description
from pg_catalog.pg_description D
  join pg_catalog.pg_operator O on O.oid = D.objoid
where O.oprnamespace = pg_catalog.oid(:schema_id) and D.classoid = 'pg_catalog.pg_operator'::regclass
#INC> and pg_catalog.age(D.xmin) <= #TXAGE
;

---- RetrieveSchemaCommentsFragPgClassRels ----
select D.objoid id, C.relkind::char as kind, D.objsubid sub_id, D.description
from pg_catalog.pg_description D
       join pg_catalog.pg_class C on D.objoid = C.oid
where C.relnamespace = :schema_id::oid and (C.relkind != 'c' and C.relkind != 'i' and C.relkind != 'I') and D.classoid = 'pg_catalog.pg_class'::regclass
and C.relname in ( :[*f_names] )

---- RetrieveSchemaCommentsFragConstraints ----
select D.objoid id, pg_catalog.translate(C.contype, 'pufc', 'kkxz')::char as kind, D.objsubid sub_id, D.description
from pg_catalog.pg_description D
       join pg_catalog.pg_constraint C on D.objoid = C.oid
       left join pg_catalog.pg_class CLS on CLS.oid = C.conrelid
       left join pg_catalog.pg_type TYP on TYP.oid = C.contypid
where C.connamespace = :schema_id::oid and D.classoid = 'pg_catalog.pg_constraint'::regclass
and CLS.relname in ( :[*f_names] ) or TYP.typname in ( :[*f_names] )

---- RetrieveSchemaCommentsFragObjTypes ----
select T.oid id, 'T'::char as kind, D.objsubid sub_id, D.description
from pg_catalog.pg_description D
       join pg_catalog.pg_type T on T.oid = D.objoid or T.typrelid = D.objoid
       left join pg_catalog.pg_class C on T.typrelid = C.oid
where T.typnamespace = :schema_id::oid and (C.relkind = 'c' or C.relkind is null)
and T.typname in ( :[*f_names] )

---- RetrieveSchemaCommentsFragTableTriggers ----
select 0 as id, '0'::char as kind, 0 as sub_id, '' as description
where false;

---- RetrieveSchemaCommentsFragTableRules ----
select 0 as id, '0'::char as kind, 0 as sub_id, '' as description
  where false;

---- RetrieveSchemaCommentsFragTableIndices ----
select 0 as id, '0'::char as kind, 0 as sub_id, '' as description
where false;

---- RetrieveSchemaCommentsFragProcs ----
select D.objoid id, 'F'::char as kind, D.objsubid sub_id, D.description
from pg_catalog.pg_description D
       join pg_catalog.pg_proc P on P.oid = D.objoid
where P.pronamespace = :schema_id::oid and D.classoid = 'pg_catalog.pg_proc'::regclass
and P.proname in ( :[*f_names] )

---- RetrieveSchemaCommentsFragOperators ----
select D.objoid id, 'O'::char as kind, D.objsubid sub_id, D.description
from pg_catalog.pg_description D
       join pg_catalog.pg_operator O on O.oid = D.objoid
where O.oprnamespace = :schema_id::oid and D.classoid = 'pg_catalog.pg_operator'::regclass
and O.oprname in ( :[*f_names] )

---- RetrieveSchemaCommentsFragOpClasses ----
select 0 as id, '0'::char as kind, 0 as sub_id, '' as description
where false;

---- RetrieveSchemaCommentsFragOpFamilies ----
select 0 as id, '0'::char as kind, 0 as sub_id, '' as description
where false;

---- RetrieveSchemaCommentsFragCollations ----
select 0 as id, '0'::char as kind, 0 as sub_id, '' as description
where false;

---- RetrieveSchemaCommentsFragSecPolicies ----
select 0 as id, '0'::char as kind, 0 as sub_id, '' as description
where false;


---- RetrieveStates ----
select distinct oid, pg_catalog.int8in(pg_catalog.xidout(xmin)) xmin
from pg_catalog.pg_type
where oid in (OIDS)
union
select distinct oid, pg_catalog.int8in(pg_catalog.xidout(xmin)) xmin
from pg_catalog.pg_class
where oid in (OIDS)
union
select distinct oid, pg_catalog.int8in(pg_catalog.xidout(xmin)) xmin
from pg_catalog.pg_proc
where oid in (OIDS)
union
select distinct oid, pg_catalog.int8in(pg_catalog.xidout(xmin)) xmin
from pg_catalog.pg_operator
where oid in (OIDS)
union
select distinct oid, pg_catalog.int8in(pg_catalog.xidout(xmin)) xmin
from pg_catalog.pg_constraint
where oid in (OIDS)
union
select distinct oid, pg_catalog.int8in(pg_catalog.xidout(xmin)) xmin
from pg_catalog.pg_namespace
where oid in (OIDS)
union
select distinct oid, pg_catalog.int8in(pg_catalog.xidout(xmin)) xmin
from pg_catalog.pg_cast
where oid in (OIDS)
;


---- RetrieveExistentDataTypes ----
select oid
  from pg_catalog.pg_type
  where typnamespace = :schema_id::oid
;

---- RetrieveDataTypes ----
with oid_t as (select pg_catalog.oid(:schema_id) as o),
     age_t as (select #TXAGE as e)
select T.oid as type_id,
       T.xmin as type_state_number,
       T.typname as type_name,
       T.typtype as type_sub_kind,
       'X' as type_category,
       T.typrelid as class_id,
       T.typbasetype as base_type_id,
       case when T.typtype in ('c','e') then null
            else pg_catalog.format_type(T.typbasetype, T.typtypmod) end as type_def,
       T.typdefault as default_expression,
       T.typnotnull as mandatory
from pg_catalog.pg_type T
         left outer join pg_catalog.pg_class C
             on T.typrelid = C.oid
where T.typnamespace = (select o from oid_t)
  #FRAG> and T.typname in ( :[*f_names] )
  #INC> and pg_catalog.age(T.xmin) <= (select e from age_t)
  and (T.typtype in ('d','e') or C.relkind = 'c'::"char" or T.typtype = 'b' and T.typelem = 0)
order by 1
;


---- RetrieveExistentTables ----
select oid from pg_catalog.pg_class
where relkind in ('r', 'm', 'v', 'p')
  and relnamespace = :schema_id::oid
;

---- RetrieveTables ----
with backup_keys as (
       select pg_catalog.split_part(key, '_', 5) as table_id,
              value
       from pg_conf
       where pg_catalog.split_part(key, '_', 4) = (select oid from pg_catalog.pg_database
                                        where datname = pg_catalog.current_database())
       and key like 'pg_class_backup_%'
       and value = 'NO'
)
select T.relkind as table_kind,
       T.relname as table_name,
       T.oid as table_id,
       T.xmin as table_state_number,
       T.relhasoids as table_with_oids,
       T.relnamespace as tablespace_id,
       T.reldiststyle as dist_style,
       (case when BK.value = 'NO' then false else true end) as bckp,
       (case when T.relkind = 'v' and T.relnatts = 0 then true else false end) as is_boundless_view,
       pg_catalog.pg_get_userbyid(T.relowner) as "owner"
from pg_catalog.pg_class T
left outer join backup_keys BK on (T.oid = BK.table_id)
where relnamespace = pg_catalog.oid(:schema_id)
  and relkind in ('r', 'm', 'v')
  #FRAG> and T.relname in ( :[*f_names] )
  #INC> and pg_catalog.age(T.xmin) <= #TXAGE
order by table_kind, table_id
;

---- RetrieveMatViewNames ----
select trim(MI.name) from pg_catalog.svv_mv_info MI
  where database_name = :database_name and schema_name = :schema_name
    #FRAG> and trim(MI.name) in ( :[*f_names] )
;

---- RetrieveSharedTables ----
select table_name
from #SHARING.svv_redshift_tables
where database_name = :database_name and schema_name = :schema_name
  #FRAG> and table_name in ( :[*f_names] )
;

---- RetrieveSharedViaDataCatalogTables ----
select case when schemaname = '<NO_SCHEMA>' then split_part(tablename, '.', 1) else schemaname end as schema_name,
       case when schemaname = '<NO_SCHEMA>' then ltrim(ltrim(tablename, schema_name), '.') else tablename end as table_name,
       schema_name = :schema_name as is_correct_schema
from pg_catalog.svv_external_tables
where redshift_database_name = :database_name
  #FRAG> and case when schemaname = '<NO_SCHEMA>' then ltrim(ltrim(tablename, schema_name), '.') else tablename end in ( :[*f_names] )
;

---- RetrieveSharedViaDataCatalogTablesNoSchemaOnly ----
select split_part(tablename, '.', 1) as schema_name,
       ltrim(ltrim(tablename, schema_name), '.') as table_name,
       true as is_correct_schema
from pg_catalog.svv_external_tables
where redshift_database_name = :database_name and schema_name = :schema_name
  #FRAG> and ltrim(ltrim(tablename, schema_name), '.') in ( :[*f_names] )
;

---- RetrieveExternalTables ----
select T.tablename as table_name,
       T.location,
       T.input_format,
       T.output_format,
       T.serialization_lib,
       T.serde_parameters as serde_properties,
       T.parameters as props
from pg_catalog.svv_external_tables T
where #V1044126: T.redshift_database_name = :database_name and #. T.schemaname = :schema_name
      #FRAG> and T.tablename in ( :[*f_names] )
;


---- RetrieveStructAttributes ----
with types as (select #INC>distinct
                      T.oid as type_id,
                      C.oid as class_id
               from pg_catalog.pg_type T
               join pg_catalog.pg_class C
                 on T.typrelid = C.oid
              #INC> join pg_catalog.pg_attribute A
              #INC>   on C.oid = A.attrelid
               where T.typnamespace = pg_catalog.oid(:schema_id)
                 #FRAG> and T.typname in ( :[*f_names] )
                 #INC> and (pg_catalog.age(C.xmin) <= #TXAGE or pg_catalog.age(A.xmin) <= #TXAGE)
                 and T.typtype = 'c'::"char"
                 and C.relkind = 'c'::"char")
select type_id,
       A.attnum as att_position,
       A.attname as att_name,
       pg_catalog.format_type(A.atttypid, A.atttypmod) as att_type
from types join pg_catalog.pg_attribute A
  on A.attrelid = types.class_id
where A.attisdropped is null or not A.attisdropped
order by type_id::bigint, A.attnum
;


---- RetrieveColumns ----
with T as ( select #INC>distinct
                  T.oid as table_id, T.relname as table_name
            from pg_catalog.pg_class T
                 #INC>, pg_catalog.pg_attribute A
            where T.relnamespace = pg_catalog.oid(:schema_id)
              and T.relkind in ('r', 'm', 'v')
              #INC> and (pg_catalog.age(T.xmin) <= #TXAGE or pg_catalog.age(A.xmin) <= #TXAGE)
              #INC> and A.attrelid = T.oid
              #FRAG> and T.relname in ( :[*f_names] )
            )
select T.table_id,
       C.attnum as column_position,
       C.attname as column_name,
       C.xmin as column_state_number,
       C.atttypmod as type_mod,
       C.attndims as dimensions_number,
       pg_catalog.format_type(C.atttypid, C.atttypmod) as type_spec,
       C.attnotnull as mandatory,
       D.adsrc as column_default_expression,
       C.attisdropped as column_is_dropped,
       pg_catalog.format_encoding(C.attencodingtype::integer) as encoding,
       C.attisdistkey as distkey,
       C.attsortkeyord as sortkeyord
from T
  inner join pg_catalog.pg_attribute C on T.table_id = C.attrelid
  left outer join pg_catalog.pg_attrdef D on (C.attrelid, C.attnum) = (D.adrelid, D.adnum)
where attnum > 0
  and not C.attisdropped
order by table_id, attnum
;

---- RetrieveSharedTablesColumns ----
select table_name,
       ordinal_position as position,
       column_name,
       data_type
from #SHARING.svv_redshift_columns
where database_name = :database_name and schema_name = :schema_name
  #FRAG> and table_name in ( :[*f_names] )
;

---- RetrieveSharedViaDataCatalogTablesColumns ----
select case when schemaname = '<NO_SCHEMA>' then split_part(tablename, '.', 1) else schemaname end as schema_name,
       case when schemaname = '<NO_SCHEMA>' then ltrim(ltrim(tablename, schema_name), '.') else tablename end as table_name,
       columnnum as position,
       columnname as column_name,
       external_type as data_type,
       schema_name = :schema_name as is_correct_schema
from pg_catalog.svv_external_columns
where redshift_database_name = :database_name
  #FRAG> and case when schemaname = '<NO_SCHEMA>' then ltrim(ltrim(tablename, schema_name), '.') else tablename end in ( :[*f_names] )
;

---- RetrieveSharedViaDataCatalogTablesColumnsNoSchemaOnly ----
select split_part(tablename, '.', 1) as schema_name,
       ltrim(ltrim(tablename, schema_name), '.') as table_name,
       columnnum as position,
       columnname as column_name,
       external_type as data_type,
       true as is_correct_schema
from pg_catalog.svv_external_columns
where redshift_database_name = :database_name and schema_name = :schema_name
  #FRAG> and ltrim(ltrim(tablename, schema_name), '.') in ( :[*f_names] )
;

---- RetrieveExternalTablesColumns ----
select C.tablename as table_name,
       C.columnnum as position,
       C.columnname as column_name,
       C.external_type as data_type,
       C.part_key as partition_key
from pg_catalog.pg_get_external_columns()
         C(esoid integer,
#V1044126> redshift_database_name character varying,
           schemaname character varying,
           tablename character varying,
           columnname character varying,
           external_type character varying,
           columnnum integer,
           part_key integer,
           is_nullable character varying)
where #V1044126: C.redshift_database_name = :database_name and #. C.schemaname = :schema_name
      #FRAG> and C.tablename in ( :[*f_names] )
;

---- RetrieveBoundlessViewsColumns ----
select view_name,
       col_num as position,
       col_name as column_name,
       col_type as column_type
from pg_get_late_binding_view_cols() cols(view_schema name, view_name name, col_name name, col_type varchar, col_num int)
where view_schema = :schema_name
      #FRAG> and view_name in ( :[*f_names] )
;


---- RetrieveExistentConstraints ----
select oid
  from pg_catalog.pg_constraint
  where conrelid != 0 and connamespace = :schema_id::oid
;

---- RetrieveConstraints ----
select T.oid table_id,
       relkind table_kind,
       C.oid::bigint con_id,
       pg_catalog.int8in(pg_catalog.xidout(C.xmin)) con_state_id,
       conname con_name,
       contype con_kind,
       '{' || pg_catalog.array_to_string(conkey, ',') || '}' con_columns,
       confrelid ref_table_id,
       consrc con_expression,
       '{' || pg_catalog.array_to_string(confkey, ',') || '}' ref_columns
from pg_catalog.pg_constraint C
         join pg_catalog.pg_class T
              on C.conrelid = T.oid
   where relkind in ('r', 'v')
     and relnamespace = pg_catalog.oid(:schema_id)
     and contype in ('p', 'u', 'f', 'c', 'x')
     and connamespace = pg_catalog.oid(:schema_id)
#INC> and pg_catalog.age(T.xmin) <= #TXAGE or pg_catalog.age(c.xmin) <= #TXAGE
;


---- RetrieveUsedArgumentTypes ----
with schema_procs as (select P.prorettype, PI.proallargtypes
                      from pg_catalog.pg_proc_info PI join pg_catalog.pg_proc P on PI.prooid = P.oid
                      where P.pronamespace = pg_catalog.oid(:schema_id)
                        and pg_catalog.age(P.xmin) <= #TXAGE #. ),
     schema_opers as (select oprleft, oprright, oprresult
                      from pg_catalog.pg_operator
                      where oprnamespace = pg_catalog.oid(:schema_id)
                        and pg_catalog.age(xmin) <= #TXAGE #. ),
     schema_aggregates as (select A.aggtranstype
                           from pg_catalog.pg_aggregate A
                           join pg_catalog.pg_proc P
                             on A.aggfnoid = P.oid
                           where P.pronamespace = :schema_id::oid
                           #INC: and (pg_catalog.age(A.xmin) <= #TXAGE or pg_catalog.age(P.xmin) <= #TXAGE ) #. ),
     schema_arg_types_arrays as (select proallargtypes as type_ids
                                 from schema_procs),
     array_idxs as (select pg_catalog.generate_series(1,
                     (select pg_catalog.max(pg_catalog.array_upper(type_ids, 1))
                      from schema_arg_types_arrays)
                   ) as i),
     schema_arg_types as ( select prorettype as type_id
                           from schema_procs
                           union
                           select A.type_ids[i]::oid AS type_id
                           from array_idxs
                           inner join schema_arg_types_arrays A ON array_idxs.i <= pg_catalog.array_upper(type_ids, 1)
                           union
                           select oprleft as type_id
                           from schema_opers
                           where oprleft is not null
                           union
                           select oprright as type_id
                           from schema_opers
                           where oprright is not null
                           union
                           select oprresult as type_id
                           from schema_opers
                           where oprresult is not null
                           union
                           select aggtranstype::oid as type_id
                           from schema_aggregates
                           )
select type_id, pg_catalog.format_type(type_id, null) as type_spec
from schema_arg_types
where type_id <> 0 -- todo unclear how to frag
;


---- RetrieveExistentRoutines ----
select oid
  from pg_catalog.pg_proc
  where not proisagg and pronamespace = :schema_id::oid
;

---- RetrieveRoutines ----
with languages as (select oid as lang_oid, lanname as lang
                   from pg_catalog.pg_language),
     routines as (select proname as r_name,
                         prolang as lang_oid,
                         oid as r_id,
                         xmin as r_state_number,
                         string_to_array(pg_catalog.textin(pg_catalog.oidvectorout(proargtypes)), ' ')::int[] as in_arg_types,
                         null as arg_defaults,
                         0 as arg_variadic_id,
                         prorettype as ret_type_id,
                         proretset as ret_set,
                         provolatile as volatile_kind,
                         false as is_strict,
                         prosecdef as is_security_definer,
                         null::text[] as configuration_parameters,
                         0 as cost,
                         0 as rows,
                         false as is_leakproof,
                         null as concurrency_kind
                  from pg_catalog.pg_proc
                  where pronamespace = pg_catalog.oid(:schema_id)
                    #FRAG> and proname in ( :[*f_names] )
                    and not proisagg
                   #INC: and pg_catalog.age(xmin) <= #TXAGE #.),
     routine_info as (select prooid,
                             proargnames as arg_names,
                             proargmodes as arg_modes,
                             proallargtypes::int[] as all_arg_types,
                             prokind as kind
        from pg_catalog.pg_proc_info
        where pronamespace = pg_catalog.oid(:schema_id))
select *
from routines natural join languages join routine_info on prooid = r_id
;


---- RetrieveExistentAggregates ----
select oid
  from pg_catalog.pg_proc
  where proisagg and pronamespace = :schema_id::oid
;


---- RetrieveAggregates ----
select P.oid as aggregate_id,
       P.proname as aggregate_name,
       P.proargnames as arg_names,
       string_to_array(pg_catalog.textin(pg_catalog.oidvectorout(P.proargtypes)), ' ')::int8[] as in_arg_types,
       A.aggtransfn::oid as aggregate_function_id,
       case when A.aggtransfn::oid = 0 then null else regprocout(A.aggtransfn) end as aggregate_function_name,
       A.aggtranstype::oid as transition_type,
       A.aggfinalfn::oid as final_function_id,
       case when A.aggfinalfn::oid = 0 then null else regprocout(A.aggfinalfn) end as final_function_name,
       case when A.aggfinalfn::oid = 0 then 0 else P.prorettype end as final_return_type,
       A.agginitval as initial_value
from pg_catalog.pg_aggregate A
join pg_catalog.pg_proc P
  on A.aggfnoid = P.oid
where P.pronamespace = :schema_id::oid
  #FRAG> and P.proname in ( :[*f_names] )
  #INC> and (pg_catalog.age(A.xmin) <= #TXAGE or pg_catalog.age(P.xmin) <= #TXAGE)


---- RetrieveExistentOperators ----
select oid
  from pg_catalog.pg_operator
  where oprnamespace = :schema_id::oid
;

---- RetrieveOperators ----
select O.oid as op_id,
       oprname as op_name,
       oprkind as op_kind,
       oprleft as arg_left_type_id,
       oprright as arg_right_type_id,
       oprresult as arg_result_type_id,
       oprcode::oid as main_id,
       regprocout(oprcode) as main_name,
       oprrest::oid as restrict_id,
       regprocout(oprrest) as restrict_name,
       oprjoin::oid as join_id,
       regprocout(oprjoin) as join_name,
       oprcom::oid as com_id,
       regoperout(oprcom) as com_name,
       oprnegate::oid as neg_id,
       regoperout(oprnegate) as neg_name,
       oprcanhash as hashes
from pg_catalog.pg_operator O
where oprnamespace = pg_catalog.oid(:schema_id)
  #FRAG> and oprname in ( :[*f_names] )
  #INC> and pg_catalog.age(xmin) <= #TXAGE
;


---- RetrieveSharedFunctions ----
select function_name,
       argument_type as in_arg_types,
       result_type
from #SHARING.svv_redshift_functions
where database_name = :database_name and schema_name = :schema_name
  #FRAG> and function_name in ( :[*f_names] )
;


---- RetrieveViewSources ----
select T.relkind as view_kind,
       T.oid as view_id,
       T.relname as view_name,
       pg_catalog.pg_get_viewdef(T.oid, true) as source_text
from pg_catalog.pg_class T,
     pg_catalog.pg_namespace N
where N.oid = pg_catalog.oid(:schema_id)
  #FRAG> and T.relname in ( :[*f_names] )
  and T.relnamespace = N.oid
  and T.relkind in ('m','v')
order by pg_catalog.int8in(pg_catalog.xidout(T.xmin))
-- todo where's inc here :thinking:
;


---- RetrieveFunctionSources ----
with system_languages as ( select oid as lang
                           from pg_catalog.pg_language
                           where lanname in ('c','internal') )
select oid as id,
       (select distinct pg_catalog.array_to_string(ARRAY(select (case 
                                                                    when arg_modes is null then '' 
                                                                    else case arg_modes[k]
                                                                        when 'o' then 'out '
                                                                        when 'b' then 'inout '
                                                                        else ''
                                                                    end 
                                                                end) +
                                                                (case when arg_names is null then '' else arg_names[k] + ' ' end) +
                                                                pg_catalog.format_type(T.oid, null)
                                                from pg_catalog.generate_series(1, pg_catalog.array_upper(arg_types, 1)) as k
                                                join pg_catalog.pg_type T ON T.oid = arg_types[k]
                                                order by k), ', ')
          from (select coalesce(string_to_array(array_to_string(PGPC.proallargtypes, ' '), ' '),
                                pg_catalog.string_to_array(pg_catalog.textin(pg_catalog.oidvectorout(PGPC.proargtypes)), ' ')) arg_types,
                       PGPC.proargmodes arg_modes,
                       PGPC.proargnames arg_names
                  from pg_proc_info PGPC
                  where PGPC.prooid = PC.oid) oids_array) as arguments_def,
       (select distinct pg_catalog.format_type(PGT.oid, null)
          from pg_catalog.pg_type PGT
          where PGT.oid = PC.prorettype) as result_def,
       prosrc as source_text
from pg_catalog.pg_proc PC
where pronamespace = pg_catalog.oid(:schema_id)
  #FRAG> and PC.proname in ( :[*f_names] )
  #INC> and pg_catalog.age(xmin) <= #SRCTXAGE
  and not proisagg
  and prolang not in (select lang from system_languages)
  and prosrc is not null
;


---- ListReferencingSchemas ----
select distinct connamespace as schema_id
from pg_catalog.pg_constraint F,
     pg_catalog.pg_class O
where F.contype = 'f'
  and F.confrelid = O.oid
  and O.relnamespace in (SCHEMAIDS)
;


---- RetrieveTimeZones ----
select
  tz.name,
  tz.is_dst
from pg_timezone_names() tz(name text, abbrev text, utc_offset interval, is_dst boolean)
union distinct
select
  tz.name,
  tz.is_dst
from pg_timezone_abbrevs() tz(name text, utc_offset interval, is_dst boolean);

---- RetrieveDateStyle ----
show DateStyle;

---- ListExistentCasts ----
select oid from pg_catalog.pg_cast
;

---- ListCasts ----
select C.oid,
       C.xmin as state_number,
       C.castsource as castsource_id,
       pg_catalog.quote_ident(SN.nspname) || '.' || pg_catalog.quote_ident(S.typname) as castsource_name,
       C.casttarget as casttarget_id,
       pg_catalog.quote_ident(TN.nspname) || '.' || pg_catalog.quote_ident(T.typname) as casttarget_name,
       C.castfunc as castfunc_id,
       pg_catalog.quote_ident(FN.nspname) || '.' || pg_catalog.quote_ident(F.proname) as castfunc_name,
       C.castcontext
from pg_cast C
     left outer join pg_proc F on C.castfunc::oid = F.oid
     left outer join pg_namespace FN on F.pronamespace = FN.oid
     join pg_type S on C.castsource::oid = S.oid
     join pg_namespace SN on S.typnamespace = SN.oid
     join pg_type T on C.casttarget::oid = T.oid
     join pg_namespace TN on T.typnamespace = TN.oid
#INC> where pg_catalog.age(C.xmin) <= #TXAGE
;

---- L1_ListAllExistentObjects ----
select T.oid as oid,
       relnamespace as schemaId,
       pg_catalog.translate(relkind, 'rmvpfS', 'rmvrfS') as kind
from pg_catalog.pg_class T
where relnamespace in ( :[*schema_ids] )
  and relkind in ('r', 'm', 'v')
--
union all
-- begin objectType
select T.oid,
       T.typnamespace,
       'T' as kind
from pg_catalog.pg_type T
       left outer join pg_catalog.pg_class C on T.typrelid = C.oid
where T.typnamespace in ( :[*schema_ids] )
  and (T.typtype in ('d','e') or
       C.relkind = 'c'::"char" or
       T.typtype = 'b' and T.typelem = 0)
--
union all
-- begin ops
select oid,
       oprnamespace,
       'O' as kind
from pg_catalog.pg_operator
where oprnamespace in ( :[*schema_ids] )
--
union all
-- begin agg & routine
select oid,
       pronamespace,
       case when not proisagg then 'R' else 'a' end as kind
from pg_catalog.pg_proc
where pronamespace in ( :[*schema_ids] )
;

---- L1_ListAllMajorNames ----
select T.oid as oid,
       relnamespace as schemaId,
       pg_catalog.translate(relkind, 'rmvpfS', 'rmvrfS') as kind,
       relname as name
from pg_catalog.pg_class T
where relnamespace in ( :[*schema_ids] )
  and relkind in ('r', 'm', 'v')
  #INC> and pg_catalog.age(T.xmin) <= #TXAGE
-- end relations (table like stuff & seq)
union all
-- begin objectType
select T.oid,
       T.typnamespace,
       'T',
       T.typname
from pg_catalog.pg_type T
       left outer join pg_catalog.pg_class C on T.typrelid = C.oid
where T.typnamespace in ( :[*schema_ids] )
  and (T.typtype in ('d','e') or
       C.relkind = 'c'::"char" or
       T.typtype = 'b' and T.typelem = 0)
  #INC> and pg_catalog.age(T.xmin) <= #TXAGE
--
union all
-- begin ops
select oid,
       oprnamespace,
       'O',
       oprname
from pg_catalog.pg_operator
where oprnamespace in ( :[*schema_ids] )
  #INC> and pg_catalog.age(xmin) <= #TXAGE
--
union all
-- begin agg & routine
select oid,
       pronamespace,
       case when not proisagg#. then 'R' else 'a' end,
       proname
from pg_catalog.pg_proc
where pronamespace in ( :[*schema_ids] )
#INC> and pg_catalog.age(xmin) <= #TXAGE
--
order by schemaId
;

---- L1_RetrieveMatViewNames ----
select trim(name) as name,
       trim(schema_name) as schemaName
from pg_catalog.svv_mv_info
where database_name = :database_name and schema_name in ( :[*schema_names] )

---- L1_RetrieveColumnNames ----
with T as ( select #INC: distinct #. T.oid as oid,
  T.relkind as kind,
  T.relnamespace as schemaId
from pg_catalog.pg_class T
  #INC>, pg_catalog.pg_attribute A
where T.relnamespace in ( :[*schema_ids] )
  and T.relkind in ('r', 'm', 'v', 'f', 'p')
  #INC> and (pg_catalog.age(A.xmin) <= #TXAGE or pg_catalog.age(T.xmin) <= #TXAGE)
  #INC> and A.attrelid = T.oid
  )
select T.schemaId as schemaId,
       T.oid as majorOid,
       pg_catalog.translate(T.kind, 'rmvpf', 'rmvrf') as kind,
       C.attnum as position,
       C.attname as name
from T
  join pg_catalog.pg_attribute C on T.oid = C.attrelid
where C.attnum > 0
  and not C.attisdropped
order by schemaId, majorOid
;

---- L1_RetrieveRoutineArgNames ----
select PPI.pronamespace as schemaId,
       PPI.prooid as majorOid,
       PPI.proargnames as argNames,
       PPI.proargmodes as argModes,
       pg_catalog.get_array_length(pg_catalog.split_to_array(pg_catalog.textin(pg_catalog.oidvectorout(PPI.proargtypes)), ' ')) as nArgs
from pg_catalog.pg_proc_info PPI
  join pg_catalog.pg_proc PP on PPI.prooid = PP.oid
where PPI.pronamespace in ( :[*schema_ids] )
  #INC> and pg_catalog.age(PP.xmin) <= #TXAGE
order by schemaId
;

---- L1_ListAllExternalMajorNames ----
select T.tablename as name,
       T.schemaname as schemaName
from pg_catalog.svv_external_tables T
where T.redshift_database_name = :database_name and T.schemaname in ( :[*schema_names] )
order by T.schemaname
;

---- L1_RetrieveExternalColumnNames ----
select C.schemaname as schemaName,
       C.tablename as tableName,
       C.columnname as name,
       C.columnnum as position
from pg_catalog.pg_get_external_columns()
  C(esoid integer,
  redshift_database_name character varying,
  schemaname character varying,
  tablename character varying,
  columnname character varying,
  external_type character varying,
  columnnum integer,
  part_key integer,
  is_nullable character varying)
where C.redshift_database_name = :database_name and C.schemaname in ( :[*schema_names] )
order by C.schemaname, C.tablename
;

-- todo: experimentation notice: below is the experimental query that use svv_all_tables for all the table
---- L1_RetrieveSharedTableNames ----
select T.table_name as name,
       T.schema_name as schemaName
from #SHARING.svv_all_tables T
where database_name = :database_name and T.schema_name in ( :[*schema_names] )
order by T.schema_name

---- L1_RetrieveSharedFunctionNames ----
select function_name as name,
       schema_name as schemaName,
       argument_type as inArgTypes,
       result_type as resultType
from #SHARING.svv_redshift_functions
where database_name = :database_name and schema_name in ( :[*schema_names] )
order by schema_name
;

-- todo: experimentation notice: below is the experimental query that use svv_all_columns for all the table
---- L1_RetrieveSharedColumnNamesSimple ----
select table_name as tableName,
       schema_name as schemaName,
       column_name as name,
       ordinal_position as position
from #SHARING.svv_all_columns
where database_name = :database_name and schemaname in ( :[*schema_names] )
order by schemaname, tablename
;

---- L1_RetrieveSharedColumnNamesViaDataCatalog ----
select case when schema_name = '<NO_SCHEMA>' then split_part(table_name, '.', 1) else schema_name end as schemaName,
       case when schema_name = '<NO_SCHEMA>' then ltrim(ltrim(table_name, split_part(table_name, '.', 1)), '.') else table_name end as tableName,
       column_name as name,
       ordinal_position as position
from #SHARING.svv_all_columns
where database_name = :database_name
  and case when schema_name = '<NO_SCHEMA>' then split_part(table_name, '.', 1) else schema_name end in ( :[*schema_names] )
order by case when schema_name = '<NO_SCHEMA>' then split_part(table_name, '.', 1) else schema_name end,
         case when schema_name = '<NO_SCHEMA>' then ltrim(ltrim(table_name, split_part(table_name, '.', 1)), '.') else table_name end
;