select
  s1.sid||','||s1.serial#||'@'||s1.inst_id as "SESSIONS",
  s1.username,
  s1.sql_id,
  (SELECT substr(regexp_replace(sql_text, '( [[:space:]]+)|([[:cntrl:]])',' '),1,30) FROM gv$sqlarea WHERE sql_id=s1.sql_id and rownum=1) sql_text,
  s1.prev_sql_id,
  (SELECT substr(regexp_replace(sql_text, '( [[:space:]]+)|([[:cntrl:]])',' '),1,30) FROM gv$sqlarea WHERE sql_id=s1.prev_sql_id and rownum=1) prev_sql_text,
  s1.program,
  s1.machine,
  s1.wait_class,
  s1.event,
  s2.sid||','||s2.serial#||'@'||s2.inst_id as "BLKD_SESSION",
  s2.serial# blkd_serial,
  s2.username blkd_username,
  s2.sql_id blkd_sql_id,
  (SELECT substr(regexp_replace(sql_text, '( [[:space:]]+)|([[:cntrl:]])',' '),1,30) FROM gv$sqlarea WHERE sql_id=s2.sql_id and rownum=1) blkd_sql_text,
  s2.program blkd_program,
  s2.machine blkd_machine,
  s2.wait_class blkd_wait_class,
  s2.event blkd_event,
  s2.seconds_in_wait wait_secs,
  'ALTER SYSTEM KILL SESSION '''
  ||s1.sid
  ||','
  ||s1.serial#
  ||',@'
  ||s1.inst_id
  || ''' IMMEDIATE;' Kill_Script 
from gv$lock l1, gv$session s1, gv$lock l2, gv$session s2
where s1.sid=l1.sid and s2.sid=l2.sid
and l1.BLOCK=1 and l2.request > 0
and l1.id1 = l2.id1
and l2.id2 = l2.id2
AND s1.CON_ID = (CASE WHEN (SELECT count(*) FROM V$CONTAINERS) > 1 THEN 1 ELSE (SELECT s1.CON_ID FROM V$CONTAINERS) END)
ORDER BY s2.seconds_in_wait DESC;
