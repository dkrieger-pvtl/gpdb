create schema bfv_aggregate;
set search_path=bfv_aggregate;

---
--- Window function with outer references in PARTITION BY/ORDER BY clause
---

-- SETUP
-- start_ignore
DROP TABLE IF EXISTS x_outer;
DROP TABLE IF EXISTS y_inner;
-- end_ignore
create table x_outer (a int, b int, c int);
create table y_inner (d int, e int);
insert into x_outer select i%3, i, i from generate_series(1,10) i;
insert into y_inner select i%3, i from generate_series(1,10) i;
analyze x_outer;
analyze y_inner;

-- TEST
select * from x_outer where a in (select row_number() over(partition by a) from y_inner) order by 1, 2;

select * from x_outer where a in (select rank() over(order by a) from y_inner) order by 1, 2;

select * from x_outer where a not in (select rank() over(order by a) from y_inner) order by 1, 2;

select * from x_outer where exists (select rank() over(order by a) from y_inner where d = a) order by 1, 2;

select * from x_outer where not exists (select rank() over(order by a) from y_inner where d = a) order by 1, 2;

select * from x_outer where a in (select last_value(d) over(partition by b order by e rows between e preceding and e+1 following) from y_inner) order by 1, 2;

-- CLEANUP
-- start_ignore
DROP TABLE IF EXISTS x_outer;
DROP TABLE IF EXISTS y_inner;
-- end_ignore

---
--- Testing aggregation in a query
---

-- SETUP
create table d (col1 timestamp, col2 int);
insert into d select to_date('2014-01-01', 'YYYY-DD-MM'), generate_series(1,100);

-- TEST
select 1, to_char(col1, 'YYYY'), median(col2) from d group by 1, 2;

-- CLEANUP
-- start_ignore
DROP TABLE IF EXISTS d;
-- end_ignore

---
--- Testing if aggregate derived window function produces incorrect results
---

-- SETUP
-- start_ignore
drop table if exists toy;
drop aggregate mysum1(int4);
drop aggregate mysum2(int4);
-- end_ignore
create table toy(id,val) as select i,i from generate_series(1,5) i;
create aggregate mysum1(int4) (sfunc = int4_sum, prefunc=int8pl, stype=bigint);
create aggregate mysum2(int4) (sfunc = int4_sum, stype=bigint);

-- TEST
select
   id, val,
   sum(val) over (w),
   mysum1(val) over (w),
   mysum2(val) over (w)
from toy
window w as (order by id rows 2 preceding);

-- CLEANUP
-- start_ignore
drop table if exists toy;
drop aggregate mysum1(int4);
drop aggregate mysum2(int4);
-- end_ignore

---
--- Error executing for aggregate with anyarry as return type
---

-- SETUP
CREATE OR REPLACE FUNCTION tfp(anyarray,anyelement) RETURNS anyarray AS
'select $1 || $2' LANGUAGE SQL;

CREATE OR REPLACE FUNCTION ffp(anyarray) RETURNS anyarray AS
'select $1' LANGUAGE SQL;

CREATE AGGREGATE myaggp20a(BASETYPE = anyelement, SFUNC = tfp,
  STYPE = anyarray, FINALFUNC = ffp, INITCOND = '{}');

-- Adding a sql function to sory the array
CREATE OR REPLACE FUNCTION array_sort (ANYARRAY)
RETURNS ANYARRAY LANGUAGE SQL
AS $$
SELECT ARRAY(SELECT unnest($1) ORDER BY 1)
$$;

create temp table t(f1 int, f2 int[], f3 text);

-- TEST
insert into t values(1,array[1],'a');
insert into t values(1,array[11],'b');
insert into t values(1,array[111],'c');
insert into t values(2,array[2],'a');
insert into t values(2,array[22],'b');
insert into t values(2,array[222],'c');
insert into t values(3,array[3],'a');
insert into t values(3,array[3],'b');

select f3, array_sort(myaggp20a(f1)) from t group by f3 order by f3;

-- CLEANUP
-- start_ignore
drop table if exists t;
drop function array_sort (ANYARRAY) cascade;
drop function tfp(anyarray,anyelement) cascade;
drop function ffp(anyarray) cascade;
-- end_ignore

-- start_ignore
-- start_ignore
create language plpythonu;
-- end_ignore
create or replace function count_operator(explain_query text, operator text) returns int as
$$
rv = plpy.execute(explain_query)
search_text = operator
result = 0
for i in range(len(rv)):
    cur_line = rv[i]['QUERY PLAN']
    if search_text.lower() in cur_line.lower():
        result = result+1
return result
$$
language plpythonu;

---
--- Testing adding a traceflag to favor multi-stage aggregation
---

-- SETUP
-- start_ignore
DROP TABLE IF EXISTS multi_stage_test;
-- end_ignore
create table multi_stage_test(a int, b int);
insert into multi_stage_test select i, i%4 from generate_series(1,10) i;
analyze multi_stage_test;

-- TEST
-- start_ignore
set optimizer_segments=2;
set optimizer_prefer_multistage_agg = on;
-- end_ignore
select count_operator('explain select count(*) from multi_stage_test group by b;','GroupAggregate');
-- start_ignore
set optimizer_prefer_multistage_agg = off;
-- end_ignore
select count_operator('explain select count(*) from multi_stage_test group by b;','GroupAggregate');

--CLEANUP
-- start_ignore
DROP TABLE IF EXISTS multi_stage_test;
reset optimizer_segments;
set optimizer_prefer_multistage_agg = off;
-- end_ignore

---
--- Testing not picking HashAgg for aggregates without preliminary functions
---

-- SETUP
-- start_ignore
SET optimizer_disable_missing_stats_collection=on;
DROP TABLE IF EXISTS attribute_table;
-- end_ignore
CREATE TABLE attribute_table (product_id integer, attribute_id integer,attribute text, attribute2 text,attribute_ref_lists text,short_name text,attribute6 text,attribute5 text,measure double precision,unit character varying(60)) DISTRIBUTED BY (product_id ,attribute_id);
-- create the transition function
CREATE OR REPLACE FUNCTION do_concat(text,text)
RETURNS text
--concatenates 2 strings
AS 'SELECT CASE WHEN $1 IS NULL THEN $2
WHEN $2 IS NULL THEN $1
ELSE $1 || $2 END;'
     LANGUAGE SQL
     IMMUTABLE
     RETURNS NULL ON NULL INPUT;
-- UDA definition. No PREFUNC exists
-- start_ignore
DROP AGGREGATE IF EXISTS concat(text);
-- end_ignore
CREATE AGGREGATE concat(text) (
   --text/string concatenation
   SFUNC = do_concat, --Function to call for each string that builds the aggregate
   STYPE = text,--FINALFUNC=final_func, --Function to call after everything has been aggregated
   INITCOND = '' --Initialize as an empty string when starting
);

-- TEST
-- cook some stats
-- start_ignore
set allow_system_table_mods='DML';
-- end_ignore
UPDATE pg_class set reltuples=524592::real, relpages=2708::integer where oid = 'attribute_table'::regclass;
select count_operator('explain select product_id,concat(E''#attribute_''||attribute_id::varchar||E'':''||attribute) as attr FROM attribute_table GROUP BY product_id;','HashAggregate');

-- CLEANUP
-- start_ignore
DROP TABLE IF EXISTS attribute_table;
DROP AGGREGATE IF EXISTS concat(text);
drop function do_concat(text,text) cascade;
SET optimizer_disable_missing_stats_collection=off;
-- end_ignore


---
--- Testing fallback to planner when the agg used in window does not have either prelim or inverse prelim function.
---

-- SETUP
-- start_ignore
DROP TABLE IF EXISTS foo;
-- end_ignore
create table foo(a int, b text) distributed by (a);

-- TEST
insert into foo values (1,'aaa'), (2,'bbb'), (3,'ccc');
-- should fall back
select string_agg(b) over (partition by a) from foo order by 1;
select string_agg(b) over (partition by a,b) from foo order by 1;
-- should not fall back
select max(b) over (partition by a) from foo order by 1;
select count_operator('explain select max(b) over (partition by a) from foo order by 1;', 'Table Scan');
-- fall back
select string_agg(b) over (partition by a+1) from foo order by 1;
select string_agg(b || 'txt') over (partition by a) from foo order by 1;
select string_agg(b || 'txt') over (partition by a+1) from foo order by 1;
-- fall back and planner's plan produces unsupported execution
select string_agg(b) over (partition by a order by a) from foo order by 1;
select string_agg(b || 'txt') over (partition by a,b order by a,b) from foo order by 1;
select '1' || string_agg(b) over (partition by a+1 order by a+1) from foo;

-- CLEANUP
-- start_ignore
drop function count_operator(text,text);
DROP TABLE IF EXISTS foo;
drop function if exists count_operator(explain_query text, operator text);
drop schema if exists bfv_aggregate;
-- end_ignore
