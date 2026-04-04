REM     Script:     killidle.sql
REM     Purpose:    List inactive user sessions older than N minutes and
REM                 generate ALTER SYSTEM KILL SESSION commands.
REM     Default:    60 minutes

SET VERIFY OFF
SET LINESIZE 220
SET PAGESIZE 1000

ACCEPT inactive_minutes NUMBER DEFAULT 60 PROMPT 'inactive_minutes [60]: '

COLUMN username FORMAT A20
COLUMN machine FORMAT A35
COLUMN status FORMAT A10
COLUMN last_call_min FORMAT 9999990
COLUMN kill_cmd FORMAT A60

PROMPT
PROMPT Inactive sessions older than &&inactive_minutes minute(s)

SELECT s.sid,
       s.serial#,
       s.inst_id,
       s.username,
       s.machine,
       s.status,
       ROUND(s.last_call_et / 60) AS last_call_min
  FROM gv$session s
 WHERE s.type <> 'BACKGROUND'
   AND s.username IS NOT NULL
   AND s.last_call_et > (&&inactive_minutes * 60)
   AND s.status = 'INACTIVE'
 ORDER BY s.last_call_et DESC, s.inst_id, s.sid;

PROMPT
PROMPT Kill commands

SELECT 'ALTER SYSTEM KILL SESSION '''
       || s.sid
       || ','
       || s.serial#
       || ',@'
       || s.inst_id
       || ''' IMMEDIATE;' AS kill_cmd
  FROM gv$session s
 WHERE s.type <> 'BACKGROUND'
   AND s.username IS NOT NULL
   AND s.last_call_et > (&&inactive_minutes * 60)
   AND s.status = 'INACTIVE'
 ORDER BY s.last_call_et DESC, s.inst_id, s.sid;

UNDEFINE inactive_minutes