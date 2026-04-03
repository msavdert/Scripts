--PROMPT
--PROMPT COUNT ACTIVE AND INACTIVE SESSIONS
--PROMPT ***************************
--select s.status, count(s.status) TOTAL_SESSIONS from gv$session s where type NOT LIKE 'BACKGROUND' group by status order by status;

--PROMPT SESSIONS WHICH ARE IN INACTIVE STATUS FROM MORE THAN 1HOUR
PROMPT ***************************
select count(s.status) "INACTIVE SESSIONS > 1HOUR " from gv$session s, v$process p where type NOT LIKE 'BACKGROUND' and p.addr=s.paddr and s.last_call_et > 3600 and s.status='INACTIVE' group by status order by status;

PROMPT ACTIVE AND INACTIVE SESSION PER INSTANCE
PROMPT ***************************
select s.inst_id,s.status,count(s.status) TOTAL_SESSIONS from gv$session s where type NOT LIKE 'BACKGROUND' group by inst_id,status order by status;

break on report on disk_group_name skip 1
compute sum label "Grand Total: " of ACTIVE INACTIVE on report

col username format a30

PROMPT ACTIVE AND INACTIVE USERS COUNT
PROMPT ***************************
select username,g.ACTIVE,g.INACTIVE,(g.ACTIVE+g.INACTIVE) TOTAL from (SELECT s.username,
         (SELECT COUNT (*)
            FROM gv$session ss
           WHERE ss.username=s.username and ss.status = 'ACTIVE' AND type NOT LIKE 'BACKGROUND')
            ACTIVE,
         (SELECT COUNT (*)
            FROM gv$session ss
           WHERE s.username=ss.username AND ss.status = 'INACTIVE' AND type NOT LIKE 'BACKGROUND')
            INACTIVE
    FROM gv$session s
   WHERE s.username IS NOT NULL
GROUP BY s.username
ORDER BY 3 DESC) g;

--PROMPT ACTIVE AND INACTIVE USERS COUNT
--PROMPT ***************************
--select username,g.ACTIVE,g.INACTIVE,(g.ACTIVE+g.INACTIVE) TOTAL from (SELECT s.username,
--         (SELECT COUNT (*)
--           FROM gv$session ss
--           WHERE ss.username=s.username and ss.status = 'ACTIVE' AND type NOT LIKE 'BACKGROUND')
--            ACTIVE,
--         (SELECT COUNT (*)
--            FROM gv$session ss
--           WHERE s.username=ss.username AND ss.status = 'INACTIVE' AND type NOT LIKE 'BACKGROUND')
--            INACTIVE
--    FROM gv$session s
--   WHERE s.username IS NOT NULL
--GROUP BY s.username
--ORDER BY 3 DESC) g;
