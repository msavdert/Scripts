REM     Script:     rmanest.sql
REM     Purpose:    Show RMAN long operations and estimated completion details.

col OPNAME format a30

SELECT
  opname,
  sofar,
  totalwork,
  ROUND((sofar/totalwork)*100, 2) AS percent_done,
  start_time,
  elapsed_seconds,
  time_remaining
FROM
  v$session_longops
WHERE
  totalwork != 0
  AND sofar != totalwork
ORDER BY 1,4 desc;