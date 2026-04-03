col "date" format a15

col "H00" format 999
col "H01" format 999
col "H02" format 999
col "H03" format 999
col "H04" format 999
col "H05" format 999
col "H06" format 999
col "H07" format 999
col "H08" format 999
col "H09" format 999
col "H10" format 999
col "H11" format 999
col "H12" format 999
col "H13" format 999
col "H14" format 999
col "H15" format 999
col "H16" format 999
col "H17" format 999
col "H18" format 999
col "H19" format 999
col "H20" format 999
col "H21" format 999
col "H22" format 999
col "H23" format 999

select to_char(completion_time,'YYYY-MON-DD') as "date",thread#, to_char(completion_time,'Dy') as "Day", count(1) as "total",
sum(decode(to_char(completion_time,'HH24'),'00',1,0)) as "h00",
sum(decode(to_char(completion_time,'HH24'),'01',1,0)) as "h01",
sum(decode(to_char(completion_time,'HH24'),'02',1,0)) as "h02",
sum(decode(to_char(completion_time,'HH24'),'03',1,0)) as "h03",
sum(decode(to_char(completion_time,'HH24'),'04',1,0)) as "h04",
sum(decode(to_char(completion_time,'HH24'),'05',1,0)) as "h05",
sum(decode(to_char(completion_time,'HH24'),'06',1,0)) as "h06",
sum(decode(to_char(completion_time,'HH24'),'07',1,0)) as "h07",
sum(decode(to_char(completion_time,'HH24'),'08',1,0)) as "h08",
sum(decode(to_char(completion_time,'HH24'),'09',1,0)) as "h09",
sum(decode(to_char(completion_time,'HH24'),'10',1,0)) as "h10",
sum(decode(to_char(completion_time,'HH24'),'11',1,0)) as "h11",
sum(decode(to_char(completion_time,'HH24'),'12',1,0)) as "h12",
sum(decode(to_char(completion_time,'HH24'),'13',1,0)) as "h13",
sum(decode(to_char(completion_time,'HH24'),'14',1,0)) as "h14",
sum(decode(to_char(completion_time,'HH24'),'15',1,0)) as "h15",
sum(decode(to_char(completion_time,'HH24'),'16',1,0)) as "h16",
sum(decode(to_char(completion_time,'HH24'),'17',1,0)) as "h17",
sum(decode(to_char(completion_time,'HH24'),'18',1,0)) as "h18",
sum(decode(to_char(completion_time,'HH24'),'19',1,0)) as "h19",
sum(decode(to_char(completion_time,'HH24'),'20',1,0)) as "h20",
sum(decode(to_char(completion_time,'HH24'),'21',1,0)) as "h21",
sum(decode(to_char(completion_time,'HH24'),'22',1,0)) as "h22",
sum(decode(to_char(completion_time,'HH24'),'23',1,0)) as "h23",
round(sum(blocks*block_size)/1024/1024/1024,1) as GB
from
v$archived_log
where first_time > trunc(sysdate-&1)
and dest_id = (select dest_id from V$ARCHIVE_DEST_STATUS where status='VALID' and type='LOCAL' and rownum<2)
group by thread#, to_char(completion_time,'YYYY-MON-DD'), to_char(completion_time, 'Dy') order by 1 desc,2;


col date format a10
col day format a5
col "TOTAL" format 99999
col "H0" format 9999
col "H1" format 9999
col "H2" format 9999
col "H3" format 9999
col "H4" format 9999
col "H5" format 9999
col "H6" format 9999
col "H7" format 9999
col "H8" format 9999
col "H9" format 9999
col "H10" format 9999
col "H11" format 9999
col "H12" format 9999
col "H13" format 9999
col "H14" format 9999
col "H15" format 9999
col "H16" format 9999
col "H17" format 9999
col "H18" format 9999
col "H19" format 9999
col "H20" format 9999
col "H21" format 9999
col "H22" format 9999
col "H23" format 9999

SELECT to_char(first_time,'YYYY-MM-DD') "DATE", inst_id, TO_CHAR (first_time, 'Dy') "DAY",
 COUNT (1) "TOTAL",
 SUM (DECODE (TO_CHAR (first_time, 'hh24'), '00', 1, 0)) "H0",
 SUM (DECODE (TO_CHAR (first_time, 'hh24'), '01', 1, 0)) "H1",
 SUM (DECODE (TO_CHAR (first_time, 'hh24'), '02', 1, 0)) "H2",
 SUM (DECODE (TO_CHAR (first_time, 'hh24'), '03', 1, 0)) "H3",
 SUM (DECODE (TO_CHAR (first_time, 'hh24'), '04', 1, 0)) "H4",
 SUM (DECODE (TO_CHAR (first_time, 'hh24'), '05', 1, 0)) "H5",
 SUM (DECODE (TO_CHAR (first_time, 'hh24'), '06', 1, 0)) "H6",
 SUM (DECODE (TO_CHAR (first_time, 'hh24'), '07', 1, 0)) "H7",
 SUM (DECODE (TO_CHAR (first_time, 'hh24'), '08', 1, 0)) "H8",
 SUM (DECODE (TO_CHAR (first_time, 'hh24'), '09', 1, 0)) "H9",
 SUM (DECODE (TO_CHAR (first_time, 'hh24'), '10', 1, 0)) "H10",
 SUM (DECODE (TO_CHAR (first_time, 'hh24'), '11', 1, 0)) "H11",
 SUM (DECODE (TO_CHAR (first_time, 'hh24'), '12', 1, 0)) "H12",
 SUM (DECODE (TO_CHAR (first_time, 'hh24'), '13', 1, 0)) "H13",
 SUM (DECODE (TO_CHAR (first_time, 'hh24'), '14', 1, 0)) "H14",
 SUM (DECODE (TO_CHAR (first_time, 'hh24'), '15', 1, 0)) "H15",
 SUM (DECODE (TO_CHAR (first_time, 'hh24'), '16', 1, 0)) "H16",
 SUM (DECODE (TO_CHAR (first_time, 'hh24'), '17', 1, 0)) "H17",
 SUM (DECODE (TO_CHAR (first_time, 'hh24'), '18', 1, 0)) "H18",
 SUM (DECODE (TO_CHAR (first_time, 'hh24'), '19', 1, 0)) "H19",
 SUM (DECODE (TO_CHAR (first_time, 'hh24'), '20', 1, 0)) "H20",
 SUM (DECODE (TO_CHAR (first_time, 'hh24'), '21', 1, 0)) "H21",
 SUM (DECODE (TO_CHAR (first_time, 'hh24'), '22', 1, 0)) "H22",
 SUM (DECODE (TO_CHAR (first_time, 'hh24'), '23', 1, 0)) "H23",
 ROUND(count(1)*(select Avg(BYTES) from v$log)/1024/1024/1024,1) AS "AVG_GB"
FROM gv$log_history
WHERE thread# = inst_id
AND first_time > sysdate -9
GROUP BY to_char(first_time,'YYYY-MM-DD'), inst_id, TO_CHAR (first_time, 'Dy')
ORDER BY 1 desc,2;