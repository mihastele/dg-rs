---- ServerStartupTime ----
select round(extract(epoch from pg_postmaster_start_time() at time zone 'UTC')) as startup_time;
;


---- IsSuperUser ----
select usesuper
from pg_catalog.pg_user
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


---- RetrieveExistentTablespaces ----
select oid::bigint from pg_catalog.pg_tablespace
;


---- RetrieveTablespaces ----
select T.oid::bigint as id, T.spcname as name,
       T.xmin as state_number, pg_catalog.pg_get_userbyid(T.spcowner) as owner,
       #V60: pg_catalog.pg_tablespace_location(T.oid) #: null #. as location,
       #V60: T.spcoptions #: null #. as options,
       D.description as comment
from pg_catalog.pg_tablespace T
  left join pg_catalog.pg_shdescription D on D.objoid = T.oid
#INC>where pg_catalog.age(T.xmin) <= #TXAGE or pg_catalog.age(D.xmin) <= #TXAGE
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

---- RetrieveExistentAccessMethods ----
select oid from pg_catalog.pg_am
;

---- RetrieveAccessMethods ----
select A.oid as access_method_id,
       A.xmin as state_number,
       A.amname as access_method_name
from pg_am A
#INC> where pg_catalog.age(A.xmin) <= #TXAGE
;

---- ListSchemas ----
select N.oid::bigint as id,
       N.xmin as state_number,
       nspname as name,
       D.description,
       pg_catalog.pg_get_userbyid(N.nspowner) as "owner"
from pg_catalog.pg_namespace N
  left join pg_catalog.pg_description D on N.oid = D.objoid
order by case when nspname = current_schema then -1::bigint else N.oid::bigint end
;


---- RetrieveRoles ----
select R.oid::bigint as role_id,
       R.rolname as role_name,
       R.rolsuper is_super,
       R.rolinherit is_inherit,
       R.rolcreaterole can_createrole,
       R.rolcreatedb can_createdb,
       R.rolcanlogin can_login,
       R.rolconnlimit conn_limit,
       R.rolvaliduntil valid_until,
       R.rolconfig config,
       D.description
from pg_catalog.pg_roles R
  left join pg_catalog.pg_shdescription D on D.objoid = R.oid
;


---- StateNumber ----
select pg_catalog.int8in(pg_catalog.xidout(L.transactionid))
from pg_catalog.pg_locks L
where L.transactionid is not null
order by pg_catalog.age(L.transactionid) desc
limit 1
;


---- CurrentXid ----
select pg_catalog.txid_current()::varchar::bigint as current_txid
;


---- ListExistentSchemaComments ----
select D.objoid id, pg_catalog.array_agg(D.objsubid) sub_ids
from pg_catalog.pg_description D
  join pg_catalog.pg_class C on D.objoid = C.oid
where C.relnamespace = :schema_id::oid and C.relkind != 'c' and D.classoid = 'pg_catalog.pg_class'::regclass
group by D.objoid
union all
select T.oid id, pg_catalog.array_agg(D.objsubid)
from pg_catalog.pg_description D
  join pg_catalog.pg_type T on T.oid = D.objoid or T.typrelid = D.objoid
  left join pg_catalog.pg_class C on T.typrelid = C.oid
where T.typnamespace = :schema_id::oid and (C.relkind = 'c' or C.relkind is null)
group by T.oid
union all
select D.objoid id, array[D.objsubid]
from pg_catalog.pg_description D
  join pg_catalog.pg_constraint C on D.objoid = C.oid
where C.connamespace = :schema_id::oid  and D.classoid = 'pg_catalog.pg_constraint'::regclass
union all
select D.objoid id, array[D.objsubid]
from pg_catalog.pg_description D
  join pg_catalog.pg_trigger T on T.oid = D.objoid
  join pg_catalog.pg_class C on C.oid = T.tgrelid
where C.relnamespace = :schema_id::oid  and D.classoid = 'pg_catalog.pg_trigger'::regclass
union all
select D.objoid id, array[D.objsubid]
from pg_catalog.pg_description D
  join pg_catalog.pg_rewrite R on R.oid = D.objoid
  join pg_catalog.pg_class C on C.oid = R.ev_class
where C.relnamespace = :schema_id::oid and D.classoid = 'pg_catalog.pg_rewrite'::regclass
union all
select D.objoid id, array[D.objsubid]
from pg_catalog.pg_description D
  join pg_catalog.pg_proc P on P.oid = D.objoid
where P.pronamespace = :schema_id::oid and D.classoid = 'pg_catalog.pg_proc'::regclass
union all
select D.objoid id, array[D.objsubid]
from pg_catalog.pg_description D
  join pg_catalog.pg_operator O on O.oid = D.objoid
where O.oprnamespace = :schema_id::oid and D.classoid = 'pg_catalog.pg_operator'::regclass
union all
select D.objoid id, array[D.objsubid]
from pg_catalog.pg_description D
  join pg_catalog.pg_opclass O on O.oid = D.objoid
where O.opcnamespace = :schema_id::oid and D.classoid = 'pg_catalog.pg_opclass'::regclass
#V50:union all
select D.objoid id, array[D.objsubid]
from pg_catalog.pg_description D
  join pg_catalog.pg_opfamily O on O.oid = D.objoid
where O.opfnamespace = :schema_id::oid and D.classoid = 'pg_catalog.pg_opfamily'::regclass
#.
#V60:union all
select D.objoid id, array[D.objsubid]
from pg_catalog.pg_description D
  join pg_catalog.pg_collation C on C.oid = D.objoid
where C.collnamespace = :schema_id::oid and D.classoid = 'pg_catalog.pg_collation'::regclass
#.
;


---- ListExistentServerComments ----
select D.objoid id
from pg_catalog.pg_description D
where D.classoid in (
  'pg_catalog.pg_tablespace'::regclass
)
;

---- ListExistentDatabaseComments ----
select D.objoid id
from pg_catalog.pg_description D
where D.classoid in (
  'pg_catalog.pg_am'::regclass,
  'pg_catalog.pg_cast'::regclass,
  #V50>'pg_catalog.pg_extension'::regclass,
  'pg_catalog.pg_language'::regclass#V60:,
  'pg_catalog.pg_foreign_data_wrapper'::regclass,
  'pg_catalog.pg_foreign_server'::regclass#.
)
;


---- RetrieveSchemaComments ----
select D.objoid id, #V70: relkind #: case when C.relstorage = 'x' then 'e' else C.relkind end #. as kind, D.objsubid sub_id, D.description
from pg_catalog.pg_description D
  join pg_catalog.pg_class C on D.objoid = C.oid
where C.relnamespace = :schema_id::oid and C.relkind != 'c' and D.classoid = 'pg_catalog.pg_class'::regclass
#INC> and pg_catalog.age(D.xmin) <= #TXAGE
union all
select T.oid id, 'T' as kind, D.objsubid sub_id, D.description
from pg_catalog.pg_description D
  join pg_catalog.pg_type T on T.oid = D.objoid or T.typrelid = D.objoid
  left join pg_catalog.pg_class C on T.typrelid = C.oid
where T.typnamespace = :schema_id::oid and (C.relkind = 'c' or C.relkind is null)
#INC> and pg_catalog.age(D.xmin) <= #TXAGE
union all
select D.objoid id, pg_catalog.translate(C.contype, 'pufc', 'kkxz') as kind, D.objsubid sub_id, D.description
from pg_catalog.pg_description D
  join pg_catalog.pg_constraint C on D.objoid = C.oid
where C.connamespace = :schema_id::oid and D.classoid = 'pg_catalog.pg_constraint'::regclass
#INC> and pg_catalog.age(D.xmin) <= #TXAGE
union all
select D.objoid id, 't' as kind, D.objsubid sub_id, D.description
from pg_catalog.pg_description D
  join pg_catalog.pg_trigger T on T.oid = D.objoid
  join pg_catalog.pg_class C on C.oid = T.tgrelid
where C.relnamespace = :schema_id::oid and D.classoid = 'pg_catalog.pg_trigger'::regclass
#INC> and pg_catalog.age(D.xmin) <= #TXAGE
union all
select D.objoid id, 'R' as kind, D.objsubid sub_id, D.description
from pg_catalog.pg_description D
  join pg_catalog.pg_rewrite R on R.oid = D.objoid
  join pg_catalog.pg_class C on C.oid = R.ev_class
where C.relnamespace = :schema_id::oid and D.classoid = 'pg_catalog.pg_rewrite'::regclass
#INC> and pg_catalog.age(D.xmin) <= #TXAGE
union all
select D.objoid id, 'F' as kind, D.objsubid sub_id, D.description
from pg_catalog.pg_description D
  join pg_catalog.pg_proc P on P.oid = D.objoid
where P.pronamespace = :schema_id::oid and D.classoid = 'pg_catalog.pg_proc'::regclass
#INC> and pg_catalog.age(D.xmin) <= #TXAGE
union all
select D.objoid id, 'O' as kind, D.objsubid sub_id, D.description
from pg_catalog.pg_description D
  join pg_catalog.pg_operator O on O.oid = D.objoid
where O.oprnamespace = :schema_id::oid and D.classoid = 'pg_catalog.pg_operator'::regclass
#INC> and pg_catalog.age(D.xmin) <= #TXAGE
#V50:union all
select D.objoid id, 'f' as kind, D.objsubid sub_id, D.description
from pg_catalog.pg_description D
  join pg_catalog.pg_opfamily O on O.oid = D.objoid
where O.opfnamespace = :schema_id::oid and D.classoid = 'pg_catalog.pg_opfamily'::regclass
#.
#INC> and pg_catalog.age(D.xmin) <= #TXAGE
union all
select D.objoid id, 'c' as kind, D.objsubid sub_id, D.description
from pg_catalog.pg_description D
  join pg_catalog.pg_opclass O on O.oid = D.objoid
where O.opcnamespace = :schema_id::oid and D.classoid = 'pg_catalog.pg_opclass'::regclass
#INC> and pg_catalog.age(D.xmin) <= #TXAGE
#V60:union all
select D.objoid id, 'C' as kind, D.objsubid sub_id, D.description
from pg_catalog.pg_description D
  join pg_catalog.pg_collation C on C.oid = D.objoid
where C.collnamespace = :schema_id::oid and D.classoid = 'pg_catalog.pg_collation'::regclass
#INC> and pg_catalog.age(D.xmin) <= #TXAGE
#.


---- RetrieveDatabaseComments ----
select D.objoid id, case
    when 'pg_catalog.pg_am'::regclass = classoid then 'A'
    when 'pg_catalog.pg_cast'::regclass = classoid then 'C'
    when 'pg_catalog.pg_extension'::regclass = classoid then 'E'
    when 'pg_catalog.pg_language'::regclass = classoid then 'L'
    #V60:when 'pg_catalog.pg_foreign_data_wrapper'::regclass = classoid then 'W'
    when 'pg_catalog.pg_foreign_server'::regclass = classoid then 'S'#.
  end as kind,
  D.objsubid sub_id, D.description
from pg_catalog.pg_description D
where classoid in (
  'pg_catalog.pg_am'::regclass,
  'pg_catalog.pg_cast'::regclass,
  'pg_catalog.pg_extension'::regclass,
  'pg_catalog.pg_language'::regclass#V60:,
  'pg_catalog.pg_foreign_data_wrapper'::regclass,
  'pg_catalog.pg_foreign_server'::regclass#.
)
#INC> and pg_catalog.age(D.xmin) <= #TXAGE

---- RetrieveStates ----
select distinct oid, pg_catalog.int8in(pg_catalog.xidout(xmin)) as "xmin"
from pg_catalog.pg_namespace
where oid in (OIDS)
union
select distinct oid, pg_catalog.int8in(pg_catalog.xidout(xmin)) as "xmin"
from pg_catalog.pg_type
where oid in (OIDS)
union
select distinct oid, pg_catalog.int8in(pg_catalog.xidout(xmin)) as "xmin"
from pg_catalog.pg_class
where oid in (OIDS)
union
select distinct oid, pg_catalog.int8in(pg_catalog.xidout(xmin)) as "xmin"
from pg_catalog.pg_proc
where oid in (OIDS)
union
select distinct oid, pg_catalog.int8in(pg_catalog.xidout(xmin)) as "xmin"
from pg_catalog.pg_operator
where oid in (OIDS)
union
select distinct oid, pg_catalog.int8in(pg_catalog.xidout(xmin)) as "xmin"
from pg_catalog.pg_constraint
where oid in (OIDS)
union
select distinct oid, pg_catalog.int8in(pg_catalog.xidout(xmin)) as "xmin"
from pg_catalog.pg_cast
where oid in (OIDS)
#V50:union
select distinct oid, pg_catalog.int8in(pg_catalog.xidout(xmin)) as "xmin"
from pg_catalog.pg_opfamily
where oid in (OIDS)
union
select distinct oid, pg_catalog.int8in(pg_catalog.xidout(xmin)) as "xmin"
from pg_catalog.pg_opclass
where oid in (OIDS)#.
#V60:union
select distinct oid, pg_catalog.int8in(pg_catalog.xidout(xmin)) as "xmin"
from pg_catalog.pg_collation
where oid in (OIDS)
#.
union
select distinct oid, pg_catalog.int8in(pg_catalog.xidout(xmin)) as "xmin"
from pg_catalog.pg_rewrite
where oid in (OIDS)
union
select distinct oid, pg_catalog.int8in(pg_catalog.xidout(xmin)) as "xmin"
from pg_catalog.pg_trigger
where oid in (OIDS)
#V50:union
select distinct oid, pg_catalog.int8in(pg_catalog.xidout(xmin)) as "xmin"
from pg_catalog.pg_am
where oid in (OIDS)#.
#V60:union
select distinct oid, pg_catalog.int8in(pg_catalog.xidout(xmin)) as "xmin"
from pg_catalog.pg_foreign_data_wrapper
where oid in (OIDS)
union
select distinct oid, pg_catalog.int8in(pg_catalog.xidout(xmin)) as "xmin"
from pg_catalog.pg_foreign_server
where oid in (OIDS)#.
#UMENABLED:union
select distinct oid, pg_catalog.int8in(pg_catalog.xidout(xmin)) as "xmin"
from pg_catalog.pg_user_mapping
where oid in (OIDS)#.
;


---- RetrieveExistentSequences ----
select oid
  from pg_catalog.pg_class
  where relkind = 'S'
    and relnamespace = :schema_id::oid
;

---- RetrieveSequences ----
with T as (
            select oid as sequence_id,
                 relname as sequence_name,
                 pg_catalog.pg_get_userbyid(relowner) as "owner",
                 xmin as sequence_state_number
                 from pg_catalog.pg_class
                   where relnamespace = :schema_id::oid
                   and relkind = 'S'
                   #INC> and pg_catalog.age(xmin) <= #TXAGE
          )
select sequence_id,
       sequence_name,
       sequence_state_number,
       "owner"
from T
;



---- RetrieveExistentOperatorClasses ----
select oid
  from pg_catalog.pg_opclass
  where opcnamespace = :schema_id::oid
;

---- RetrieveOperatorClasses ----
select O.oid as id,
       O.xmin as state_number,
       opcname as name,
       opcintype::regtype::varchar as in_type,
       case when opckeytype = 0 then null else opckeytype::regtype::varchar end as key_type,
       opcdefault as is_default,
       opcfamily as family_id,
       opfname as family,
       opcmethod as access_method_id,
       pg_catalog.pg_get_userbyid(O.opcowner) as "owner"
from pg_catalog.pg_opclass O join pg_catalog.pg_opfamily F on F.oid = opcfamily
where opcnamespace = :schema_id::oid
  #INC> and pg_catalog.age(O.xmin) <= #TXAGE
;


---- RetrieveExistentAmOps ----
select pg_amop.oid
  from pg_catalog.pg_amop
    join pg_catalog.pg_opfamily on pg_opfamily.oid = amopfamily
  where opfnamespace = :schema_id::oid
;


---- RetrieveAmOps ----
select O.oid as id,
       O.amopstrategy as strategy,
       O.amopopr as op_id,
       O.amopopr::regoperator::varchar as op_sig,
       #V91> O.amopsortfamily #: null #. as sort_family_id,
       #V91> SF.opfname #: null #. as sort_family,
       O.amopfamily as family_id,
       C.oid as class_id
from pg_catalog.pg_amop O
    left join pg_opfamily F on O.amopfamily = F.oid
    #V91>left join pg_opfamily SF on O.amopsortfamily = SF.oid
    left join pg_depend D on D.classid = 'pg_amop'::regclass and O.oid = D.objid and D.objsubid = 0
    left join pg_opclass C on D.refclassid = 'pg_opclass'::regclass and C.oid = D.refobjid and D.refobjsubid = 0
where C.opcnamespace = :schema_id::oid or C.opcnamespace is null and F.opfnamespace = :schema_id::oid
  #INC> and pg_catalog.age(O.xmin) <= #TXAGE
order by C.oid, F.oid
;


---- RetrieveExistentAmProcs ----
select pg_amproc.oid
  from pg_catalog.pg_amproc
    join pg_catalog.pg_opfamily on pg_opfamily.oid = amprocfamily
  where opfnamespace = :schema_id::oid
;


---- RetrieveAmProcs ----
select P.oid as id,
       P.amprocnum as num,
       P.amproc::oid as proc_id,
       P.amproc::regprocedure::varchar as proc_sig,
       P.amproclefttype::regtype::varchar as left_type,
       P.amprocrighttype::regtype::varchar as right_type,
       P.amprocfamily as family_id,
       C.oid as class_id
from pg_catalog.pg_amproc P
    left join pg_opfamily F on P.amprocfamily = F.oid
    left join pg_depend D on D.classid = 'pg_amproc'::regclass and P.oid = D.objid and D.objsubid = 0
    left join pg_opclass C on D.refclassid = 'pg_opclass'::regclass and C.oid = D.refobjid and D.refobjsubid = 0
where C.opcnamespace = :schema_id::oid or C.opcnamespace is null and F.opfnamespace = :schema_id::oid
  #INC> and pg_catalog.age(P.xmin) <= #TXAGE
order by C.oid, F.oid
;


---- RetrieveExistentOperatorFamilies ----
select oid
from pg_catalog.pg_opfamily
where opfnamespace = :schema_id::oid
;


---- RetrieveOperatorFamilies ----
select O.oid as id,
       O.xmin as state_number,
       opfname as name,
       opfmethod as access_method_id,
       pg_catalog.pg_get_userbyid(O.opfowner) as "owner"
from pg_catalog.pg_opfamily O
where opfnamespace = :schema_id::oid
  #INC> and pg_catalog.age(xmin) <= #TXAGE
;

---- RetrieveExistentDataTypes ----
select oid
  from pg_catalog.pg_type
  where typnamespace = :schema_id::oid
;

---- RetrieveDataTypes ----
select T.oid as type_id,
       T.xmin as type_state_number,
       T.typname as type_name,
       T.typtype as type_sub_kind,
       T.typrelid as class_id,
       T.typbasetype as base_type_id,
       case when T.typtype in ('c','e') then null
            else pg_catalog.format_type(T.typbasetype, T.typtypmod) end as type_def,
       T.typndims as dimensions_number,
       T.typdefault as default_expression,
       T.typnotnull as mandatory,
       pg_catalog.pg_get_userbyid(T.typowner) as "owner"
from pg_catalog.pg_type T
         left outer join pg_catalog.pg_class C
             on T.typrelid = C.oid
where T.typnamespace = :schema_id::oid
  #INC> and pg_catalog.age(T.xmin) <= #TXAGE
  and (T.typtype in ('d','e') or
       C.relkind = 'c'::"char" or
       (T.typtype = 'b' and T.typelem = 0) or
       T.typtype = 'p' and not T.typisdefined)
order by 1
;


---- RetrieveExistentDataTypeChecks ----
select oid
  from pg_catalog.pg_constraint
  where contypid != 0 and connamespace = :schema_id::oid
;

---- RetrieveDataTypeChecks ----
select T.oid::bigint as type_id,
       C.oid::bigint as constraint_id,
       C.xmin as constraint_state_number,
       C.conname as constraint_name,
       #V70: pg_catalog.pg_get_expr(C.conbin, 0) #: C.consrc #. as predicate
from pg_catalog.pg_type T,
     pg_catalog.pg_constraint C
where T.typnamespace = :schema_id::oid
  and T.typtype = 'd'::"char"
  and T.oid = C.contypid
  #INC> and (pg_catalog.age(T.xmin) <= #TXAGE or pg_catalog.age(C.xmin) <= #TXAGE)
order by constraint_name
;


---- RetrieveExistentTables ----
select C.oid
  from pg_catalog.pg_class C
    #V70: #: left outer join pg_catalog.pg_partition_rule PR on C.oid = PR.parchildrelid #.
  where C.relkind in ('r', 'm', 'v', 'p', 'f')
    and #V70: not C.relispartition #: PR.oid is null #.
    and C.relnamespace = :schema_id::oid
;

---- RetrieveTables ----
select T.relkind as table_kind,
       T.relname as table_name,
       T.oid as table_id,
       T.xmin as table_state_number,
       #V70: false #: T.relhasoids #. as table_with_oids,
       T.reltablespace as tablespace_id,
       T.reloptions as options,
       #V60>T.relpersistence as persistence,
       (select '{' || pg_catalog.array_to_string(pg_catalog.array_agg(inhparent), ',') || '}' from (select inhparent::bigint from pg_catalog.pg_inherits where T.oid = inhrelid order by inhseqno) as bts) as ancestors,
       (select '{' || pg_catalog.array_to_string(pg_catalog.array_agg(inhrelid), ',') || '}' from (select inhrelid::bigint from pg_catalog.pg_inherits where T.oid = inhparent order by inhrelid) as its) as successors,
       pg_catalog.pg_get_userbyid(T.relowner) as "owner"
from pg_catalog.pg_class T
  #V70: #: left outer join pg_catalog.pg_partition_rule PR on T.oid = PR.parchildrelid #.
where T.relnamespace = :schema_id::oid
  and T.relkind in ('r', 'm', 'v', 'p', 'f')
  #V70: #: and T.relstorage <> 'x' #.
  and #V70: not T.relispartition #: PR.oid is null #.
  #INC> and pg_catalog.age(T.xmin) <= #TXAGE
order by table_kind, table_id
;


---- RetrieveStructAttributes ----
#INC> select type_id, att_position, att_name, att_type, att_dropped, dimensions_number from (
select T.oid as type_id,
       A.attnum as att_position,
       A.attname as att_name,
       pg_catalog.format_type(A.atttypid, A.atttypmod) as att_type,
       A.attndims as dimensions_number,
       A.attisdropped as att_dropped
#INC>     , min(pg_catalog.age(A.xmin)) over (partition by a.attrelid) as age
from pg_catalog.pg_type T
  join pg_catalog.pg_class C
    on T.typrelid = C.oid
  join pg_catalog.pg_attribute A
    on A.attrelid = C.oid
where T.typnamespace = :schema_id::oid
  and T.typtype = 'c'::"char"
  and C.relkind = 'c'::"char"
#INC> ) sub where age <= #TXAGE
order by #INC:type_id#:T.oid#.::bigint, #INC:att_position#:A.attnum#.
;


---- RetrieveEnumLabels ----
with types as (select distinct T.oid as type_id
               from pg_catalog.pg_type T
               join pg_catalog.pg_enum E
                 on T.oid = E.enumtypid
               where T.typnamespace = :schema_id::oid
                 and T.typtype = 'e'::"char"
               #INC> and pg_catalog.age(E.xmin) <= #TXAGE
               )
select T.type_id as enum_id,
       pg_catalog.array_agg(E.enumlabel::varchar) as enum_labels
from types T
join pg_catalog.pg_enum E
  on T.type_id = E.enumtypid
group by T.type_id
;


---- RetrieveColumns ----
with T as ( select #INC>distinct
                  T.oid as table_id, T.relname as table_name
            from pg_catalog.pg_class T
                 #INC>, pg_catalog.pg_attribute A
            where T.relnamespace = :schema_id::oid
              and T.relkind in ('r', 'm', 'v', 'f', 'p')
              #INC> and (pg_catalog.age(A.xmin) <= #TXAGE or pg_catalog.age(T.xmin) <= #TXAGE)
              #INC> and A.attrelid = T.oid
            )
select T.table_id,
       C.attnum as column_position,
       C.attname as column_name,
       C.xmin as column_state_number,
       C.atttypmod as type_mod,
       C.attndims as dimensions_number,
       pg_catalog.format_type(C.atttypid, C.atttypmod) as type_spec,
       C.atttypid as type_id,
       C.attnotnull as mandatory,
       #V70: pg_catalog.pg_get_expr(D.adbin, T.table_id) #: D.adsrc #. as column_default_expression,
       not C.attislocal as column_is_inherited,
       C.attisdropped as column_is_dropped
from T
  join pg_catalog.pg_attribute C on T.table_id = C.attrelid
  left join pg_catalog.pg_attrdef D on (C.attrelid, C.attnum) = (D.adrelid, D.adnum)
where attnum > 0
order by table_id, attnum
;


---- RetrieveDistributionKeys ----
select DP.localoid as table_id,
       #V60: '{' || array_to_string(DP.distkey, ',') || '}' #: DP.attrnums #. as distribution_keys
from pg_catalog.gp_distribution_policy DP
         inner join pg_catalog.pg_class T on t.oid = DP.localoid
where T.relnamespace = :schema_id::oid
  and T.relkind = 'r'
;


---- RetrieveExistentIndices ----
select IX.indexrelid
  from pg_catalog.pg_index IX,
    pg_catalog.pg_class IC
  where IC.oid = IX.indrelid
    and IC.relnamespace = :schema_id::oid
;

---- RetrieveIndices ----
select tab.oid               table_id,
       tab.relkind           table_kind,
       ind_stor.relname      index_name,
       ind_head.indexrelid   index_id,
       ind_stor.xmin         state_number,
       ind_head.indisunique  is_unique,
       ind_head.indisprimary is_primary,
       pg_catalog.pg_get_expr(ind_head.indpred, ind_head.indrelid) as condition,
       ind_stor.reltablespace tablespace_id,
       #V50: opcmethod #: 0 #. as access_method_id
from pg_catalog.pg_class tab
         join pg_catalog.pg_index ind_head
              on ind_head.indrelid = tab.oid
         join pg_catalog.pg_class ind_stor
              on tab.relnamespace = ind_stor.relnamespace and ind_stor.oid = ind_head.indexrelid
#V50>         left join pg_catalog.pg_opclass on pg_opclass.oid = ANY(indclass)
where tab.relnamespace = :schema_id::oid
        and tab.relkind in ('r', 'm', 'v', 'p')
        and ind_stor.relkind = 'i'
#INC>   and pg_catalog.age(ind_stor.xmin) <= #TXAGE


---- RetrieveIndexColumns ----
select ind_head.indexrelid index_id,
       k col_idx,
       true in_key,
       ind_head.indkey[k-1] column_position,
       #V50: ind_head.indoption[k-1] #: 0 #. column_options,
       #V60: ind_head.indcollation[k-1] #: null #. as collation,
       #V60: collname #: null #. as collation_str,
       ind_head.indclass[k-1] as opclass,
       case when opcdefault then null else opcname end as opclass_str,
       case
           when indexprs is null then null
           when ind_head.indkey[k-1] = 0 then chr(27) || pg_catalog.pg_get_indexdef(ind_head.indexrelid, k::int, true)
           else pg_catalog.pg_get_indexdef(ind_head.indexrelid, k::int, true)
       end as expression,
       #V50: amcanorder #: true #. can_order
from (select *, pg_catalog.generate_series(1, pg_catalog.array_upper(indkey, 1) + 1) k from pg_catalog.pg_index) ind_head
         join pg_catalog.pg_class ind_stor
              on ind_stor.oid = ind_head.indexrelid
#V60>         left join pg_catalog.pg_collation
#V60>                   on pg_collation.oid = ind_head.indcollation[k-1]
#V50>    #V70: cross join pg_catalog.pg_indexam_has_property(ind_stor.relam, 'can_order') amcanorder #: left join pg_catalog.pg_am am on ind_stor.relam = am.oid #.
         left join pg_catalog.pg_opclass
                   on pg_opclass.oid = ind_head.indclass[k-1]
where ind_stor.relnamespace = :schema_id::oid
  and ind_stor.relkind = 'i'
#INC>  and pg_catalog.age(ind_stor.xmin) <= #TXAGE
order by index_id, k


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
       conkey con_columns,
       #V60: conindid #: 0 #. index_id,
       confrelid ref_table_id,
       condeferrable is_deferrable,
       condeferred is_init_deferred,
       confupdtype on_update,
       confdeltype on_delete,
       #V60> connoinherit no_inherit,
       #V70: pg_catalog.pg_get_expr(conbin, T.oid) #: consrc #. con_expression,
       confkey ref_columns
from pg_catalog.pg_constraint C
         join pg_catalog.pg_class T
              on C.conrelid = T.oid
   where relkind in ('r', 'v', 'f', 'p')
     and relnamespace = :schema_id::oid
     and contype in ('p', 'u', 'f', 'c', 'x')
     and connamespace = :schema_id::oid
#INC> and pg_catalog.age(T.xmin) <= #TXAGE or pg_catalog.age(c.xmin) <= #TXAGE
;


---- RetrieveUsedArgumentTypes ----
with schema_procs as (select prorettype, proargtypes, proallargtypes
                      from pg_catalog.pg_proc
                      where pronamespace = :schema_id::oid
                        #INC: and pg_catalog.age(xmin) <= #TXAGE #. ),
     schema_opers as (select oprleft, oprright, oprresult
                      from pg_catalog.pg_operator
                      where oprnamespace = :schema_id::oid
                        #INC: and pg_catalog.age(xmin) <= #TXAGE #. ),
     schema_aggregates as (select A.aggtranstype
                           from pg_catalog.pg_aggregate A
                           join pg_catalog.pg_proc P
                             on A.aggfnoid = P.oid
                           where P.pronamespace = :schema_id::oid
                           #INC: and (pg_catalog.age(A.xmin) <= #TXAGE or pg_catalog.age(P.xmin) <= #TXAGE) #.),
     schema_arg_types as ( select prorettype as type_id
                           from schema_procs
                           union
                           select distinct unnest(proargtypes) as type_id
                           from schema_procs
                           union
                           select distinct unnest(proallargtypes) as type_id
                           from schema_procs
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
where type_id <> 0
;


---- RetrieveExistentRoutines ----
select oid
  from pg_catalog.pg_proc
  where #V70: prokind <> 'a' #: not proisagg #. and pronamespace = :schema_id::oid
;

---- RetrieveRoutines ----
with languages as (select oid as lang_oid, lanname as lang
                   from pg_catalog.pg_language),
     routines as (select proname as r_name,
                         prolang as lang_oid,
                         oid as r_id,
                         xmin as r_state_number,
                         proargnames as arg_names,
                         proargmodes as arg_modes,
                         proargtypes::int[] as in_arg_types,
                         proallargtypes::int[] as all_arg_types,
                         #SUPER> #V50> pg_catalog.pg_get_expr(proargdefaults, 'pg_catalog.pg_proc'::regclass) as arg_defaults,
                         #V50> provariadic as arg_variadic_id,
                         prorettype as ret_type_id,
                         proretset as ret_set,
                         #V70: prokind #: case when proisagg then 'a' else 'f' end #. as kind,
                         provolatile as volatile_kind,
                         proisstrict as is_strict,
                         prosecdef as is_security_definer,
                         #V50> proconfig as configuration_parameters,
                         #V50> procost as cost,
                         pg_catalog.pg_get_userbyid(proowner) as "owner"
                         #V50> ,prorows as rows
                  from pg_catalog.pg_proc
                  where pronamespace = :schema_id::oid
                    and #V70: prokind <> 'a' #: not proisagg #.
                    #INC: and pg_catalog.age(xmin) <= #TXAGE #.)
select *
from routines natural join languages
;


---- RetrieveExistentAggregates ----
select oid
  from pg_catalog.pg_proc
  where #V70: prokind = 'a' #: proisagg #. and pronamespace = :schema_id::oid
;


---- RetrieveAggregates ----
select P.oid as aggregate_id,
       P.xmin as state_number,
       P.proname as aggregate_name,
       P.proargnames as arg_names,
       P.proargmodes as arg_modes,
       P.proargtypes::int[] as in_arg_types,
       P.proallargtypes::int[] as all_arg_types,
       A.aggtransfn::oid as transition_function_id,
       A.aggtransfn::regproc::text as transition_function_name,
       A.aggtranstype as transition_type,
       A.aggfinalfn::oid as final_function_id,
       case when A.aggfinalfn::oid = 0 then null else A.aggfinalfn::regproc::varchar end as final_function_name,
       A.agginitval as initial_value,
       A.aggsortop as sort_operator_id,
       case when A.aggsortop = 0 then null else A.aggsortop::regoper::varchar end as sort_operator_name,
       pg_catalog.pg_get_userbyid(P.proowner) as "owner"
from pg_catalog.pg_aggregate A
join pg_catalog.pg_proc P
  on A.aggfnoid = P.oid
where P.pronamespace = :schema_id::oid
#INC> and (pg_catalog.age(A.xmin) <= #TXAGE or pg_catalog.age(P.xmin) <= #TXAGE)
order by P.oid
;


---- RetrieveExistentOperators ----
select oid
  from pg_catalog.pg_operator
  where oprnamespace = :schema_id::oid
;

---- RetrieveOperators ----
select O.oid as op_id,
       O.xmin as state_number,
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
       #V50: oprcanmerge#: false#. as merges,
       oprcanhash as hashes,
       pg_catalog.pg_get_userbyid(O.oprowner) as "owner"
from pg_catalog.pg_operator O
where oprnamespace = :schema_id::oid
  #INC> and pg_catalog.age(xmin) <= #TXAGE
;


---- RetrieveExistentRules ----
select RU.oid
  from pg_catalog.pg_rewrite RU,
       pg_catalog.pg_class RC
  where RC.oid = RU.ev_class
    and RC.relnamespace = :schema_id::oid
    and not RU.rulename = '_RETURN'
;

---- RetrieveRules ----
select R.ev_class as table_id,
       R.oid as rule_id,
       R.xmin as rule_state_number,
       R.rulename as rule_name,
       pg_catalog.translate(ev_type,'1234','SUID') as rule_event_code,
       #V50> R.ev_enabled as rule_fire_mode,
       R.is_instead as rule_is_instead
from pg_catalog.pg_rewrite R
where R.ev_class in (select oid
                     from pg_catalog.pg_class
                     where relnamespace = :schema_id::oid)
  #INC> and pg_catalog.age(R.xmin) <= #TXAGE
  and R.rulename != '_RETURN'::name
order by R.ev_class::bigint, ev_type
;


---- RetrieveExistentTriggers ----
select TG.oid
from pg_catalog.pg_trigger TG,
     pg_catalog.pg_class TC
where TC.oid = TG.tgrelid
  and TC.relnamespace = :schema_id::oid
;

---- RetrieveTriggers ----
select T.tgrelid as table_id,
       T.oid as trigger_id,
       T.xmin as trigger_state_number,
       T.tgname as trigger_name,
       T.tgfoid as function_id,
       pg_catalog.encode(T.tgargs, 'escape') as function_args,
       T.tgtype as bits,
       T.tgenabled as trigger_fire_mode
from pg_catalog.pg_trigger T
where T.tgrelid in (select oid
                    from pg_catalog.pg_class
                    where relnamespace = :schema_id::oid)
  #INC> and pg_catalog.age(T.xmin) <= #TXAGE
  and not #V60: T.tgisinternal #: T.tgisconstraint #.
;


---- RetrieveViewSources ----
select
       T.relkind as view_kind,
       T.oid as view_id,
       pg_catalog.pg_get_viewdef(T.oid, true) as source_text
from pg_catalog.pg_class T
  join pg_catalog.pg_namespace N on T.relnamespace = N.oid
where N.oid = :schema_id::oid
  and T.relkind in ('m','v')
  #INCSRC> and (pg_catalog.age(T.xmin) <= #SRCTXAGE or exists(
  #INCSRC>    select A.attrelid from pg_catalog.pg_attribute A where A.attrelid = T.oid and pg_catalog.age(A.xmin) <= #SRCTXAGE))
;


---- RetrieveRuleSources ----
with A as ( select oid as table_id, #V70: relkind #: case when relstorage = 'x' then 'e' else relkind end #. as table_kind
            from pg_catalog.pg_class
            where relnamespace = :schema_id::oid
              and relkind in ('r', 'm', 'v', 'f', 'p') )
select table_kind,
       table_id,
       R.oid as rule_id,
       pg_catalog.pg_get_ruledef(R.oid, true) as source_text
from A join pg_catalog.pg_rewrite R
        on A.table_id = R.ev_class
where R.rulename != '_RETURN'::name
  #INC> and pg_catalog.age(R.xmin) <= #SRCTXAGE
;


---- RetrieveFunctionSources ----
with system_languages as ( select oid as lang
                           from pg_catalog.pg_language
                           where lanname in ('c','internal') )
select PC.oid as id,
       #V50:
       pg_catalog.pg_get_function_arguments(PC.oid) as arguments_def,
       pg_catalog.pg_get_function_result(PC.oid) as result_def,
       #:
       (select distinct pg_catalog.array_to_string(ARRAY(select (case when arg_names is null then '' else arg_names[k] || ' ' end) || pg_catalog.format_type(T.oid, null)
                                                from pg_catalog.generate_series(1, pg_catalog.array_upper(arg_types, 1)) as k
                                                join pg_catalog.pg_type T ON T.oid = arg_types[k]
                                                order by k), ', ')
          from (select pg_catalog.string_to_array(pg_catalog.textin(pg_catalog.oidvectorout(PGPC.proargtypes)), ' ') arg_types,
                       PGPC.proargnames arg_names
                  from pg_proc PGPC
                  where PGPC.oid = PC.oid) oids_array) as arguments_def,
       (select distinct pg_catalog.format_type(PGT.oid, null)
          from pg_catalog.pg_type PGT
          where PGT.oid = PC.prorettype) as result_def,
      #.
       PC.prosrc as source_text
from pg_catalog.pg_proc PC
where PC.pronamespace = :schema_id::oid
  #INC> and pg_catalog.age(PC.xmin) <= #SRCTXAGE
  and #V70: PC.prokind <> 'a' #: not PC.proisagg #.
  and PC.prolang not in (select lang from system_languages)
  and PC.prosrc is not null
;


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
  and D.deptype = 'a'
  and C_TAB.relnamespace = :schema_id::oid
order by owner_id
;


---- RetrieveExistentExtensions ----
select oid from pg_catalog.pg_extension
;

---- RetrieveExtensions ----
select E.oid        as id,
       E.xmin       as state_number,
       extname      as name,
       extversion   as version,
       extnamespace as schema_id,
       nspname      as schema_name,
       array(select unnest
             from unnest(available_versions)
             where unnest > extversion) as available_updates
from pg_catalog.pg_extension E
       join pg_namespace N on E.extnamespace = N.oid
       left join (select name, array_agg(version) as available_versions
                  from pg_available_extension_versions()
                  group by name) V on E.extname = V.name
#INC> where pg_catalog.age(E.xmin) <= #TXAGE
;

---- RetrieveExtensionMembers ----
select E.oid   as extension_id,
       D.objid as member_id
from pg_extension E join pg_depend D
  on E.oid = D.refobjid and
     D.refclassid = 'pg_extension'::regclass::oid
where D.deptype = 'e'
order by extension_id
;

---- RetrieveExistentExternalTables ----
select oid from pg_catalog.pg_class
  where relstorage = 'x'
    and relnamespace = :schema_id::oid
;


---- RetrieveExternalTables ----
select E.xmin as state_number,
       E.reloid as id,
       C.relname as name,
       E.writable as writable,
       #V50: E.urilocation #: case when command is null then E.location else null end #. as locations,
       E.command as command,
       #V50: E.execlocation[1] #: case when command is not null then E.location[1] else null end #. as exec_location,
       E.fmttype as "format",
       E.fmtopts as format_options,
       E.encoding as "encoding",
       E.rejectlimit as reject_limit,
       E.rejectlimittype as reject_limit_type
from pg_catalog.pg_exttable E
  join pg_class C on E.reloid = C.oid
  where C.relnamespace = :schema_id::oid
#INC> and pg_catalog.age(E.xmin) <= #TXAGE
;

---- RetrieveExistentPartitions ----
select PR.oid from pg_catalog.pg_partition P
    join pg_catalog.pg_class C on P.parrelid = C.oid
    join pg_catalog.pg_partition_rule PR on P.oid = PR.paroid
  where C.relnamespace = :schema_id::oid
;


---- RetrievePartitions ----
select PR.oid as id,
       P.parlevel as level,
       PR.parname as name,
       P.parkind as kind,
       P.parrelid as table_id,
       '{' || pg_catalog.array_to_string(P.paratts, ',') || '}' as columns,
       PR_PARENT.oid as parent_id,
       pg_catalog.pg_get_expr(PR.parlistvalues, 'pg_catalog.pg_partition_rule'::regclass) as values_list,
       pg_catalog.pg_get_expr(PR.parrangestart, 'pg_catalog.pg_partition_rule'::regclass) as start_value,
       pg_catalog.pg_get_expr(PR.parrangeend, 'pg_catalog.pg_partition_rule'::regclass) as end_value,
       pg_catalog.pg_get_expr(PR.parrangeevery, 'pg_catalog.pg_partition_rule'::regclass) as every_value,
       PR.parrangestartincl as start_inclusive,
       PR.parrangeendincl as end_inclusive,
       PR.parisdefault as is_default,
       PR.parruleord as "order"
from pg_catalog.pg_partition P
  join pg_catalog.pg_partition_rule PR on P.oid = PR.paroid
  join pg_class C on P.parrelid = C.oid
  left join pg_catalog.pg_partition_rule PR_PARENT on PR.parparentrule = PR_PARENT.oid
where not P.paristemplate
  and C.relnamespace = :schema_id::oid
#INC> and pg_catalog.age(PR.xmin) <= #TXAGE
order by PR.oid::bigint

---- RetrieveTimeZones ----
select name, is_dst from pg_catalog.pg_timezone_names
union distinct
select abbrev as name, is_dst from pg_catalog.pg_timezone_abbrevs

---- RetrieveDateStyle ----
show DateStyle

---- RetrieveExistentCollations ----
select oid from pg_catalog.pg_collation
  where collnamespace = :schema_id::oid
;

---- RetrieveCollations ----
select oid as id,
       xmin as state_number,
       collname as name,
       collcollate as lc_collate,
       collctype as lc_ctype,
       pg_catalog.pg_get_userbyid(collowner) as "owner"
from pg_catalog.pg_collation
where collnamespace = :schema_id::oid
  #INC> and pg_catalog.age(xmin) <= #TXAGE
;

---- RetrieveExistentForeignDataWrappers ----
select oid from pg_catalog.pg_foreign_data_wrapper
;

---- RetrieveForeignDataWrappers ----
select fdw.oid as id,
       fdw.xmin as state_number,
       fdw.fdwname as name,
       #V60>pr.proname as handler,
       #V60>nspc.nspname as handler_schema,
       pr2.proname as validator,
       nspc2.nspname as validator_schema,
       fdw.fdwoptions as options,
       pg_catalog.pg_get_userbyid(fdw.fdwowner) as "owner"
from pg_catalog.pg_foreign_data_wrapper fdw
     #V60>left outer join pg_catalog.pg_proc pr on fdw.fdwhandler = pr.oid
     #V60>left outer join pg_catalog.pg_namespace nspc on pr.pronamespace = nspc.oid
     left outer join pg_catalog.pg_proc pr2 on fdw.fdwvalidator = pr2.oid
     left outer join pg_catalog.pg_namespace nspc2 on pr2.pronamespace = nspc2.oid
  #INC> where pg_catalog.age(fdw.xmin) <= #TXAGE
;

---- RetrieveExistentForeignServers ----
select oid from pg_catalog.pg_foreign_server
;

---- RetrieveForeignServers ----
select srv.oid as id,
       srv.srvfdw as fdw_id,
       srv.xmin as state_number,
       srv.srvname as name,
       srv.srvtype as type,
       srv.srvversion as version,
       srv.srvoptions as options,
       pg_catalog.pg_get_userbyid(srv.srvowner) as "owner"
from pg_catalog.pg_foreign_server srv
  #INC> where pg_catalog.age(srv.xmin) <= #TXAGE
;

---- RetrieveExistentUserMappingsSuperUser ----
select oid from pg_catalog.pg_user_mapping
;

---- RetrieveUserMappingsSuperUser ----
select oid as id,
       umserver as server_id,
       case when umuser = 0 then null else pg_catalog.pg_get_userbyid(umuser) end as user,
       umoptions as options
from pg_catalog.pg_user_mapping
#INC>  where pg_catalog.age(xmin) <= #TXAGE
order by server_id
;


---- RetrieveUserMappings ----
select umid as id,
       srvid as server_id,
       usename as user,
       umoptions as options
from pg_catalog.pg_user_mappings
order by server_id
;


---- RetrieveForeignTables ----
select ft.ftrelid as table_id,
       srv.srvname as table_server,
       ft.ftoptions as table_options,
       pg_catalog.pg_get_userbyid(cls.relowner) as "owner"
from pg_catalog.pg_foreign_table ft
     left outer join pg_catalog.pg_foreign_server srv on ft.ftserver = srv.oid
     join pg_catalog.pg_class cls on ft.ftrelid = cls.oid
where cls.relnamespace = :schema_id::oid
  #INC> and pg_catalog.age(ft.xmin) <= #TXAGE
order by table_id
;

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
       C.castcontext #V60:,
       C.castmethod #.
from pg_cast C
     left outer join pg_proc F on C.castfunc::oid = F.oid
     left outer join pg_namespace FN on F.pronamespace = FN.oid
     join pg_type S on C.castsource::oid = S.oid
     join pg_namespace SN on S.typnamespace = SN.oid
     join pg_type T on C.casttarget::oid = T.oid
     join pg_namespace TN on T.typnamespace = TN.oid
#INC> where pg_catalog.age(C.xmin) <= #TXAGE
;