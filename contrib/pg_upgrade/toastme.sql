CREATE EXTENSION IF NOT EXISTS pgcrypto;
DROP FUNCTION IF EXISTS randomtext(integer);
CREATE FUNCTION randomtext(len integer) returns text as $$
select string_agg(md5(random()::text),'') from generate_series(1, $1 / 32)
$$ language sql;

DROP FUNCTION IF EXISTS toasted();
CREATE FUNCTION toasted() RETURNS TABLE (
  chunk_id oid,
  chunk_seq integer,
  chunk_data bytea
)
AS $$
  declare
     my_relname varchar;
  begin
    select relname into my_relname from pg_class where oid = (
      select reltoastrelid from pg_class where relname = 'example'
    );

     RETURN QUERY EXECUTE 'select * from pg_toast.' || my_relname;
  end;
$$ LANGUAGE plpgsql;


DROP TABLE IF EXISTS example;
CREATE TABLE example (
  a char(1000000)
);
ALTER table example alter column a  set storage external;

--insert into example select * from randomtext(1000000);
insert into example select * from randomtext(1000000);

select count(*) from toasted();

