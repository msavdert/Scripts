REM     Script:     wcbytwt.sql
REM     Purpose:    Report wait class activity between snapshots and highlight
REM                 top wait categories.

set linesize 200
set veri off
col Waits format 999,999,999,999
col 'Event Class' format a20
DEFINE beg_snap = 1120;
DEFINE end_snap = 1121;
WITH cputime_and_dbtime AS (
  SELECT
    (SELECT SUM(e.VALUE - b.value) AS diff_value
       FROM dba_hist_sys_time_model b,
            dba_hist_sys_time_model e
      WHERE e.dbid = b.dbid
        AND e.instance_number = b.instance_number
        AND e.STAT_ID = b.STAT_ID
        AND b.dbid = (SELECT dbid FROM v$database)
        AND b.instance_number = (SELECT instance_number FROM v$instance)
        AND b.snap_id = &beg_snap
        AND e.snap_id = &end_snap
        AND e.stat_name = 'DB CPU') AS cputime,
    (SELECT SUM(e.VALUE - b.value) AS diff_value
       FROM dba_hist_sys_time_model b,
            dba_hist_sys_time_model e
      WHERE e.dbid = b.dbid
        AND e.instance_number = b.instance_number
        AND e.STAT_ID = b.STAT_ID
        AND b.dbid = (SELECT dbid FROM v$database)
        AND b.instance_number = (SELECT instance_number FROM v$instance)
        AND b.snap_id = &beg_snap
        AND e.snap_id = &end_snap
        AND e.stat_name = 'DB time') AS dbtime,
    (SELECT
        EXTRACT(DAY FROM e.end_interval_time - b.end_interval_time) * 86400
        + EXTRACT(HOUR FROM e.end_interval_time - b.end_interval_time) * 3600
        + EXTRACT(MINUTE FROM e.end_interval_time - b.end_interval_time) * 60
        + EXTRACT(SECOND FROM e.end_interval_time - b.end_interval_time) AS d_elp_time
    FROM dba_hist_snapshot b, dba_hist_snapshot e
    WHERE e.snap_id = &end_snap
      AND b.snap_id = &beg_snap
      AND b.dbid = (SELECT dbid FROM v$database)
      AND b.instance_number = (SELECT instance_number FROM v$instance)
      AND e.dbid = b.dbid
      AND e.instance_number = b.instance_number) as elp_time
  FROM dual
)
SELECT WAIT_CLASS AS "Event Class",
       TOTAL_WAITS AS "Waits",
       ROUND(wait_time_seconds, 2) AS "Total Wait Time (sec)",
       ROUND(avg_wait_ms, 2) AS "Avg Wait (ms)",
       ROUND(pct_db_time, 2) AS "% DB Time",
       ROUND(avg_active_sess, 2) AS "Avg Active Sessions"
  FROM (
    SELECT WAIT_CLASS,
           TOTAL_WAITS,
           wait_time_microseconds / 1000000 AS wait_time_seconds,
           DECODE(total_waits, 0, NULL, wait_time_microseconds / total_waits) / 1000 AS avg_wait_ms,
           DECODE((SELECT dbtime FROM cputime_and_dbtime), 0, NULL, wait_time_microseconds / (SELECT dbtime FROM cputime_and_dbtime)) * 100 AS pct_db_time,
           wait_time_microseconds  / 1000000 / (SELECT elp_time FROM cputime_and_dbtime) as avg_active_sess
      FROM (
        SELECT wait_class,
                 total_waits - NVL(prev_total_waits, 0) total_waits,
                 time_waited_micro - NVL(prev_time_waited_micro, 0) wait_time_microseconds
          FROM (
            SELECT e.WAIT_CLASS wait_class,
                   sum(b.total_waits) prev_total_waits,
                   sum(b.time_waited_micro) AS prev_time_waited_micro,
                   sum(e.total_waits) total_waits,
                   sum(e.time_waited_micro) time_waited_micro
              FROM dba_hist_system_event b,
                   dba_hist_system_event e
             WHERE b.snap_id = &beg_snap
               AND e.dbid= (SELECT dbid FROM v$database)
               AND e.snap_id = &end_snap
               AND e.instance_number = (SELECT instance_number FROM v$instance)
               AND e.dbid = b.dbid(+)
               AND e.instance_number = b.instance_number(+)
               AND e.event_id = b.event_id(+)
               AND e.total_waits > NVL(b.total_waits, 0)
               AND e.time_waited_micro > NVL(b.time_waited_micro, 0)
               AND e.wait_class <> 'Idle'
            group by e.wait_class
            UNION ALL
            SELECT 'DB CPU' AS wait_class,
                   NULL AS prev_total_waits,
                   NULL AS prev_time_waited_micro,
                   NULL AS total_waits,
                   (SELECT cputime FROM cputime_and_dbtime) AS time_waited_micro
              FROM dual
             WHERE (SELECT cputime FROM cputime_and_dbtime) > 0
          )
         ORDER BY wait_time_microseconds DESC, total_waits DESC
      )
  );