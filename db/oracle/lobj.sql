REM     Script:     lobj.sql
REM     Purpose:    List locked database objects with owner, object, and session
REM                 details.

col owner for a15
col object_name for a30
col object_type for a15
col lo.session_id for a10
col oracle_username for a20


SELECT lo.inst_id,
       lo.session_id sid,
       lo.process,
       DO.owner,
       DO.object_name,
       DO.object_type,
       lo.oracle_username
  FROM dba_objects DO, gv$locked_object lo
WHERE DO.object_id = lo.object_id
ORDER BY 2;