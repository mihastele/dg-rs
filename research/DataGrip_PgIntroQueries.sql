---- ServerStartupTime ----
select round(extract(epoch from pg_postmaster_start_time() at time zone 'UTC')) as startup_time;
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
select oid from pg_catalog.pg_language
;

---- ListLanguages ----
select l.oid as id, l.xmin state_number, lanname as name, lanpltrusted as trusted,
       h.proname as handler, hs.nspname as handlerSchema,
       i.proname as inline, isc.nspname as inlineSchema,
       v.proname as validator, vs.nspname as validatorSchema
from pg_catalog.pg_language l
    left join pg_catalog.pg_proc h on h.oid = lanplcallfoid
    left join pg_catalog.pg_namespace hs on hs.oid = h.pronamespace
    left join pg_catalog.pg_proc i on i.oid = laninline
    left join pg_catalog.pg_namespace isc on isc.oid = i.pronamespace
    left join pg_catalog.pg_proc v on v.oid = lanvalidator
    left join pg_catalog.pg_namespace vs on vs.oid = v.pronamespace
#INC> where pg_catalog.age(l.xmin) <= #TXAGE
order by lanname
;


----RetrieveExistentEventTriggers ----
select oid from pg_catalog.pg_event_trigger
;

---- RetrieveEventTriggers ----
select t.oid as id,
       t.xmin as state_number,
       t.evtname as name,
       t.evtevent as event,
       t.evtfoid as routine_id,
       pg_catalog.pg_get_userbyid(t.evtowner) as owner,
       t.evttags as tags,
       case when t.evtenabled = 'D' then 1 else 0 end as is_disabled
from pg_catalog.pg_event_trigger t
#INC> where pg_catalog.age(t.xmin) <= #TXAGE
;

---- ListSchemas ----
select N.oid::bigint as id,
       N.xmin as state_number,
       nspname as name,
       D.description,
       pg_catalog.pg_get_userbyid(N.nspowner) as "owner"
from pg_catalog.pg_namespace N
  left join pg_catalog.pg_description D on N.oid = D.objoid
order by case when nspname = pg_catalog.current_schema() then -1::bigint else N.oid::bigint end
;


---- RetrieveRoles ----
select R.oid::bigint as role_id, rolname as role_name,
  rolsuper is_super, rolinherit is_inherit,
  rolcreaterole can_createrole, rolcreatedb can_createdb,
  rolcanlogin can_login, #V91: rolreplication #: false #. is_replication,
  rolconnlimit conn_limit, rolvaliduntil valid_until,
  #V95: rolbypassrls #: false #. bypass_rls, rolconfig config,
  D.description
from pg_catalog.pg_roles R
  left join pg_catalog.pg_shdescription D on D.objoid = R.oid
;

---- RetrieveExistentTablespaces ----
select oid::bigint from pg_catalog.pg_tablespace
;

---- RetrieveTablespaces ----
select T.oid::bigint as id, T.spcname as name,
       T.xmin as state_number, pg_catalog.pg_get_userbyid(T.spcowner) as owner,
       #V92: pg_catalog.pg_tablespace_location(T.oid) #: null #. as location,
       #V94: T.spcoptions #: null #. as options,
       D.description as comment
from pg_catalog.pg_tablespace T
  left join pg_catalog.pg_shdescription D on D.objoid = T.oid
#INC>where pg_catalog.age(T.xmin) <= #TXAGE
;


---- StateNumber ----
select L.transactionid::varchar::bigint as transaction_id
from pg_catalog.pg_locks L
where L.transactionid is not null
order by pg_catalog.age(L.transactionid) desc
limit 1
;


---- CurrentXid ----
select case
  when pg_catalog.pg_is_in_recovery()
    then null
  else
    (pg_catalog.txid_current() % 4294967296)::varchar::bigint
  end as current_txid
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
where C.connamespace = :schema_id::oid and D.classoid = 'pg_catalog.pg_constraint'::regclass
union all
select D.objoid id, array[D.objsubid]
from pg_catalog.pg_description D
  join pg_catalog.pg_trigger T on T.oid = D.objoid
  join pg_catalog.pg_class C on C.oid = T.tgrelid
where C.relnamespace = :schema_id::oid and D.classoid = 'pg_catalog.pg_trigger'::regclass
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
union all
select D.objoid id, array[D.objsubid]
from pg_catalog.pg_description D
  join pg_catalog.pg_opfamily O on O.oid = D.objoid
where O.opfnamespace = :schema_id::oid and D.classoid = 'pg_catalog.pg_opfamily'::regclass
#V91:union all
select D.objoid id, array[D.objsubid]
from pg_catalog.pg_description D
  join pg_catalog.pg_collation C on C.oid = D.objoid
where C.collnamespace = :schema_id::oid and D.classoid = 'pg_catalog.pg_collation'::regclass
#.
#V95:union all
select D.objoid id, array[D.objsubid]
from pg_catalog.pg_description D
  join pg_catalog.pg_policy P on P.oid = D.objoid
  join pg_catalog.pg_class C on P.polrelid = C.oid
where C.relnamespace = :schema_id::oid  and D.classoid = 'pg_catalog.pg_policy'::regclass
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
  #V93>'pg_catalog.pg_event_trigger'::regclass,
  'pg_catalog.pg_am'::regclass,
  'pg_catalog.pg_cast'::regclass,
  'pg_catalog.pg_foreign_data_wrapper'::regclass,
  'pg_catalog.pg_foreign_server'::regclass,
  'pg_catalog.pg_language'::regclass
  #V91:,
  'pg_catalog.pg_extension'::regclass
  #.
)
;

---- RetrieveSchemaComments ----
select D.objoid id, C.relkind::char as kind, D.objsubid sub_id, D.description
from pg_catalog.pg_description D
  join pg_catalog.pg_class C on D.objoid = C.oid
where C.relnamespace = :schema_id::oid and C.relkind != 'c' and D.classoid = 'pg_catalog.pg_class'::regclass
#INC> and pg_catalog.age(D.xmin) <= #TXAGE
-- all table-like things + seqs + iets anders?
union all
select T.oid id, 'T'::char as kind, D.objsubid sub_id, D.description
from pg_catalog.pg_description D
  join pg_catalog.pg_type T on T.oid = D.objoid or T.typrelid = D.objoid
  left join pg_catalog.pg_class C on T.typrelid = C.oid
where T.typnamespace = :schema_id::oid and (C.relkind = 'c' or C.relkind is null)
#INC> and pg_catalog.age(D.xmin) <= #TXAGE
-- relkind = c (composite types?)
union all
select D.objoid id, pg_catalog.translate(C.contype, 'pufc', 'kkxz')::char as kind, D.objsubid sub_id, D.description
from pg_catalog.pg_description D
  join pg_catalog.pg_constraint C on D.objoid = C.oid
where C.connamespace = :schema_id::oid and D.classoid = 'pg_catalog.pg_constraint'::regclass
#INC> and pg_catalog.age(D.xmin) <= #TXAGE
-- table constraints
union all
select D.objoid id, 't'::char as kind, D.objsubid sub_id, D.description
from pg_catalog.pg_description D
  join pg_catalog.pg_trigger T on T.oid = D.objoid
  join pg_catalog.pg_class C on C.oid = T.tgrelid
where C.relnamespace = :schema_id::oid and D.classoid = 'pg_catalog.pg_trigger'::regclass
#INC> and pg_catalog.age(D.xmin) <= #TXAGE
-- triggers
union all
select D.objoid id, 'R'::char as kind, D.objsubid sub_id, D.description
from pg_catalog.pg_description D
  join pg_catalog.pg_rewrite R on R.oid = D.objoid
  join pg_catalog.pg_class C on C.oid = R.ev_class
where C.relnamespace = :schema_id::oid and D.classoid = 'pg_catalog.pg_rewrite'::regclass
#INC> and pg_catalog.age(D.xmin) <= #TXAGE
-- rules
union all
select D.objoid id, 'F'::char as kind, D.objsubid sub_id, D.description
from pg_catalog.pg_description D
  join pg_catalog.pg_proc P on P.oid = D.objoid
where P.pronamespace = :schema_id::oid and D.classoid = 'pg_catalog.pg_proc'::regclass
#INC> and pg_catalog.age(D.xmin) <= #TXAGE
-- more routines
union all
select D.objoid id, 'O'::char as kind, D.objsubid sub_id, D.description
from pg_catalog.pg_description D
  join pg_catalog.pg_operator O on O.oid = D.objoid
where O.oprnamespace = :schema_id::oid and D.classoid = 'pg_catalog.pg_operator'::regclass
#INC> and pg_catalog.age(D.xmin) <= #TXAGE
-- operators
union all
select D.objoid id, 'f'::char as kind, D.objsubid sub_id, D.description
from pg_catalog.pg_description D
  join pg_catalog.pg_opfamily O on O.oid = D.objoid
where O.opfnamespace = :schema_id::oid and D.classoid = 'pg_catalog.pg_opfamily'::regclass
#INC> and pg_catalog.age(D.xmin) <= #TXAGE
-- op families
union all
select D.objoid id, 'c'::char as kind, D.objsubid sub_id, D.description
from pg_catalog.pg_description D
  join pg_catalog.pg_opclass O on O.oid = D.objoid
where O.opcnamespace = :schema_id::oid and D.classoid = 'pg_catalog.pg_opclass'::regclass
#INC> and pg_catalog.age(D.xmin) <= #TXAGE
-- op class
  #V91:union all
select D.objoid id, 'C'::char as kind, D.objsubid sub_id, D.description
from pg_catalog.pg_description D
  join pg_catalog.pg_collation C on C.oid = D.objoid
where C.collnamespace = :schema_id::oid and D.classoid = 'pg_catalog.pg_collation'::regclass
#INC> and pg_catalog.age(D.xmin) <= #TXAGE
#.
-- collations
  #V95:union all
select D.objoid id, 'P'::char as kind, D.objsubid sub_id, D.description
from pg_catalog.pg_description D
       join pg_catalog.pg_policy P on P.oid = D.objoid
       join pg_catalog.pg_class C on P.polrelid = C.oid
where C.relnamespace = :schema_id::oid and D.classoid = 'pg_catalog.pg_policy'::regclass
#INC> and pg_catalog.age(D.xmin) <= #TXAGE
#.
-- security policies (also by table name...)

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
select D.objoid id, 't'::char as kind, D.objsubid sub_id, D.description
from pg_catalog.pg_description D
       join pg_catalog.pg_trigger T on T.oid = D.objoid
       join pg_catalog.pg_class C on C.oid = T.tgrelid
where C.relnamespace = :schema_id::oid and D.classoid = 'pg_catalog.pg_trigger'::regclass
and C.relname in ( :[*f_names] )

---- RetrieveSchemaCommentsFragTableRules ----
select D.objoid id, 'R'::char as kind, D.objsubid sub_id, D.description
from pg_catalog.pg_description D
       join pg_catalog.pg_rewrite R on R.oid = D.objoid
       join pg_catalog.pg_class C on C.oid = R.ev_class
where C.relnamespace = :schema_id::oid and D.classoid = 'pg_catalog.pg_rewrite'::regclass
and C.relname in ( :[*f_names] )

---- RetrieveSchemaCommentsFragTableIndices ----
select D.objoid id, ind_store.relkind::char as kind, D.objsubid sub_id, D.description
from pg_catalog.pg_class ind_store
       join pg_catalog.pg_index ind_head on ind_store.oid = ind_head.indexrelid
       join pg_catalog.pg_class tab on tab.relnamespace = ind_store.relnamespace
       join pg_catalog.pg_description D on ind_store.oid = D.objoid
where ind_store.relkind in ('i', 'I')
  and tab.relkind in ('r', 'm', 'v', 'p')
  and D.classoid = 'pg_catalog.pg_class'::regclass
  and tab.relnamespace = :schema_id::oid
  and tab.relname in ( :[*f_names] )

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
select D.objoid id, 'c'::char as kind, D.objsubid sub_id, D.description
from pg_catalog.pg_description D
       join pg_catalog.pg_opclass O on O.oid = D.objoid
where O.opcnamespace = :schema_id::oid and D.classoid = 'pg_catalog.pg_opclass'::regclass
and O.opcname in ( :[*f_names] )

---- RetrieveSchemaCommentsFragOpFamilies ----
select D.objoid id, 'f'::char as kind, D.objsubid sub_id, D.description
from pg_catalog.pg_description D
       join pg_catalog.pg_opfamily O on O.oid = D.objoid
where O.opfnamespace = :schema_id::oid and D.classoid = 'pg_catalog.pg_opfamily'::regclass
and O.opfname in ( :[*f_names] )

---- RetrieveSchemaCommentsFragCollations ----
select D.objoid id, 'C'::char as kind, D.objsubid sub_id, D.description
from pg_catalog.pg_description D
       join pg_catalog.pg_collation C on C.oid = D.objoid
where C.collnamespace = :schema_id::oid and D.classoid = 'pg_catalog.pg_collation'::regclass
and C.collname in ( :[*f_names] )

---- RetrieveSchemaCommentsFragSecPolicies ----
#V95:
select D.objoid id, 'P'::char as kind, D.objsubid sub_id, D.description
from pg_catalog.pg_description D
       join pg_catalog.pg_policy P on P.oid = D.objoid
       join pg_catalog.pg_class C on P.polrelid = C.oid
where C.relnamespace = :schema_id::oid and D.classoid = 'pg_catalog.pg_policy'::regclass
and C.relname in ( :[*f_names] )
#:
select D.objoid id, 'P'::char as kind, D.objsubid sub_id, D.description
from pg_catalog.pg_description D where false
#.

---- RetrieveDatabaseComments ----
select D.objoid id, case
    #V93>when 'pg_catalog.pg_event_trigger'::regclass = classoid then 'T'
    when 'pg_catalog.pg_am'::regclass = classoid then 'A'
    when 'pg_catalog.pg_cast'::regclass = classoid then 'C'
    when 'pg_catalog.pg_foreign_data_wrapper'::regclass = classoid then 'W'
    when 'pg_catalog.pg_foreign_server'::regclass = classoid then 'S'
    when 'pg_catalog.pg_language'::regclass = classoid then 'L'
    #V91:
    when 'pg_catalog.pg_extension'::regclass = classoid then 'E'
    #.
  end as kind,
  D.objsubid sub_id, D.description
from pg_catalog.pg_description D
where classoid in (
  #V93>'pg_catalog.pg_event_trigger'::regclass,
  'pg_catalog.pg_am'::regclass,
  'pg_catalog.pg_cast'::regclass,
  'pg_catalog.pg_foreign_data_wrapper'::regclass,
  'pg_catalog.pg_foreign_server'::regclass,
  'pg_catalog.pg_language'::regclass
  #V91:,
  'pg_catalog.pg_extension'::regclass
  #.
)
#INC> and pg_catalog.age(D.xmin) <= #TXAGE


---- RetrieveStates ----
select distinct oid, xmin
from pg_catalog.pg_namespace
where oid in (OIDS)
union
select distinct oid, xmin
from pg_catalog.pg_type
where oid in (OIDS)
union
(with ar as (
  select C.oid,
         least(age(C.xmin), age(A.xmin)) lage,
         case when age(C.xmin) < age(A.xmin) then C.xmin else A.xmin end larg
  from pg_catalog.pg_class C
    join pg_catalog.pg_attribute A on A.attrelid = C.oid
    where C.oid in (OIDS))
select distinct on (oid) oid, larg xmin from ar
order by oid, lage)
union
select distinct oid, xmin
from pg_catalog.pg_proc
where oid in (OIDS)
union
select distinct oid, xmin
from pg_catalog.pg_operator
where oid in (OIDS)
union
select distinct oid, xmin
from pg_catalog.pg_constraint
where oid in (OIDS)
union
#V93:select distinct oid, xmin
from pg_catalog.pg_event_trigger
where oid in (OIDS)
union
#.
#V91:select distinct oid, xmin
from pg_catalog.pg_collation
where oid in (OIDS)
union
#.
select distinct oid, xmin
from pg_catalog.pg_rewrite
where oid in (OIDS)
union
select distinct oid, xmin
from pg_catalog.pg_trigger
where oid in (OIDS)
union
select distinct oid, xmin
from pg_catalog.pg_am
where oid in (OIDS)
union
select distinct oid, xmin
from pg_catalog.pg_cast
where oid in (OIDS)
union
select distinct oid, xmin
from pg_catalog.pg_foreign_data_wrapper
where oid in (OIDS)
union
select distinct oid, xmin
from pg_catalog.pg_language
where oid in (OIDS)
union
select distinct oid, xmin
from pg_catalog.pg_foreign_server
where oid in (OIDS)
union
select distinct oid, xmin
from pg_catalog.pg_opfamily
where oid in (OIDS)
union
select distinct oid, xmin
from pg_catalog.pg_opclass
where oid in (OIDS)
#V91:union
select distinct oid, xmin
from pg_catalog.pg_extension
where oid in (OIDS)
#.
#V95:union
select distinct oid, xmin
from pg_catalog.pg_policy
where oid in (OIDS)
#.
#SUPER:union
select distinct oid, xmin
from pg_catalog.pg_user_mapping
where oid in (OIDS)
#.
;

---- RetrieveExistentSequences ----
select oid
from pg_catalog.pg_class
where relkind = 'S'
  and relnamespace = :schema_id::oid
;


---- RetrieveSequences10 ----
select cls.xmin as sequence_state_number,
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
#INC>  and pg_catalog.age(cls.xmin) <= #TXAGE
#FRAG> and cls.relname in ( :[*f_names] )
;


---- RetrieveSequences ----
with T as (
                select oid as sequence_id,
                       relname as sequence_name,
                       pg_catalog.pg_get_userbyid(relowner) as "owner",
                       #V91:
                       case when has_sequence_privilege(oid, 'SELECT, UPDATE, USAGE') then trim(both '()' from pg_catalog.pg_sequence_parameters(oid)::varchar)
                       else null::varchar
                       end as sequence_params,
                       #.
                       xmin as sequence_state_number
                       from pg_catalog.pg_class
                         where relnamespace = :schema_id::oid
                         and relkind = 'S'
                         #INC>  and pg_catalog.age(xmin) <= #TXAGE
                         #FRAG> and relname in ( :[*f_names] )
                )
select sequence_id,
       sequence_name,
       #V91:
       pg_catalog.split_part(sequence_params, ',', 1)::bigint as start_value,
       pg_catalog.split_part(sequence_params, ',', 2)::bigint as min_value,
       pg_catalog.split_part(sequence_params, ',', 3)::bigint as max_value,
       pg_catalog.split_part(sequence_params, ',', 4)::bigint as inc_value,
       pg_catalog.lower(pg_catalog.split_part(sequence_params, ',', 5)) LIKE '%t%' as cycle_option,
       #.
       sequence_state_number,
       "owner"
from T
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
       T.typcategory as type_category,
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
  #FRAG> and T.typname in ( :[*f_names] )
  #INC> and pg_catalog.age(T.xmin) <= #TXAGE
  and (T.typtype in ('d','e') or
       C.relkind = 'c'::"char" or
       (T.typtype = 'b' and (T.typelem = 0 OR T.typcategory <> 'A')) or
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
       #V120: pg_catalog.pg_get_expr(C.conbin, C.conrelid) #: C.consrc #. as predicate
from pg_catalog.pg_type T,
     pg_catalog.pg_constraint C
where T.typnamespace = :schema_id::oid
  and T.typtype = 'd'::"char"
  and T.oid = C.contypid
  and #V120: pg_catalog.pg_get_expr(C.conbin, C.conrelid) #: C.consrc #. is not null
  #INC> and (pg_catalog.age(T.xmin) <= #TXAGE or pg_catalog.age(C.xmin) <= #TXAGE)
order by constraint_name
-- todo think abt frag?
;


---- RetrieveExistentTables ----
select oid from pg_catalog.pg_class C
where relkind in ('r', 'm', 'v', 'p', 'f')
  and relnamespace = :schema_id::oid
;


---- RetrieveTables ----
select T.relkind as table_kind,
       T.relname as table_name,
       T.oid as table_id,
       T.xmin as table_state_number,
       #V120: false #: T.relhasoids #. as table_with_oids,
       T.reltablespace as tablespace_id,
       T.reloptions as options,
       #V91>T.relpersistence as persistence,
       (select pg_catalog.array_agg(inhparent::bigint order by inhseqno)::varchar from pg_catalog.pg_inherits where T.oid = inhrelid) as ancestors,
       (select pg_catalog.array_agg(inhrelid::bigint order by inhrelid)::varchar from pg_catalog.pg_inherits where T.oid = inhparent) as successors,
       #V99: T.relispartition #: false #. as is_partition,
       #V99: pg_catalog.pg_get_partkeydef(T.oid) #: null #. as partition_key,
       #V99: pg_catalog.pg_get_expr(T.relpartbound, T.oid) #: null #. as partition_expression,
       T.relam am_id,
       pg_catalog.pg_get_userbyid(T.relowner) as "owner"
from pg_catalog.pg_class T
where relnamespace = :schema_id::oid
       and relkind in ('r', 'm', 'v', 'f', 'p')
#INC>  and pg_catalog.age(T.xmin) <= #TXAGE
#FRAG> and T.relname in ( :[*f_names] )
order by table_kind, table_id
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
  #FRAG> and cls.relname in ( :[*f_names] )
order by table_id
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
#FRAG> and T.typname in ( :[*f_names] )
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
               #FRAG> and T.typname in ( :[*f_names] )
               #INC> and pg_catalog.age(E.xmin) <= #TXAGE
               )
select T.type_id as enum_id,
       pg_catalog.array_agg(E.enumlabel::varchar #V91: order by E.enumsortorder #.) as enum_labels
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
             #FRAG> and T.relname in ( :[*f_names] )
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
       #V120: pg_catalog.pg_get_expr(D.adbin, T.table_id) #: D.adsrc #. as column_default_expression,
       not C.attislocal as column_is_inherited,
       #V92> C.attfdwoptions as options,
       C.attisdropped as column_is_dropped,
       #V99: C.attidentity #: null #. as identity_kind,
       #V120: C.attgenerated #: null #. as generated
from T
  join pg_catalog.pg_attribute C on T.table_id = C.attrelid
  left join pg_catalog.pg_attrdef D on (C.attrelid, C.attnum) = (D.adrelid, D.adnum)
where attnum > 0
order by table_id, attnum
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
       #V150: ind_head.indnullsnotdistinct #: false #. nulls_not_distinct,
       pg_catalog.pg_get_expr(ind_head.indpred, ind_head.indrelid) as condition,
       (select pg_catalog.array_agg(inhparent::bigint order by inhseqno)::varchar from pg_catalog.pg_inherits where ind_stor.oid = inhrelid) as ancestors,
       ind_stor.reltablespace tablespace_id,
       opcmethod as access_method_id
from pg_catalog.pg_class tab
         join pg_catalog.pg_index ind_head
              on ind_head.indrelid = tab.oid
         join pg_catalog.pg_class ind_stor
              on tab.relnamespace = ind_stor.relnamespace and ind_stor.oid = ind_head.indexrelid
         left join pg_catalog.pg_opclass on pg_opclass.oid = ANY(indclass)
where tab.relnamespace = :schema_id::oid
        and tab.relkind in ('r', 'm', 'v', 'p')
        and ind_stor.relkind in ('i', 'I')
#FRAG>  and tab.relname in ( :[*f_names] )
#INC>   and pg_catalog.age(ind_stor.xmin) <= #TXAGE


---- RetrieveIndexColumns ----
#FRAG:
with T as (
  select T.oid as oid
  from pg_catalog.pg_class T
  where T.relnamespace = :schema_id::oid
    and T.relkind in ('r', 'm', 'v', 'p', 'f')
    and T.relname in ( :[*f_names] )
)
#.
select ind_head.indexrelid index_id,
       k col_idx,
       #V120: k <= indnkeyatts #: true #. in_key,
       ind_head.indkey[k-1] column_position,
       ind_head.indoption[k-1] column_options,
       #V91: ind_head.indcollation[k-1] #: null #. as collation,
       #V91: colln.nspname #: null #. as collation_schema,
       #V91: collname #: null #. as collation_str,
       ind_head.indclass[k-1] as opclass,
       case when opcdefault then null else opcn.nspname end as opclass_schema,
       case when opcdefault then null else opcname end as opclass_str,
       case
           when indexprs is null then null
           when ind_head.indkey[k-1] = 0 then chr(27) || pg_catalog.pg_get_indexdef(ind_head.indexrelid, k::int, true)
           else pg_catalog.pg_get_indexdef(ind_head.indexrelid, k::int, true)
       end as expression,
       amcanorder can_order
from #V94: pg_catalog.pg_index #: (select *, pg_catalog.generate_subscripts(indkey::int[], 1) + 1 k from pg_catalog.pg_index) #. ind_head
         join pg_catalog.pg_class ind_stor
              on ind_stor.oid = ind_head.indexrelid
#V94>    cross join unnest(ind_head.indkey) with ordinality u(u, k)
#V91>         left join pg_catalog.pg_collation
#V91>                   on pg_collation.oid = ind_head.indcollation[k-1]
#V91>         left join pg_catalog.pg_namespace colln on collnamespace = colln.oid
#V96:  cross join pg_catalog.pg_indexam_has_property(ind_stor.relam, 'can_order') amcanorder #: left join pg_catalog.pg_am am on ind_stor.relam = am.oid#.
         left join pg_catalog.pg_opclass
                   on pg_opclass.oid = ind_head.indclass[k-1]
         left join pg_catalog.pg_namespace opcn on opcnamespace = opcn.oid
  #FRAG> join T on ind_head.indrelid = T.oid
where ind_stor.relnamespace = :schema_id::oid
  and ind_stor.relkind in ('i', 'I')
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
       C.xmin::varchar::bigint con_state_id,
       conname con_name,
       contype con_kind,
       conkey con_columns,
       conindid index_id,
       confrelid ref_table_id,
       condeferrable is_deferrable,
       condeferred is_init_deferred,
       #V180: not conenforced #: false #. is_not_enforced,
       #V180: not convalidated #: false #. is_not_validated,
       #V180: conperiod #: false #. is_defined_with_period,
       confupdtype on_update,
       confdeltype on_delete,
       #V92> connoinherit no_inherit,
       #V120: pg_catalog.pg_get_expr(conbin, T.oid) #: consrc #. con_expression,
       confkey ref_columns,
       conexclop::int[] excl_operators,
       array(select unnest::regoper::varchar from unnest(conexclop)) excl_operators_str
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
     schema_aggregates as (select A.aggtranstype #V94:, A.aggmtranstype #.
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
                           #V94:
                           union
                           select aggmtranstype::oid as type_id
                           from schema_aggregates
                           #.
                           )
select type_id, pg_catalog.format_type(type_id, null) as type_spec
from schema_arg_types
where type_id <> 0 -- todo unclear how to frag
;


---- RetrieveExistentRoutines ----
select oid
from pg_catalog.pg_proc
where #V110: prokind != 'a'#: not proisagg#. and pronamespace = :schema_id::oid
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
                         pg_catalog.pg_get_expr(proargdefaults, 0) as arg_defaults,
                         provariadic as arg_variadic_id,
                         prorettype as ret_type_id,
                         proretset as ret_set,
                         #V110: prokind #: case when proiswindow then 'w'
                                                when proisagg then 'a'
                                                else 'f'
                                           end #. as kind,
                         provolatile as volatile_kind,
                         proisstrict as is_strict,
                         prosecdef as is_security_definer,
                         proconfig as configuration_parameters,
                         procost as cost,
                         pg_catalog.pg_get_userbyid(proowner) as "owner",
                         prorows as rows #V92:,
                         proleakproof as is_leakproof #. #V96:,
                         proparallel as concurrency_kind #.
                  from pg_catalog.pg_proc
                  where pronamespace = :schema_id::oid
                    #FRAG> and proname in ( :[*f_names] )
                    and not #V110: (prokind = 'a') #: proisagg #.
                    #INC: and pg_catalog.age(xmin) <= #TXAGE #.)
select *
from routines natural join languages
;


---- RetrieveExistentAggregates ----
select oid
from pg_catalog.pg_proc
where #V110: prokind = 'a'#: proisagg#. and pronamespace = :schema_id::oid
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
       case when A.aggfinalfn::oid = 0 then 0 else P.prorettype end as final_return_type,
       A.agginitval as initial_value,
       A.aggsortop as sort_operator_id,
       case when A.aggsortop = 0 then null else A.aggsortop::regoper::varchar end as sort_operator_name,
       pg_catalog.pg_get_userbyid(P.proowner) as "owner"
       #V94:,
       A.aggfinalextra as final_extra,
       A.aggtransspace as state_size,
       A.aggmtransfn::oid as moving_transition_id,
       case when A.aggmtransfn::oid = 0 then null else A.aggmtransfn::regproc::varchar end as moving_transition_name,
       A.aggminvtransfn::oid as inverse_transition_id,
       case when A.aggminvtransfn::oid = 0 then null else A.aggminvtransfn::regproc::varchar end as inverse_transition_name,
       A.aggmtranstype::oid as moving_state_type,
       A.aggmtransspace as moving_state_size,
       A.aggmfinalfn::oid as moving_final_id,
       case when A.aggmfinalfn::oid = 0 then null else A.aggmfinalfn::regproc::varchar end as moving_final_name,
       A.aggmfinalextra as moving_final_extra,
       A.aggminitval as moving_initial_value,
       A.aggkind as aggregate_kind,
       A.aggnumdirectargs as direct_args
       #.
       #V96:,
       A.aggcombinefn::oid as combine_function_id,
       case when A.aggcombinefn::oid = 0 then null else A.aggcombinefn::regproc::varchar end as combine_function_name,
       A.aggserialfn::oid as serialization_function_id,
       case when A.aggserialfn::oid = 0 then null else A.aggserialfn::regproc::varchar end as serialization_function_name,
       A.aggdeserialfn::oid as deserialization_function_id,
       case when A.aggdeserialfn::oid = 0 then null else A.aggdeserialfn::regproc::varchar end as deserialization_function_name,
       P.proparallel as concurrency_kind
       #.
from pg_catalog.pg_aggregate A
     join pg_catalog.pg_proc P
       on A.aggfnoid = P.oid
where P.pronamespace = :schema_id::oid
  #FRAG> and P.proname in ( :[*f_names] )
  #INC> and (pg_catalog.age(A.xmin) <= #TXAGE or pg_catalog.age(P.xmin) <= #TXAGE)
order by P.oid
;


---- RetrieveExistentExtensions ----
select oid
from pg_catalog.pg_extension
;

---- RetrieveExtensions ----
select E.oid        as id,
       E.xmin       as state_number,
       extname      as name,
       extversion   as version,
       extnamespace as schema_id,
       nspname      as schema_name
       #V100:
       ,
       array(select unnest
             from unnest(available_versions)
             where unnest > extversion) as available_updates
       #.
from pg_catalog.pg_extension E
       join pg_namespace N on E.extnamespace = N.oid
       #V100:
       left join (select name, array_agg(version) as available_versions
                  from pg_available_extension_versions()
                  group by name) V on E.extname = V.name
       #.
#INC> where pg_catalog.age(E.xmin) <= #TXAGE
;

---- RetrieveExtensionMembers ----
select E.oid   as extension_id,
       D.objid as member_id
from pg_extension E
     join pg_depend D on E.oid = D.refobjid and
                         D.refclassid = 'pg_extension'::regclass::oid
where D.deptype = 'e'
order by extension_id
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
       oprcode::varchar as main_name,
       oprrest::oid as restrict_id,
       oprrest::varchar as restrict_name,
       oprjoin::oid as join_id,
       oprjoin::varchar as join_name,
       oprcom::oid as com_id,
       oprcom::regoper::varchar as com_name,
       oprnegate::oid as neg_id,
       oprnegate::regoper::varchar as neg_name,
       oprcanmerge as merges,
       oprcanhash as hashes,
       pg_catalog.pg_get_userbyid(O.oprowner) as "owner"
from pg_catalog.pg_operator O
where oprnamespace = :schema_id::oid
  #FRAG> and oprname in ( :[*f_names] )
  #INC> and pg_catalog.age(xmin) <= #TXAGE
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
from pg_catalog.pg_opclass O
     join pg_catalog.pg_opfamily F on F.oid = opcfamily
where opcnamespace = :schema_id::oid
  #FRAG> and opcname in ( :[*f_names] )
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
       #V91: O.amopsortfamily #: null #. as sort_family_id,
       #V91: SF.opfname #: null #. as sort_family,
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
  #FRAG> and opfname in ( :[*f_names] )
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
       R.ev_enabled as rule_fire_mode,
       R.is_instead as rule_is_instead
from pg_catalog.pg_rewrite R
where R.ev_class in ( select oid
                      from pg_catalog.pg_class
                      where relnamespace = :schema_id::oid
                      #FRAG> and relname in ( :[*f_names] )
                    )
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
       T.tgdeferrable as is_deferrable,
       T.tginitdeferred as is_init_deferred,
       T.tgenabled as trigger_fire_mode,
       T.tgattr as columns,
       T.tgconstraint != 0 as is_constraint,
       #V100: T.tgoldtable #: null #. as old_table_name,
       #V100: T.tgnewtable #: null #. as new_table_name,
       pg_catalog.pg_get_triggerdef(T.oid, true) as source_code
from pg_catalog.pg_trigger T
     join pg_catalog.pg_class TAB on TAB.oid = T.tgrelid and TAB.relnamespace = :schema_id::oid
where true
  #FRAG> and TAB.relname in ( :[*f_names] )
  #INC>  and pg_catalog.age(T.xmin) <= #TXAGE
  and not T.tgisinternal
;


---- RetrieveViewSources ----
select T.relkind as view_kind,
       T.oid as view_id,
       pg_catalog.pg_get_viewdef(T.oid, true) as source_text
from pg_catalog.pg_class T
     join pg_catalog.pg_namespace N on T.relnamespace = N.oid
where N.oid = :schema_id::oid
  and T.relkind in ('m','v')
  #FRAG> and T.relname in ( :[*f_names] )
  #INCSRC> and (pg_catalog.age(T.xmin) <= #SRCTXAGE or exists(
  #INCSRC>    select A.attrelid from pg_catalog.pg_attribute A where A.attrelid = T.oid and pg_catalog.age(A.xmin) <= #SRCTXAGE))
;


---- RetrieveRuleSources ----
with A as ( select oid as table_id,
                   pg_catalog.upper(relkind) as table_kind
            from pg_catalog.pg_class
            where relnamespace = :schema_id::oid
              and relkind in ('r', 'm', 'v', 'f', 'p')
              #FRAG> and relname in ( :[*f_names] )
          )
select table_kind,
       table_id,
       R.oid as rule_id,
       pg_catalog.pg_get_ruledef(R.oid, true) as source_text
from A
     join pg_catalog.pg_rewrite R
       on A.table_id = R.ev_class
where R.rulename != '_RETURN'::name
  #INC> and pg_catalog.age(R.xmin) <= #SRCTXAGE
;


---- RetrieveFunctionSources ----
with system_languages as ( select oid as lang
                           from pg_catalog.pg_language
                           where lanname in ('c','internal') )
select oid as id,
       pg_catalog.pg_get_function_arguments(oid) as arguments_def,
       pg_catalog.pg_get_function_result(oid) as result_def,
       #V140: pg_catalog.pg_get_function_sqlbody(oid) #: null #. as sqlbody_def,
       prosrc as source_text
from pg_catalog.pg_proc
where pronamespace = :schema_id::oid
  #FRAG> and pg_proc.proname in ( :[*f_names] )
  #INC> and pg_catalog.age(xmin) <= #SRCTXAGE
  and not #V110: (prokind = 'a') #: proisagg #.
  and prolang not in (select lang from system_languages)
  and prosrc is not null
;


---- RetrieveExistentAccessMethods ----
select oid from pg_catalog.pg_am
;

---- RetrieveAccessMethods ----
select A.oid as access_method_id,
       A.xmin as state_number,
       A.amname as access_method_name
       #V96:
       ,
       A.amhandler::oid as handler_id,
       pg_catalog.quote_ident(N.nspname) || '.' || pg_catalog.quote_ident(P.proname) as handler_name,
       A.amtype as access_method_type
       #.
from pg_am A
     #V96:
     join pg_proc P on A.amhandler::oid = P.oid
     join pg_namespace N on P.pronamespace = N.oid
     #.
#INC> where pg_catalog.age(A.xmin) <= #TXAGE
;


---- ListExistentCasts ----
select oid
from pg_catalog.pg_cast
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
       C.castcontext,
       C.castmethod
from pg_cast C
     left outer join pg_proc F on C.castfunc::oid = F.oid
     left outer join pg_namespace FN on F.pronamespace = FN.oid
     join pg_type S on C.castsource::oid = S.oid
     join pg_namespace SN on S.typnamespace = SN.oid
     join pg_type T on C.casttarget::oid = T.oid
     join pg_namespace TN on T.typnamespace = TN.oid
#INC> where pg_catalog.age(C.xmin) <= #TXAGE
;

---- RetrieveExistentCollations ----
select oid
from pg_catalog.pg_collation
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
  #FRAG> and collname in ( :[*f_names] )
  #INC> and pg_catalog.age(xmin) <= #TXAGE
;


---- RetrieveExistentForeignDataWrappers ----
select oid
from pg_catalog.pg_foreign_data_wrapper
;


---- RetrieveForeignDataWrappers ----
select fdw.oid as id,
       fdw.xmin as state_number,
       fdw.fdwname as name,
       #V91>pr.proname as handler,
       #V91>nspc.nspname as handler_schema,
       pr2.proname as validator,
       nspc2.nspname as validator_schema,
       fdw.fdwoptions as options,
       pg_catalog.pg_get_userbyid(fdw.fdwowner) as "owner"
from pg_catalog.pg_foreign_data_wrapper fdw
     #V91>left outer join pg_catalog.pg_proc pr on fdw.fdwhandler = pr.oid
     #V91>left outer join pg_catalog.pg_namespace nspc on pr.pronamespace = nspc.oid
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
select oid
from pg_catalog.pg_user_mapping
;


---- RetrieveUserMappingsSuperUser ----
select oid as id,
       umserver as server_id,
       case when umuser = 0 then null else pg_catalog.pg_get_userbyid(umuser) end as user,
       umoptions as options
from pg_catalog.pg_user_mapping
#INC> where pg_catalog.age(xmin) <= #TXAGE
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
select name, is_dst from pg_catalog.pg_timezone_names
union distinct
select abbrev as name, is_dst from pg_catalog.pg_timezone_abbrevs
;    

---- RetrieveDateStyle ----
show DateStyle
;

---- RetrieveExistentSecurityPolicies ----
select P.oid
from pg_catalog.pg_policy P
     join pg_catalog.pg_class C on polrelid = C.oid
where relnamespace = :schema_id::oid
;

---- RetrieveSecurityPolicies ----
select
       P.oid id,
       P.xmin as state_number,
       polname policyname,
       polrelid table_id,
       #V100: polpermissive #: true #. as permissive,
       polroles roles,
       polcmd cmd,
       pg_get_expr(polqual, polrelid) qual,
       pg_get_expr(polwithcheck, polrelid) with_check
from pg_catalog.pg_policy P
       join pg_catalog.pg_class C on polrelid = C.oid
where relnamespace = :schema_id::oid
  #FRAG> and C.relname in ( :[*f_names] )
  #INC> and pg_catalog.age(P.xmin) <= #TXAGE
order by polrelid
;

---- RetrieveDependentTableNames ----
select T.relname
from pg_catalog.pg_class PAR
     join pg_catalog.pg_inherits I on I.inhparent = PAR.oid
     join pg_catalog.pg_class T on T.oid = I.inhrelid
where PAR.relkind in ('r', 'm', 'v', 'p', 'f') and
      PAR.relnamespace = :schema_id::oid and
      T.relkind in ('r', 'm', 'v', 'p', 'f') and
      T.relnamespace = :schema_id::oid and
      PAR.relname in ( :[*f_names] )
;

---- L1_ListAllExistentObjects ----
select T.oid as oid,
       relnamespace as schemaId,
       pg_catalog.translate(relkind, 'rmvpfS', 'rmvrfS') as kind
from pg_catalog.pg_class T
where relnamespace in ( :[*schema_ids] )
  and relkind in ('r', 'm', 'v', 'p', 'f', 'S')
--
union all
-- begin objectType
select T.oid,
       T.typnamespace,
       'T' as kind
from pg_catalog.pg_type T
     left outer join pg_catalog.pg_class C on T.typrelid = C.oid
where T.typnamespace in ( :[*schema_ids] )
  and ( T.typtype in ('d','e') or
        C.relkind = 'c'::"char" or
        (T.typtype = 'b' and (T.typelem = 0 OR T.typcategory <> 'A')) or
        T.typtype = 'p' and not T.typisdefined )
--
union all
-- begin collation
select oid,
       collnamespace,
       'C' as kind
from pg_catalog.pg_collation
where collnamespace in ( :[*schema_ids] )
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
-- begin opClasses
select oid,
       opcnamespace,
       'c' as kind
from pg_catalog.pg_opclass
where opcnamespace in ( :[*schema_ids] )
--
union all
-- begin opFams
select oid,
       opfnamespace,
       'F' as kind
from pg_catalog.pg_opfamily
where opfnamespace in ( :[*schema_ids] )
--
union all
-- begin agg & routine
select oid,
       pronamespace,
       case when #V110: prokind != 'a' #: not proisagg #. then 'R'
            else 'a'
            end as kind
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
  and relkind in ('r', 'm', 'v', 'p', 'f', 'S')
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
  and ( T.typtype in ('d','e') or
        C.relkind = 'c'::"char" or
        (T.typtype = 'b' and (T.typelem = 0 OR T.typcategory <> 'A')) or
        T.typtype = 'p' and not T.typisdefined )
  #INC> and pg_catalog.age(T.xmin) <= #TXAGE
--
union all
-- begin collation
select oid,
       collnamespace,
       'C',
       collname
from pg_catalog.pg_collation
where collnamespace in ( :[*schema_ids] )
  #INC> and pg_catalog.age(xmin) <= #TXAGE
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
-- begin opClasses
select oid,
       opcnamespace,
       'c',
       opcname
from pg_catalog.pg_opclass
where opcnamespace in ( :[*schema_ids] )
  #INC> and pg_catalog.age(xmin) <= #TXAGE
--
union all
-- begin opFams
select oid,
       opfnamespace,
       'F',
       opfname
from pg_catalog.pg_opfamily
where opfnamespace in ( :[*schema_ids] )
  #INC> and pg_catalog.age(xmin) <= #TXAGE
--
union all
-- begin agg & routine
select oid,
       pronamespace,
       case when #V110: prokind != 'a'#: not proisagg#. then 'R'
            else 'a'
            end,
       proname
from pg_catalog.pg_proc
where pronamespace in ( :[*schema_ids] )
  #INC> and pg_catalog.age(xmin) <= #TXAGE
--
order by schemaId
;


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
select pronamespace as schemaId,
       oid as majorOid,
       proargnames as argNames,
       proargmodes as argModes,
       array_length(proargtypes, 1) as nArgs
from pg_catalog.pg_proc
where pronamespace in ( :[*schema_ids] )
  #INC> and pg_catalog.age(xmin) <= #TXAGE
order by schemaId
;