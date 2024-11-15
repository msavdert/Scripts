WITH BackupDataRaw AS (
select
  CASE
    WHEN INPUT_TYPE = 'DB FULL' THEN 'D'
    WHEN INPUT_TYPE = 'DB INCR' THEN 'I'
    WHEN INPUT_TYPE = 'ARCHIVELOG' THEN 'L'
  END AS type,
  end_time AS last_backup_date,
  round(elapsed_seconds) AS duration_seconds,
  output_bytes AS backup_size_bytes,
  ROW_NUMBER() OVER (PARTITION BY INPUT_TYPE ORDER BY end_time DESC) AS rn
from v$rman_backup_job_details
where status='COMPLETED' and INPUT_TYPE IN ('DB FULL','DB INCR','ARCHIVELOG')
),
BackupData AS (
select
  type,
  last_backup_date,
  duration_seconds,
  backup_size_bytes
from BackupDataRaw WHERE rn = 1
),
BackupTimes AS (
SELECT
  MAX(CASE WHEN type = 'D' THEN last_backup_date END) AS full_backup_last_time,
  MAX(CASE WHEN type = 'I' THEN last_backup_date END) AS differential_backup_last_time,
  MAX(CASE WHEN type = 'L' THEN last_backup_date END) AS transaction_log_backup_last_time
FROM BackupData
)
SELECT
  (select host_name from v$instance) ora_instance,
  (select upper(name) from v$database) datname,
  NVL(ROUND((SYSDATE - bt.full_backup_last_time) * 24 * 60 * 60), -1) AS full_backup_since_sec,
  round((CAST(SYS_EXTRACT_UTC(FROM_TZ(CAST(bt.full_backup_last_time AS TIMESTAMP), SESSIONTIMEZONE)) AS DATE) - DATE '1970-01-01') * 86400) AS full_backup_last_time,
  NVL(bd_full.duration_seconds, -1) AS full_backup_duration_sec,
  NVL(bd_full.backup_size_bytes, -1) AS full_backup_size_bytes,
  NVL(ROUND((SYSDATE - bt.differential_backup_last_time) * 24 * 60 * 60), -1) AS diff_backup_since_sec,
  round((CAST(SYS_EXTRACT_UTC(FROM_TZ(CAST(bt.differential_backup_last_time AS TIMESTAMP), SESSIONTIMEZONE)) AS DATE) - DATE '1970-01-01') * 86400) AS diff_backup_last_time,
  NVL(bd_diff.duration_seconds, -1) AS diff_backup_duration_sec,
  NVL(bd_diff.backup_size_bytes, -1) AS diff_backup_size_bytes,
  NVL(ROUND((SYSDATE - bt.transaction_log_backup_last_time) * 24 * 60 * 60), -1) AS log_backup_since_sec,
  round((CAST(SYS_EXTRACT_UTC(FROM_TZ(CAST(bt.transaction_log_backup_last_time AS TIMESTAMP), SESSIONTIMEZONE)) AS DATE) - DATE '1970-01-01') * 86400) AS log_backup_last_time,
  NVL(bd_log.duration_seconds, -1) AS log_backup_duration_sec,
  NVL(bd_log.backup_size_bytes, -1) AS log_backup_size_bytes
FROM BackupTimes bt
LEFT JOIN BackupData bd_full ON bd_full.type = 'D'
LEFT JOIN BackupData bd_diff ON bd_diff.type = 'I'
LEFT JOIN BackupData bd_log ON bd_log.type = 'L';


WITH BackupDataRaw AS (
select
  CASE
    WHEN INPUT_TYPE = 'DB FULL' THEN 'D'
    WHEN INPUT_TYPE = 'DB INCR' THEN 'I'
    WHEN INPUT_TYPE = 'ARCHIVELOG' THEN 'L'
  END AS type,
  end_time AS last_backup_date,
  round(elapsed_seconds) AS duration_seconds,
  output_bytes AS backup_size_bytes,
  ROW_NUMBER() OVER (PARTITION BY INPUT_TYPE ORDER BY end_time DESC) AS rn
from v$rman_backup_job_details
where status='COMPLETED' and INPUT_TYPE IN ('DB FULL','DB INCR','ARCHIVELOG')
),
BackupData AS (
select
  type,
  last_backup_date,
  duration_seconds,
  backup_size_bytes
from BackupDataRaw WHERE rn = 1
),
BackupTimes AS (
SELECT
  MAX(CASE WHEN type = 'D' THEN last_backup_date END) AS full_backup_last_time,
  MAX(CASE WHEN type = 'I' THEN last_backup_date END) AS differential_backup_last_time,
  MAX(CASE WHEN type = 'L' THEN last_backup_date END) AS transaction_log_backup_last_time
FROM BackupData
)
SELECT
  (select host_name from v$instance) ora_instance,
  (select upper(name) from v$database) datname,
  'full_backup_since_sec' AS metric_name, 
  NVL(ROUND((SYSDATE - bt.full_backup_last_time) * 24 * 60 * 60), -1) AS value
FROM BackupTimes bt
LEFT JOIN BackupData bd_full ON bd_full.type = 'D'
UNION ALL
SELECT
  (select host_name from v$instance) ora_instance,
  (select upper(name) from v$database) datname,
  'full_backup_duration_sec' AS metric_name,
  NVL(bd_full.duration_seconds, -1) AS value
FROM BackupTimes bt
LEFT JOIN BackupData bd_full ON bd_full.type = 'D'
UNION ALL
SELECT
  (select host_name from v$instance) ora_instance,
  (select upper(name) from v$database) datname,
  'full_backup_size_bytes' AS metric_name,
  NVL(bd_full.backup_size_bytes, -1) AS value
FROM BackupTimes bt
LEFT JOIN BackupData bd_full ON bd_full.type = 'D'
UNION ALL
SELECT
  (select host_name from v$instance) ora_instance,
  (select upper(name) from v$database) datname,
  'diff_backup_since_sec' AS metric_name,
  NVL(ROUND((SYSDATE - bt.differential_backup_last_time) * 24 * 60 * 60), -1) AS value
FROM BackupTimes bt
LEFT JOIN BackupData bd_diff ON bd_diff.type = 'I'
UNION ALL
SELECT
  (select host_name from v$instance) ora_instance,
  (select upper(name) from v$database) datname,
  'diff_backup_duration_sec' AS metric_name,
  NVL(bd_diff.duration_seconds, -1) AS value
FROM BackupTimes bt
LEFT JOIN BackupData bd_diff ON bd_diff.type = 'I'
UNION ALL
SELECT
  (select host_name from v$instance) ora_instance,
  (select upper(name) from v$database) datname,
  'diff_backup_size_bytes' AS metric_name,
  NVL(bd_diff.backup_size_bytes, -1) AS value
FROM BackupTimes bt
LEFT JOIN BackupData bd_diff ON bd_diff.type = 'I'
UNION ALL
SELECT
  (select host_name from v$instance) ora_instance,
  (select upper(name) from v$database) datname,
  'log_backup_since_sec' AS metric_name,
  NVL(ROUND((SYSDATE - bt.transaction_log_backup_last_time) * 24 * 60 * 60), -1) AS value
FROM BackupTimes bt
LEFT JOIN BackupData bd_log ON bd_log.type = 'L'
UNION ALL
SELECT
  (select host_name from v$instance) ora_instance,
  (select upper(name) from v$database) datname,
  'log_backup_duration_sec' AS metric_name,
  NVL(bd_log.duration_seconds, -1) AS value
FROM BackupTimes bt
LEFT JOIN BackupData bd_log ON bd_log.type = 'L'
UNION ALL
SELECT
  (select host_name from v$instance) ora_instance,
  (select upper(name) from v$database) datname,
  'log_backup_size_bytes' AS metric_name,
  NVL(bd_log.backup_size_bytes, -1) AS value
FROM BackupTimes bt
LEFT JOIN BackupData bd_log ON bd_log.type = 'L';
