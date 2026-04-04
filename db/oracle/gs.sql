REM     Script:     gs.sql
REM     Purpose:    Display the full SQL text for a given SQL_ID.

SELECT sql_fulltext FROM gv$sqlarea WHERE sql_id='&1' AND rownum=1;