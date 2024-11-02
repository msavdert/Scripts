SELECT
    s1.con_id,
    cdb_pdbs.pdb_name,
    s1.sid || ',' || s1.serial# || '@' || s1.inst_id AS "SESSIONS",
    s1.username,
    s1.sql_id,
    (SELECT SUBSTR(REGEXP_REPLACE(sql_text, '( [[:space:]]+)|([[:cntrl:]])',' '), 1, 30) FROM gv$sqlarea WHERE sql_id = s1.sql_id AND rownum = 1) AS sql_text,
    s1.prev_sql_id,
    (SELECT SUBSTR(REGEXP_REPLACE(sql_text, '( [[:space:]]+)|([[:cntrl:]])',' '), 1, 30) FROM gv$sqlarea WHERE sql_id = s1.prev_sql_id AND rownum = 1) AS prev_sql_text,
    s1.program,
    s1.machine,
    s1.wait_class,
    s1.event,
    s2.sid || ',' || s2.serial# || '@' || s2.inst_id AS "BLKD_SESSION",
    s2.serial# AS blkd_serial,
    s2.username AS blkd_username,
    s2.sql_id AS blkd_sql_id,
    (SELECT SUBSTR(REGEXP_REPLACE(sql_text, '( [[:space:]]+)|([[:cntrl:]])',' '), 1, 30) FROM gv$sqlarea WHERE sql_id = s2.sql_id AND rownum = 1) AS blkd_sql_text,
    s2.program AS blkd_program,
    s2.machine AS blkd_machine,
    s2.wait_class AS blkd_wait_class,
    s2.event AS blkd_event,
    s2.seconds_in_wait AS wait_secs,
    'ALTER SYSTEM KILL SESSION ''' || s1.sid || ',' || s1.serial# || ',@' || s1.inst_id || ''' IMMEDIATE;' AS Kill_Script 
FROM gv$lock l1
JOIN gv$session s1 ON s1.sid = l1.sid AND s1.inst_id = l1.inst_id
JOIN gv$lock l2 ON l1.id1 = l2.id1 AND l1.id2 = l2.id2 AND l1.con_id = l2.con_id AND l2.request > 0
JOIN gv$session s2 ON s2.sid = l2.sid AND s2.inst_id = l2.inst_id AND s2.con_id = l2.con_id
JOIN cdb_pdbs ON s1.con_id = cdb_pdbs.con_id
WHERE l1.block = 1
ORDER BY 
    s2.seconds_in_wait DESC;
