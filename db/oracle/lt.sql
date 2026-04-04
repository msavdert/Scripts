REM     Script:     lt.sql
REM     Purpose:    Display a blocking lock tree hierarchy for current sessions.

col lock_tree format a15

WITH lk
     AS (SELECT blocking_instance || '.' || blocking_session blocker,
                inst_id || '.' || sid                        waiter
           FROM gv$session
          WHERE     blocking_instance IS NOT NULL
                AND blocking_session IS NOT NULL)
    SELECT LPAD ('  ', 2 * (LEVEL - 1)) || waiter lock_tree
      FROM (SELECT * FROM lk
            UNION ALL
            SELECT DISTINCT 'root', blocker
              FROM lk
             WHERE blocker NOT IN (SELECT waiter
                                     FROM lk))
CONNECT BY PRIOR waiter = blocker
START WITH blocker = 'root';