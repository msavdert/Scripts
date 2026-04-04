REM     Script:     tsh.sql
REM     Purpose:    Show historical tablespace size and usage for a specified
REM                 tablespace name.

define tablespace_name = '&1'
define day = '&2'

select
  to_char(s.begin_interval_time, 'YYYY-MM-DD HH24:MI:SS') as snapshot_time,
  t.name as tablespace_name,
  trim(to_char(h.tablespace_size * p.value / 1024 / 1024, '999,999,999,999')) as size_mb,
  trim(to_char(h.tablespace_maxsize * p.value / 1024 / 1024, '999,999,999,999')) as maxsize_mb,
  trim(to_char(h.tablespace_usedsize * p.value / 1024 / 1024, '999,999,999,999')) as usedsize_mb,
  trim(to_char((h.tablespace_size - h.tablespace_usedsize) * p.value / 1024 / 1024, '999,999,999,999')) as free_size_mb,
  trim(to_char((h.tablespace_maxsize - h.tablespace_usedsize) * p.value / 1024 / 1024, '999,999,999,999')) as max_free_size_mb,
  trim(to_char(case when h.tablespace_size > 0 then (h.tablespace_usedsize * 100) / h.tablespace_size else 0 end, '999.99')) || '%' as usage_percent
from
  dba_hist_tbspc_space_usage h
join
  dba_hist_snapshot s on h.snap_id = s.snap_id and h.dbid = s.dbid
join
  v$tablespace t on h.tablespace_id = t.ts#
cross join
  v$parameter p
where
  upper(t.name) = upper('&&tablespace_name')
  and p.name = 'db_block_size'
   and s.begin_interval_time >= sysdate - &&day
order by
  s.begin_interval_time desc;

undefine tablespace_name
undefine day