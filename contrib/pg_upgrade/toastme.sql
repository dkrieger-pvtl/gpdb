CREATE EXTENSION IF NOT EXISTS pgcrypto;
DROP FUNCTION IF EXISTS randomtext(integer);
CREATE FUNCTION randomtext(len integer) returns text as $$
select string_agg(md5(random()::text),'') from generate_series(1, $1 / 32)
$$ language sql;

DROP FUNCTION IF EXISTS toasted();
CREATE FUNCTION toasted() RETURNS TABLE (
  seq_id integer,
  toastcnt bigint
)
AS $$
  declare
     my_relname varchar;
     my_toast varchar;
     my_endq varchar;
     my_ns varchar;
  begin
    select relname into my_relname from pg_class where oid = (
      select reltoastrelid from pg_class where relname = 'example'
    );

    select concat('pg_toast','') into my_ns;
     RETURN QUERY EXECUTE  'select gp_segment_id,count(*) from gp_dist_random(''' || quote_ident(my_ns) || '.' || quote_ident(my_relname) || ''') GROUP BY gp_segment_id;';
  end;
$$ LANGUAGE plpgsql;


DROP TABLE IF EXISTS example;
CREATE TABLE example (
  a char(1000000)
);
ALTER table example alter column a  set storage external;

--insert into example select * from randomtext(1000000);
--insert into example select * from randomtext(1000000);

select count(*) from example;
select * from toasted();




