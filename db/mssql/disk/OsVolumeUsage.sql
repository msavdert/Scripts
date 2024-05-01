SELECT DISTINCT
   SERVERPROPERTY('MachineName') AS MachineName
 , ISNULL(SERVERPROPERTY('InstanceName'), 'MSSQLSERVER') AS InstanceName
 , vs.volume_mount_point AS VolumeName
 , vs.logical_volume_name AS VolumeLabel
 , vs.total_bytes AS VolumeCapacity
 , vs.available_bytes AS VolumeFreeSpace
 , CAST(vs.available_bytes * 100.0 / vs.total_bytes AS DECIMAL(5, 2)) AS PercentageFreeSpace
FROM sys.master_files AS mf
 CROSS APPLY sys.dm_os_volume_stats(mf.database_id, mf.file_id) AS vs;
RETURN;
