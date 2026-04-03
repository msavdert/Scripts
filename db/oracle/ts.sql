col pdb format a10
col contents format a10
col tablespace_name format a25
col "total_bytes" format a20
col "used_bytes" format a20
col "free_bytes" format a20
--col "used_pct" format 999


SELECT
  CASE WHEN (select cdb from v$database) = 'NO' then null else p.name END as pdb,
  m.tablespace_name tablespace_name,
  contents,
  trim(to_char(max(m.tablespace_size*t.block_size)/1024/1024, '999,999,999,999')) as total_bytes,
  trim(to_char(max(m.used_space*t.block_size)/1024/1024, '999,999,999,999')) as used_bytes,
  trim(to_char(max((m.tablespace_size-m.used_space)*t.block_size)/1024/1024, '999,999,999,999')) as free_bytes,
  round(max(m.used_percent),1) as used_pct
FROM cdb_tablespace_usage_metrics m, cdb_tablespaces t, v$containers p
WHERE m.tablespace_name=t.tablespace_name
  AND p.con_id = m.con_id
GROUP BY m.tablespace_name ,p.name, t.contents
ORDER BY used_pct DESC;