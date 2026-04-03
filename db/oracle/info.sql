col instance_name for a15
col dbid for 9999999999
col db_unique_name for a15
col host_name for a25
col version for a15
col startup_time for a20
col log_mode for a15
col open_mode for a20
col database_role for a16
col dataguard for a9
col rac for a3
col platform_name for a30
col flashback_on for a15
col logins_on for a15

select
  instance_name,
  dbid, name,
  db_unique_name,
  host_name, version,
  to_char(startup_time, 'YYYY-MM-DD HH24:MI:SS') startup_time,
  log_mode,
  open_mode,
  database_role,
  CASE WHEN (select count(*) from v$archive_dest where status = 'VALID' and target = 'STANDBY') > 0 THEN 'YES' ELSE 'NO' END dataguard,
  CASE WHEN (select value from v$parameter where name = 'cluster_database') = 'FALSE' THEN 'NO' ELSE 'YES' END rac,
  platform_name,
  flashback_on,
  logins
 from v$database, v$instance;