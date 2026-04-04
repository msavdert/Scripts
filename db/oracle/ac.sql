REM     Script:     ac.sql
REM     Purpose:    List active foreground sessions with wait details and
REM                 generate RAC-aware kill commands.

col "User Session" for a12
col username for a15
col osuser for a17
col machine for a31
col program for a45
col module for a30
col sql_id for a15
col prev_sql_id for a15
col sql_exec_id for 9999999999
col SQL_HASH_VALUE for 9999999999
col event for a40
col wait_class for a15
col last_call_et for a15
col Kill_Script for a54

SELECT
    inst_id || ':' || sid || ',' || serial# AS "User Session",
    username,
    osuser,
    machine,
    program,
--    module,
    sql_id,
--    prev_sql_id,
--    sql_exec_id,
--    sql_hash_value,
    event,
    wait_class,
    floor(last_call_et / 86400) || 'd ' || to_char(TO_DATE(mod(last_call_et, 86400), 'sssss'), 'hh24"h" mi"m" ss"s"') last_call_et,
    'ALTER SYSTEM KILL SESSION ''' || sid || ',' || serial# || ',@' || inst_id || ''' IMMEDIATE;' kill_script
FROM gv$session
WHERE type NOT LIKE 'BACKGROUND'
  AND wait_class != 'Idle'
  AND status LIKE 'ACTIVE'
  AND sid NOT IN (SELECT DISTINCT sid FROM gv$mystat WHERE  ROWNUM < 2)
ORDER BY
    username, osuser;
