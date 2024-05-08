--Find the count of objects for each Database Schema
-- https://www.dbrnd.com/2017/06/postgresql-script-to-find-the-count-of-objects-for-each-database-schema/

SELECT
	n.nspname as schema_name
	,CASE c.relkind
	   WHEN 'r' THEN 'table'
	   WHEN 'v' THEN 'view'
	   WHEN 'i' THEN 'index'
	   WHEN 'S' THEN 'sequence'
	   WHEN 's' THEN 'special'
	END as object_type
	,count(1) as object_count
FROM pg_catalog.pg_class c
LEFT JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace
WHERE c.relkind IN ('r','v','i','S','s')
GROUP BY  n.nspname,
	CASE c.relkind
	   WHEN 'r' THEN 'table'
	   WHEN 'v' THEN 'view'
	   WHEN 'i' THEN 'index'
	   WHEN 'S' THEN 'sequence'
	   WHEN 's' THEN 'special'
	END
ORDER BY n.nspname,
	CASE c.relkind
	   WHEN 'r' THEN 'table'
	   WHEN 'v' THEN 'view'
	   WHEN 'i' THEN 'index'
	   WHEN 'S' THEN 'sequence'
	   WHEN 's' THEN 'special'
	END;
