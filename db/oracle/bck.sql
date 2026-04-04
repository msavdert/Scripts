REM     Script:     bck.sql
REM     Purpose:    Show RMAN backup job history with size, duration, and
REM                 throughput details.

col day format a10
col start_time format a21
col end_time format a21
col time_taken format a10
col elaps_min format 99999
col comp_ratio format 9999
col input_size format a12
col output_size format a12
col "OutBytesPerSec" format a14

SELECT TO_CHAR (j.start_time, 'DD-MON-YYYY HH24:MI:SS') start_time,
       TO_CHAR (j.end_time, 'DD-MON-YYYY HH24:MI:SS') end_time,
       DECODE(TO_CHAR(j.start_time, 'd'), 1, 'Sunday', 2, 'Monday', 3, 'Tuesday', 4, 'Wednesday', 5, 'Thursday', 6, 'Friday', 7, 'Saturday') day,
       x.device_type device_type, j.input_type, CASE WHEN I0 > 0 THEN 0 WHEN I1 > 0 THEN 1 END l,
       j.status,
       j.time_taken_display time_taken,
       ROUND (j.elapsed_seconds / 60, 0) elaps_min,
       ROUND(j.compression_ratio,1) comp_ratio,
       j.input_bytes_display input_size,
       j.output_bytes_display output_size,
       j.output_bytes_per_sec_display "OutBytesPerSec"
  FROM V$RMAN_BACKUP_JOB_DETAILS j
    left outer join (
        select d.session_recid,
               d.session_stamp,
               sum(case when d.controlfile_included = 'YES' then d.pieces else 0 end) CF,
               sum(case when d.controlfile_included = 'NO' and d.backup_type||d.incremental_level = 'D' then d.pieces else 0 end) DF,
               sum(case when d.backup_type||d.incremental_level in ('I0', 'D0') then d.pieces else 0 end) I0,
               sum(case when d.backup_type||d.incremental_level = 'I1' then d.pieces else 0 end) I1,
               sum(case when d.backup_type = 'L' then d.pieces else 0 end) L,
               d.device_type device_type
          from V$BACKUP_SET_DETAILS d
            join V$BACKUP_SET s on s.set_stamp = d.set_stamp and s.set_count = d.set_count
          where s.input_file_scan_only = 'NO'
            group by d.session_recid, d.session_stamp, d.device_type) x on x.session_recid = j.session_recid and x.session_stamp = j.session_stamp
        left outer join (select o.session_recid, o.session_stamp, min(inst_id) inst_id
        from GV$RMAN_OUTPUT o
          group by o.session_recid, o.session_stamp) ro on ro.session_recid = j.session_recid
        and ro.session_stamp = j.session_stamp
        WHERE j.start_time > TRUNC (SYSDATE-7) AND j.INPUT_TYPE not in ('CONTROLFILE')
        ORDER BY TO_DATE (start_time, 'DD-MON-YYYY HH24:MI:SS') DESC,device_type desc;