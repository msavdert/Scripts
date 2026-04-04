REM     Script:     killu.sql
REM     Purpose:    Generate kill commands for sessions whose username matches a
REM                 provided pattern.

col Kill_Script format a60;

SELECT username,
  sid,
  serial#,
  inst_id,
  'ALTER SYSTEM KILL SESSION '''
  ||sid
  ||','
  ||serial#
  ||',@'
  ||inst_id
  || ''' IMMEDIATE;' Kill_Script
FROM gv$session
WHERE username LIKE UPPER('%&1%');