col dest_id format 9999999
col name format a15
col time_diff format a15
col error format a32

SELECT
    a.dest_id,
    a.name,
    a.thread#,
    c.status,
    c.type,
    c.database_mode,
    c.recovery_mode,
    c.protection_mode,
    d.process,
    d.transmit_mode,
    b.last_seq                                             last_seq_prmy,
    a.applied_seq                                          applied_seq_stby,
    to_char(a.last_app_timestamp, 'YYYY-MM-DD HH24:MI:SS') last_app_timestamp,
    b.last_seq - a.applied_seq                             arch_diff,
    floor(sysdate - last_app_timestamp)
    || 'd '
    || trunc(24 *((sysdate - last_app_timestamp) - trunc(sysdate - last_app_timestamp)))
    || 'h '
    || mod(trunc(1440 *((sysdate - last_app_timestamp) - trunc(sysdate - last_app_timestamp))),
           60)
    || 'm '
    || mod(trunc(86400 *((sysdate - last_app_timestamp) - trunc(sysdate - last_app_timestamp))),
           60)
    || 's'                                                 time_diff,
    c.error
FROM
    (
        SELECT
            thread#,
            MAX(sequence#) applied_seq,
            MAX(next_time) last_app_timestamp,
            dest_id,
            name
        FROM
            gv$archived_log
        WHERE
                applied = 'YES'
            AND name IN (SELECT destination FROM gv$archive_dest WHERE  destination IS NOT NULL)
            AND first_change# > (SELECT resetlogs_change# FROM v$database)
            AND resetlogs_time = (SELECT resetlogs_time FROM v$database)
        GROUP BY
            thread#,
            dest_id,
            name
    ) a,
    (
        SELECT
            thread#,
            MAX(sequence#) last_seq,
            dest_id
        FROM
            gv$archived_log
        WHERE
                resetlogs_time = (SELECT resetlogs_time FROM v$database)
            AND first_change# > (SELECT resetlogs_change# FROM v$database)
        GROUP BY
            thread#,
            dest_id
    ) b,
    (
        SELECT
            dest_id,
            dest_name,
            status,
            type,
            database_mode,
            recovery_mode,
            protection_mode,
            destination,
            db_unique_name,
            error
        FROM
            v$archive_dest_status
        WHERE
            type <> 'LOCAL'
    ) c,
    (
        SELECT
            dest_id,
            archiver,
            process,
            transmit_mode
        FROM
            v$archive_dest
        WHERE
            destination IS NOT NULL
    ) d
WHERE
        a.thread# = b.thread#
    AND a.dest_id = c.dest_id
    AND b.dest_id = c.dest_id
    AND a.dest_id = d.dest_id
    AND b.dest_id = d.dest_id
    AND c.dest_id = d.dest_id
ORDER BY
    2,
    3;