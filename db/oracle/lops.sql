col "User Session" for a20
col username for a20
col osuser for a20
col opname for a34
col target for a32
col message for a79
col target for a18
col start_time for a21
col elapsed for a7
col remain for a7
col "% Completed" for a12

SELECT
    s.inst_id || ':' || s.sid || ',' || s.serial# AS "User Session",
    s.username,
    osuser,
    sl.sql_id,
    opname,
    sl.message,
    target,
    to_char(start_time,'YYYY/MM/DD HH24:MI:SS') start_time,
    CASE WHEN elapsed_seconds < 60 THEN to_char(round(elapsed_seconds, 1)) || ' s' ELSE to_char(round(elapsed_seconds / 60, 1)) || ' m' END AS elapsed,
    CASE WHEN time_remaining < 60 THEN to_char(round(time_remaining, 1)) || ' s' ELSE to_char(round(time_remaining / 60, 1)) || ' m' END AS remain,
    round((elapsed_seconds /(elapsed_seconds + time_remaining) * 100), 2)
    || '%'   AS "% Completed"
FROM
         gv$session_longops sl
    INNER JOIN gv$session s ON sl.sid = s.sid
                               AND sl.serial# = s.serial#
                               AND sl.inst_id = s.inst_id
WHERE time_remaining > 0
ORDER BY "% Completed" DESC;