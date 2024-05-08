SELECT current_database(),
       schemaname,
       relname, 
       last_vacuum, 
       last_autovacuum, 
       last_analyze, 
       last_autoanalyze 
FROM   pg_stat_all_tables 
WHERE  schemaname = 'public' 
ORDER  BY last_vacuum DESC;
