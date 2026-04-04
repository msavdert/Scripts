REM     Script:     taila.sql
REM     Purpose:    Tail recent alert log messages in SQL output format.

WITH oneday AS
( SELECT /*+ materialize */ *  FROM TABLE
  (gv$(cursor(select originating_timestamp, message_text FROM v$diag_alert_ext WHERE ORIGINATING_TIMESTAMP > SYSTIMESTAMP - 1 
  AND UPPER(filename) LIKE (select '%'||UPPER(name)||'%' from v$database)))))
  SELECT TO_CHAR (ORIGINATING_TIMESTAMP, 'YYYY-MM-DD HH24:MI:SS') c2,
  MESSAGE_TEXT c3
  FROM oneday
  WHERE originating_timestamp > sysdate-&1
  ORDER BY c2 DESC;