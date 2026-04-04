REM     Script:     killsql.sql
REM     Purpose:    Generate disconnect commands for sessions currently running a
REM                 specified SQL_ID.

col username for a25
col kill_sql_id for a80

PROMPT 1.SQL_ID

SELECT 'alter system disconnect session '''
       || s.sid
       || ','
       || s.serial#
       || ',@'
       || s.inst_id
       || ''' immediate;'
       AS kill_sql_id
    FROM gv$session s, gv$session_wait sw
   WHERE s.inst_id = sw.inst_id AND s.sid = sw.sid AND s.sql_id = '&1'
ORDER BY username;

UNDEFINE 1
