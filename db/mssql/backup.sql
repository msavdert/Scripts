WITH BackupData AS (
    SELECT 
        database_name,
        type,
        MAX(backup_finish_date) AS last_backup_date,
        DATEDIFF(SECOND, MAX(backup_start_date), MAX(backup_finish_date)) AS duration_seconds,
        CAST(MAX(backup_size)AS BIGINT)/1024/1024 AS backup_size_mb
    FROM msdb.dbo.backupset
    WHERE type IN ('D', 'I', 'L')
    GROUP BY database_name, type
),
BackupTimes AS (
    SELECT 
        database_name,
        MAX(CASE WHEN type = 'D' THEN last_backup_date END) AS full_backup_last_time,
        MAX(CASE WHEN type = 'I' THEN last_backup_date END) AS differential_backup_last_time,
        MAX(CASE WHEN type = 'L' THEN last_backup_date END) AS transaction_log_backup_last_time
    FROM BackupData
    GROUP BY database_name
)
SELECT
  REPLACE(@@SERVERNAME,'\',':') AS [sql_instance],
  db.name AS [database_name],
  db.state_desc AS db_state,
  db.recovery_model_desc AS db_recovery_model,
  -- Time since last full backup and date of last full backup
  FORMAT(bt.full_backup_last_time, 'dd MMM, yyyy HH:mm') AS full_backup_last_time,
--  DATEDIFF(SECOND, bt.full_backup_last_time, GETDATE()) AS full_backup_since_sec,
  RIGHT('00' + CONVERT(VARCHAR, (DATEDIFF(SECOND, bt.full_backup_last_time, GETDATE()) / 86400)), 2) + 'd:' +  -- Gün
  RIGHT('00' + CONVERT(VARCHAR, ((DATEDIFF(SECOND, bt.full_backup_last_time, GETDATE()) % 86400) / 3600)), 2) + 'h:' +  -- Saat
  RIGHT('00' + CONVERT(VARCHAR, ((DATEDIFF(SECOND, bt.full_backup_last_time, GETDATE()) % 3600) / 60)), 2) + 'm:' +  -- Dakika
  RIGHT('00' + CONVERT(VARCHAR, (DATEDIFF(SECOND, bt.full_backup_last_time, GETDATE()) % 60)), 2) + 's' AS full_backup_since_sec,
  bd_full.duration_seconds AS full_backup_duration_sec,
  bd_full.backup_size_mb AS full_backup_size_mb,
  -- Time since last differential backup and date of last differential backup
  FORMAT(bt.differential_backup_last_time, 'dd MMM, yyyy HH:mm') AS differential_backup_last_time,
--  DATEDIFF(SECOND, bt.differential_backup_last_time, GETDATE()) AS diff_backup_since_sec,
  RIGHT('00' + CONVERT(VARCHAR, (DATEDIFF(SECOND, bt.differential_backup_last_time, GETDATE()) / 86400)), 2) + 'd:' +  -- Gün
  RIGHT('00' + CONVERT(VARCHAR, ((DATEDIFF(SECOND, bt.differential_backup_last_time, GETDATE()) % 86400) / 3600)), 2) + 'h:' +  -- Saat
  RIGHT('00' + CONVERT(VARCHAR, ((DATEDIFF(SECOND, bt.differential_backup_last_time, GETDATE()) % 3600) / 60)), 2) + 'm:' +  -- Dakika
  RIGHT('00' + CONVERT(VARCHAR, (DATEDIFF(SECOND, bt.differential_backup_last_time, GETDATE()) % 60)), 2) + 's' AS diff_backup_since_sec,
  bd_diff.duration_seconds AS diff_backup_duration_sec,
  bd_diff.backup_size_mb AS diff_backup_size_mb,
  -- Time since last transaction log backup and date of last transaction log backup
  FORMAT(bt.transaction_log_backup_last_time, 'dd MMM, yyyy HH:mm') AS transaction_log_backup_last_time,
--  DATEDIFF(SECOND, bt.transaction_log_backup_last_time, GETDATE()) AS log_backup_since_sec,
  RIGHT('00' + CONVERT(VARCHAR, (DATEDIFF(SECOND, bt.transaction_log_backup_last_time, GETDATE()) / 86400)), 2) + 'd:' +  -- Gün
  RIGHT('00' + CONVERT(VARCHAR, ((DATEDIFF(SECOND, bt.transaction_log_backup_last_time, GETDATE()) % 86400) / 3600)), 2) + 'h:' +  -- Saat
  RIGHT('00' + CONVERT(VARCHAR, ((DATEDIFF(SECOND, bt.transaction_log_backup_last_time, GETDATE()) % 3600) / 60)), 2) + 'm:' +  -- Dakika
  RIGHT('00' + CONVERT(VARCHAR, (DATEDIFF(SECOND, bt.transaction_log_backup_last_time, GETDATE()) % 60)), 2) + 's' AS log_backup_since_sec,
  bd_log.duration_seconds AS log_backup_duration_sec,
  bd_log.backup_size_mb AS log_backup_size_mb
FROM sys.databases db
LEFT JOIN BackupTimes bt ON db.name = bt.database_name
LEFT JOIN BackupData bd_full ON db.name = bd_full.database_name AND bd_full.type = 'D'
LEFT JOIN BackupData bd_diff ON db.name = bd_diff.database_name AND bd_diff.type = 'I'
LEFT JOIN BackupData bd_log ON db.name = bd_log.database_name AND bd_log.type = 'L'
WHERE db.name <> 'tempdb'  -- Exclude 'tempdb' database
ORDER BY db.name;
