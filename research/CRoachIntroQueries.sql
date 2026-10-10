---- ServerStartupTime ----
select 0 as startup_time
;


---- IsSuperUser ----
select usesuper
from pg_user
where usename = current_user
;


---- ListDatabases ----
select N.oid::bigint as id,
       datname as name,
       D.description,
       datistemplate as is_template,
       datallowconn as allow_connections,
       pg_catalog.pg_get_userbyid(N.datdba) as "owner"
from pg_catalog.pg_database N
         left join pg_catalog.pg_shdescription D on N.oid = D.objoid
order by case when datname = pg_catalog.current_database() then -1::bigint else N.oid::bigint end
;


---- ListExistentLanguages ----
-- nothing


---- ListLanguages ----
-- nothing


----RetrieveExistentEventTriggers ----
-- nothing


---- RetrieveEventTriggers ----
-- nothing


---- ListSchemas ----
select N.oid::bigint as id,
--        N.xmin as state_number,
        nspname as name,
       D.description,
       pg_catalog.pg_get_userbyid(N.nspowner) as "owner"
from pg_catalog.pg_namespace N
         left join pg_catalog.pg_description D on N.oid = D.objoid and D.classoid = 'pg_catalog.pg_namespace'::regclass
order by case when nspname = current_schema then -1::bigint else N.oid::bigint end
;


---- RetrieveRoles ----
select R.oid::bigint role_id,
       rolname       role_name,
       rolcanlogin   can_login
       #SUPER> #V201> ,CR.options    role_options
from pg_catalog.pg_roles R
       #SUPER> #V201> left join [SHOW ROLES] CR on CR.username = R.rolname
;


---- RetrieveExistentTablespaces ----
-- nothing


---- RetrieveTablespaces ----
-- nothing


---- StateNumber ----
select 0 as transaction_id
;


---- CurrentXid ----
-- nothing


---- ListExistentSchemaComments ----
-- nothing


---- ListExistentServerComments ----
-- nothing


---- ListExistentDatabaseComments ----
-- nothing


---- RetrieveSchemaComments ----
select D.objoid id, C.relkind as kind, D.objsubid sub_id, D.description
from pg_catalog.pg_description D
         join pg_catalog.pg_class C on D.objoid = C.oid
where C.relnamespace = :schema_id::oid and C.relkind != 'c' and D.classoid = 'pg_catalog.pg_class'::regclass
;


---- RetrieveDatabaseComments ----
-- nothing


---- RetrieveStates ----
-- nothing


---- RetrieveExistentSequences ----
-- nothing


---- RetrieveSequences ----
select --cls.xmin as sequence_state_number,
       sq.seqrelid as sequence_id,
       cls.relname as sequence_name,
       pg_catalog.format_type(sq.seqtypid, null) as data_type,
       sq.seqstart as start_value,
       sq.seqincrement as inc_value,
       sq.seqmin as min_value,
       sq.seqmax as max_value,
       sq.seqcache as cache_size,
       sq.seqcycle as cycle_option,
       pg_catalog.pg_get_userbyid(cls.relowner) as "owner"
from pg_catalog.pg_sequence sq
         join pg_class cls on sq.seqrelid = cls.oid
where cls.relnamespace = :schema_id::oid
--           #INC> and pg_catalog.age(cls.xmin) <= #TXAGE
;


---- RetrieveExistentDataTypes ----
-- nothing


---- RetrieveDataTypes ----
select T.oid as type_id,
--        T.xmin as type_state_number,
       T.typname as type_name,
       T.typtype as type_sub_kind,
       T.typcategory as type_category,
       T.typrelid as class_id,
       T.typbasetype as base_type_id,
       case when T.typtype in ('c','e') or T.typbasetype <= 100000 then null
            else pg_catalog.format_type(T.typbasetype, T.typtypmod) end as type_def,
       T.typdefault as default_expression,
       T.typnotnull as mandatory,
       pg_catalog.pg_get_userbyid(T.typowner) as "owner"
from pg_catalog.pg_type T
         left outer join pg_catalog.pg_class C
                         on T.typrelid = C.oid
where T.typnamespace = :schema_id::oid
--   #INC> and pg_catalog.age(T.xmin) <= #TXAGE
  and (T.typtype in ('d','e') or C.relkind = 'c'::"char" or T.typtype = 'b' and (T.typelem = 0 OR T.typcategory <> 'A'))
order by 1
;


---- RetrieveExistentDataTypeChecks ----
-- nothing


---- RetrieveDataTypeChecks ----
-- nothing


---- RetrieveExistentTables ----
-- nothing


---- RetrieveTables ----
select T.relkind as table_kind,
       T.relname as table_name,
       T.oid as table_id,
--        T.xmin as table_state_number,
       T.relhasoids as table_with_oids,
       T.reltablespace as tablespace_id,
       (select array_agg(opt) from unnest(T.reloptions) as opt where opt not like 'schema_locked=%') as options,
       T.relpersistence as persistence,
       (select pg_catalog.array_agg(inhparent)::varchar from (select inhparent::bigint from pg_catalog.pg_inherits where T.oid = inhrelid order by inhseqno) as bts) as ancestors,
       (select pg_catalog.array_agg(inhrelid)::varchar from (select inhrelid::bigint from pg_catalog.pg_inherits where T.oid = inhparent order by inhrelid) as its) as successors,
       T.relam am_id,
       pg_catalog.pg_get_userbyid(T.relowner) as "owner"
from pg_catalog.pg_class T
where relnamespace = :schema_id::oid
  and relkind in ('r', 'm', 'v', 'f', 'p')
--   #INC> and pg_catalog.age(T.xmin) <= #TXAGE
order by table_kind, table_id
;


---- RetrieveForeignTables ----
-- nothing


---- RetrieveStructAttributes ----
-- nothing


---- RetrieveEnumLabels ----
with types as (select distinct T.oid as type_id
               from pg_catalog.pg_type T
                        join pg_catalog.pg_enum E
                             on T.oid = E.enumtypid
               where T.typnamespace = :schema_id::oid
    and T.typtype = 'e'::"char"
--     #INC> and pg_catalog.age(E.xmin) <= #TXAGE
    )
select T.type_id as enum_id,
       pg_catalog.array_agg(E.enumlabel::varchar order by E.enumsortorder) as enum_labels
from types T
         join pg_catalog.pg_enum E
              on T.type_id = E.enumtypid
group by T.type_id
;


---- RetrieveColumns ----
with T as ( select
                   T.oid as table_id, T.relname as table_name
            from pg_catalog.pg_class T
            where T.relnamespace = :schema_id::oid
    and T.relkind in ('r', 'm', 'v', 'f', 'p')
    )
select T.table_id,
       C.attnum as column_position,
       C.attname as column_name,
       C.atttypmod as type_mod,
       C.attndims as dimensions_number,
       pg_catalog.format_type(C.atttypid, C.atttypmod) as type_spec,
       C.atttypid as type_id,
       C.attnotnull as mandatory,
       pg_catalog.pg_get_expr(D.adbin, T.table_id) as column_default_expression,
       not C.attislocal as column_is_inherited,
       C.attfdwoptions as options,
       C.attisdropped as column_is_dropped,
       #V201: C.attgenerated #: ' ' #. as generated,
       #V260: ISC.is_hidden is NULL or ISC.is_hidden = 'YES' #: R.hidden #. as is_hidden
from T
         join pg_catalog.pg_attribute C on T.table_id = C.attrelid
         left join pg_catalog.pg_attrdef D on (C.attrelid, C.attnum) = (D.adrelid, D.adnum)
         #V260: #: left join crdb_internal.table_columns R on T.table_id = R.descriptor_id::oid and C.attnum = R.column_id #.
         #V260> left join information_schema.columns ISC on ISC.table_name = T.table_name and ISC.column_name = C.attname and ISC.table_schema = :schema_name and ISC.table_catalog = :database_name
where attnum > 0
order by table_id, attnum
;


---- RetrieveExistentIndices ----


---- RetrieveIndices ----
select tab.oid                                                        table_id,
       tab.relkind                                                    table_kind,
       ind_stor.relname                                               index_name,
       ind_head.indexrelid                                            index_id,
       ind_head.indisunique                                           is_unique,
       ind_head.indisprimary                                          is_primary,
       pg_catalog.pg_get_expr(ind_head.indpred, ind_head.indrelid) as condition,
       ind_stor.reltablespace                                         tablespace_id,
       #V260: false #: #V201: ti.is_inverted #: false #. #.        as is_inverted -- fixme: currently a reliable way to fetch the correct value in CR 26+ is not found - keep as 'false' for now
from pg_catalog.pg_class tab
         join pg_catalog.pg_index ind_head
              on ind_head.indrelid = tab.oid
         join pg_catalog.pg_class ind_stor
              on tab.relnamespace = ind_stor.relnamespace and ind_stor.oid = ind_head.indexrelid
         #V260: #: left join crdb_internal.table_indexes ti on ti.descriptor_id::oid = tab.oid and ti.index_name = ind_stor.relname #.
where tab.relnamespace = :schema_id::oid
  and tab.relkind in ('r', 'm', 'v', 'p')
  and ind_stor.relkind = 'i'
order by index_id
;


---- RetrieveIndexColumns ----
select ind_head.indexrelid index_id,
       k col_idx,
       ind_head.indkey[k-1] column_position,
       ind_head.indoption[k-1] column_options,
       ind_head.indclass[k-1] as opclass,
       #V260: ISC.is_hidden is NULL or ISC.is_hidden = 'YES' #: ic.hidden #. as is_hidden,
       case
           when indexprs is null then null
           when ind_head.indkey[k-1] = 0 then chr(27) || pg_catalog.pg_get_indexdef(ind_head.indexrelid, k::int, true)
           else pg_catalog.pg_get_indexdef(ind_head.indexrelid, k::int, true)
end as expression,
       amcanorder can_order
from (select *, pg_catalog.generate_subscripts(indkey::int[], 1) k from pg_catalog.pg_index) ind_head
         join pg_catalog.pg_class ind_stor
              on ind_stor.oid = ind_head.indexrelid
         left join pg_catalog.pg_collation
              on pg_collation.oid = ind_head.indcollation[k-1]
         left join pg_catalog.pg_am am
              on ind_stor.relam = am.oid
         #V260: #: left join crdb_internal.table_columns ic
              on ind_head.indrelid = ic.descriptor_id::oid and ind_head.indkey[k-1] = ic.column_id #.
         #V260> left join pg_catalog.pg_class ind_rel on ind_rel.oid = ind_head.indrelid
         #V260> left join information_schema.columns ISC on ISC.table_name = ind_rel.relname and ISC.ordinal_position = ind_head.indkey[k-1] and ISC.table_schema = :schema_name and ISC.table_catalog = :database_name
where ind_stor.relnamespace = :schema_id::oid
  and ind_stor.relkind = 'i'
order by index_id, k
;


---- RetrieveExistentConstraints ----
-- nothing


---- RetrieveConstraints ----
with T as (select oid     as table_id,
                  relkind as table_kind
           from pg_catalog.pg_class
           where relkind in ('r', 'v', 'f', 'p')
             and relnamespace = :schema_id::oid),
     C as (select conrelid         as table_id,
                  oid::bigint      as con_id,
                  conname          as con_name,
                  contype          as con_kind,
                  conkey           as con_columns,
                  conindid         as index_id,
                  confrelid        as ref_table_id,
                  confkey          as ref_columns,
                  condeferrable    as is_deferrable,
                  condeferred      as is_init_deferred,
                  confupdtype      as on_update,
                  confdeltype      as on_delete,
                  conbin
           from pg_catalog.pg_constraint
           where contype in ('u', 'f', 'c', 'x')
             and connamespace = :schema_id::oid
           union all
           select i.indrelid      as table_id,
                  ci.oid::bigint  as con_id,
                  ci.relname      as con_name,
                  'p'             as con_kind,
                  i.indkey::int[] as con_columns,
                  ci.oid          as index_id,
                  0               as ref_table_id,
                  null            as ref_columns,
                  false           as is_defferrable,
                  false           as is_init_deferred,
                  null            as on_update,
                  null            as on_delete,
                  null            as conbin
           from pg_catalog.pg_index i
                  join pg_catalog.pg_class ci on (ci.oid = i.indexrelid)
           where i.indisprimary
             and ci.relnamespace = :schema_id::oid
     )
select table_id,
       table_kind,
       con_id,
       con_name,
       con_kind,
       con_columns,
       index_id,
       ref_table_id,
       is_deferrable,
       is_init_deferred,
       on_update,
       on_delete,
       pg_catalog.pg_get_expr(conbin, table_id) as con_expression,
       ref_columns
from T natural join C
order by pg_catalog.strpos('pufc', con_kind)
;


---- RetrieveUsedArgumentTypes ----
-- nothing


---- RetrieveExistentRoutines ----
-- nothing


---- RetrieveRoutines ----
-- nothing


---- RetrieveExistentAggregates ----
-- nothing


---- RetrieveAggregates ----
-- nothing


---- RetrieveExistentExtensions ----
-- nothing


---- RetrieveExtensions ----
-- nothing

---- RetrieveExtensionMembers ----
-- nothing


---- RetrieveExistentOperators ----
-- nothing


---- RetrieveOperators ----
-- nothing


---- RetrieveExistentOperatorClasses ----
-- nothing


---- RetrieveOperatorClasses ----
-- nothing


---- RetrieveExistentAmOps ----
-- nothing


---- RetrieveAmOps ----
-- nothing


---- RetrieveExistentAmProcs ----
-- nothing


---- RetrieveAmProcs ----
-- nothing


---- RetrieveExistentOperatorFamilies ----
-- nothing


---- RetrieveOperatorFamilies ----
-- nothing


---- RetrieveExistentRules ----
-- nothing


---- RetrieveRules ----
-- nothing


---- RetrieveExistentTriggers ----
-- nothing


---- RetrieveTriggers ----
-- nothing


---- RetrieveViewSources ----
select
    T.relkind as view_kind,
    T.oid as view_id,
    pg_catalog.pg_get_viewdef(T.oid, true) as source_text
from pg_catalog.pg_class T
         join pg_catalog.pg_namespace N on T.relnamespace = N.oid
where N.oid = :schema_id::oid
  and T.relkind in ('m','v')
--   #INCSRC> and (pg_catalog.age(T.xmin) <= #SRCTXAGE or exists(
--   #INCSRC>    select A.attrelid from pg_catalog.pg_attribute A where A.attrelid = T.oid and pg_catalog.age(A.xmin) <= #SRCTXAGE))
;


---- RetrieveRuleSources ----
-- nothing


---- RetrieveFunctionSources ----
-- nothing


---- RetrieveExistentAccessMethods ----
-- nothing


---- RetrieveAccessMethods ----
-- nothing


---- RetrieveExistentCollations ----
-- nothing


---- RetrieveCollations ----
-- nothing


---- RetrieveExistentForeignDataWrappers ----
-- nothing


---- RetrieveForeignDataWrappers ----
-- nothing


---- RetrieveExistentForeignServers ----
-- nothing


---- RetrieveForeignServers ----
-- nothing


---- RetrieveExistentUserMappingsSuperUser ----
-- nothing


---- RetrieveUserMappingsSuperUser ----
-- nothing


---- RetrieveUserMappings ----
-- nothing


---- ListReferencingSchemas ----
select distinct connamespace as schema_id
from pg_catalog.pg_constraint F,
     pg_catalog.pg_class O
where F.contype = 'f'
  and F.confrelid = O.oid
  and O.relnamespace in (SCHEMAIDS)
;


---- RetrieveRelations ----
select D.objid as dependent_id,
       D.refobjid as owner_id,
       D.refobjsubid as owner_subobject_id
from pg_depend D
  join pg_class C_SEQ on D.objid    = C_SEQ.oid and D.classid    = 'pg_class'::regclass::oid
  join pg_class C_TAB on D.refobjid = C_TAB.oid and D.refclassid = 'pg_class'::regclass::oid
where C_SEQ.relkind = 'S'
  and C_TAB.relkind = 'r'
  and D.refobjsubid <> 0
  and (D.deptype = 'a' or D.deptype = 'i')
  and C_TAB.relnamespace = :schema_id::oid
order by owner_id
;


---- RetrieveTimeZones ----
-- nothing


---- RetrieveDateStyle ----
show DateStyle
;


---- RetrieveSecurityPolicies ----
-- nothing

---- ListExistentCasts ----
-- nothing

---- ListCasts ----
-- nothing