REM     Script:     ash_activity_timeline.sql
REM     Purpose:    Display recent ASH activity as a text-based timeline.
REM                 '+' = ON CPU, '=' = User I/O, '-' = other waits.
REM     Notes:      Requires access to V$ACTIVE_SESSION_HISTORY.
REM                 Use only where Oracle Diagnostic Pack licensing permits.

SET PAGESIZE 1000
SET LINESIZE 220
SET VERIFY OFF

PROMPT Press Enter to accept the defaults.
PROMPT Use ALL for instance_number, con_id, and sql_id to disable filtering.
ACCEPT analysis_minutes NUMBER DEFAULT 60 PROMPT 'analysis_minutes [60]: '
ACCEPT bucket_seconds NUMBER DEFAULT 60 PROMPT 'bucket_seconds [60]: '
ACCEPT graph_width NUMBER DEFAULT 50 PROMPT 'graph_width [50]: '
ACCEPT instance_number CHAR DEFAULT 'ALL' PROMPT 'instance_number [ALL]: '
ACCEPT con_id CHAR DEFAULT 'ALL' PROMPT 'con_id [ALL]: '
ACCEPT sql_id CHAR DEFAULT 'ALL' PROMPT 'sql_id [ALL]: '

COLUMN sample_time         FORMAT A20
COLUMN active_sessions     FORMAT 9999990
COLUMN cpu_samples         FORMAT 9999990
COLUMN user_io_samples     FORMAT 9999990
COLUMN other_wait_samples  FORMAT 9999990
COLUMN visualized_activity FORMAT A&&graph_width

VAR ash_activity_timeline_rc REFCURSOR

DECLARE
  l_sql            CLOB;
  l_has_con_id     NUMBER := 0;
BEGIN
  BEGIN
    EXECUTE IMMEDIATE 'SELECT con_id FROM gv$active_session_history WHERE ROWNUM = 1';
    l_has_con_id := 1;
  EXCEPTION
    WHEN OTHERS THEN
      IF SQLCODE = -904 THEN
        l_has_con_id := 0;
      ELSE
        RAISE;
      END IF;
  END;

  l_sql := q'[
WITH ash_window AS (
  SELECT TRUNC(CAST(sample_time AS DATE), 'DD')
         + FLOOR(TO_NUMBER(TO_CHAR(sample_time, 'SSSSS')) / ]' || &&bucket_seconds || q'[) * ]' || &&bucket_seconds || q'[ / 86400 AS bucket_time,
         session_state,
         wait_class
    FROM gv$active_session_history
   WHERE sample_time >= SYSTIMESTAMP - NUMTODSINTERVAL(]' || &&analysis_minutes || q'[, 'MINUTE')
     AND (:instance_number = 'ALL' OR TO_CHAR(inst_id) = :instance_number)
]';

  IF l_has_con_id = 1 THEN
    l_sql := l_sql || q'[
     AND (:con_id = 'ALL' OR TO_CHAR(con_id) = :con_id)
]';
  END IF;

  l_sql := l_sql || q'[
     AND (:sql_id = 'ALL' OR LOWER(sql_id) = LOWER(:sql_id))
),
ash_agg AS (
  SELECT bucket_time,
         COUNT(*) AS active_sessions,
         SUM(CASE WHEN session_state = 'ON CPU' THEN 1 ELSE 0 END) AS cpu_samples,
         SUM(CASE WHEN wait_class = 'User I/O' THEN 1 ELSE 0 END) AS user_io_samples,
         SUM(CASE WHEN session_state <> 'ON CPU' AND NVL(wait_class, 'CPU') <> 'User I/O' THEN 1 ELSE 0 END) AS other_wait_samples
    FROM ash_window
   GROUP BY bucket_time
),
ash_scaled AS (
  SELECT bucket_time,
         active_sessions,
         cpu_samples,
         user_io_samples,
         other_wait_samples,
         GREATEST(MAX(active_sessions) OVER (), 1) AS peak_active_sessions,
         FLOOR(cpu_samples * ]' || &&graph_width || q'[ / GREATEST(MAX(active_sessions) OVER (), 1)) AS cpu_len,
         FLOOR(user_io_samples * ]' || &&graph_width || q'[ / GREATEST(MAX(active_sessions) OVER (), 1)) AS user_io_len
    FROM ash_agg
),
ash_output AS (
  SELECT bucket_time,
         TO_CHAR(bucket_time, 'DD-MON HH24:MI:SS') AS sample_time,
         active_sessions,
         cpu_samples,
         user_io_samples,
         other_wait_samples,
         SUBSTR(
           RPAD('+', cpu_len, '+')
           || RPAD('=', user_io_len, '=')
           || RPAD(
                '-',
                GREATEST(
                  LEAST(
                    ]' || &&graph_width || q'[ - cpu_len - user_io_len,
                    FLOOR(other_wait_samples * ]' || &&graph_width || q'[ / peak_active_sessions)
                  ),
                  0
                ),
                '-'
              )
           || RPAD(' ', ]' || &&graph_width || q'[, ' '),
           1,
           ]' || &&graph_width || q'[
         ) AS visualized_activity
    FROM ash_scaled
)
SELECT sample_time,
       active_sessions,
       cpu_samples,
       user_io_samples,
       other_wait_samples,
       visualized_activity
  FROM ash_output
UNION ALL
SELECT TO_CHAR(SYSTIMESTAMP, 'DD-MON HH24:MI:SS') AS sample_time,
       0 AS active_sessions,
       0 AS cpu_samples,
       0 AS user_io_samples,
       0 AS other_wait_samples,
       'No ASH samples matched the current filters/window' AS visualized_activity
  FROM dual
 WHERE NOT EXISTS (
       SELECT 1
         FROM ash_output
       )
 ORDER BY 1
]';

  IF l_has_con_id = 1 THEN
    OPEN :ash_activity_timeline_rc FOR l_sql
      USING '&&instance_number', '&&instance_number', '&&con_id', '&&con_id', '&&sql_id', '&&sql_id';
  ELSE
    IF UPPER('&&con_id') <> 'ALL' THEN
      DBMS_OUTPUT.PUT_LINE('Warning: con_id filter ignored because GV$ACTIVE_SESSION_HISTORY has no CON_ID column on this database version.');
    END IF;

    OPEN :ash_activity_timeline_rc FOR l_sql
      USING '&&instance_number', '&&instance_number', '&&sql_id', '&&sql_id';
  END IF;
END;
/

PRINT ash_activity_timeline_rc

PROMPT
PROMPT Parameters:
PROMPT   analysis_minutes = &&analysis_minutes
PROMPT   bucket_seconds   = &&bucket_seconds
PROMPT   graph_width      = &&graph_width
PROMPT   instance_number  = &&instance_number
PROMPT   con_id           = &&con_id
PROMPT   sql_id           = &&sql_id
PROMPT
PROMPT Interpretation:
PROMPT   active_sessions shows ASH sample count in each bucket.
PROMPT   cpu_samples approximates sampled seconds on CPU.
PROMPT   user_io_samples and other_wait_samples are sampled wait counts.
PROMPT   If no rows match, widen analysis_minutes or relax instance/con_id/sql_id filters.
