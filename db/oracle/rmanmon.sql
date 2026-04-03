TTITLE LEFT '% Completed. Aggregate is the overall progress:'
SET LINE 132
SELECT opname, round(sofar/totalwork*100) "% Complete"
  FROM gv$session_longops
 WHERE opname LIKE 'RMAN%'
   AND totalwork != 0
   AND sofar <> totalwork
 ORDER BY 1,2 desc
/
 
TTITLE LEFT 'Channels waiting:'
COL client_info FORMAT A15 TRUNC
COL event FORMAT A20 TRUNC
COL state FORMAT A30
COL wait FORMAT 999.90 HEAD "Min waiting"
SELECT s.sid, p.spid, s.client_info, status, event, state, seconds_in_wait/60 wait
  FROM gv$process p, gv$session s
 WHERE p.addr = s.paddr
   AND client_info LIKE 'rman%'
/
   
TTITLE LEFT 'Files currently being written to:'
COL filename FORMAT a60
SELECT filename, bytes, io_count
  FROM v$backup_async_io
 WHERE status='IN PROGRESS'
/

TTITLE OFF
SET HEAD OFF
SELECT 'Throughput: '||
       ROUND(SUM(v.value/1024/1024),1) || ' Meg so far @ ' ||
       ROUND(SUM(v.value/1024/1024)/NVL((SELECT MIN(elapsed_seconds)
            FROM v$session_longops
            WHERE opname LIKE 'RMAN: aggregate input'
              AND sofar != TOTALWORK
              AND elapsed_seconds IS NOT NULL
       ),SUM(v.value/1024/1024)),2) || ' Meg/sec' AS Output
 FROM gv$sesstat v, v$statname n, gv$session s
WHERE v.statistic# = n.statistic#
  AND n.name       = 'physical write total bytes'
  AND v.sid        = s.sid
  AND v.inst_id    = s.inst_id
  AND s.program LIKE 'rman@%'
GROUP BY n.name
/
SET HEAD ON