-- Underlying Windows Failover Cluster info

SELECT  member_name, member_type_desc AS member_type, member_state_desc AS member_state, number_of_quorum_votes
FROM sys.dm_hadr_cluster_members;

-- AG level info => Recovery health + synchronization state

SELECT
  g.name as ag_name,
  rgs.primary_replica,
  rgs.primary_recovery_health_desc AS [primary_recovery_health],
  rgs.synchronization_health_desc AS [synchronization_health]
FROM sys.dm_hadr_availability_group_states as rgs
JOIN sys.availability_groups AS g ON rgs.group_id = g.group_id;

-- AG replica level info => synchronization state + operational state + recovery health

SELECT
  g.name as ag_name,
  r.replica_server_name,
  rs.is_local, role_desc AS [role],
  rs.operational_state_desc AS [operational_state],
  rs.connected_state_desc AS [connected_state],
  rs.recovery_health_desc AS [recovery_health],
  rs.synchronization_health_desc AS [synchronization_health]
FROM sys.dm_hadr_availability_replica_states AS rs
JOIN sys.availability_replicas AS r ON rs.replica_id = r.replica_id
JOIN sys.availability_groups AS g ON g.group_id = r.group_id

-- AG database level info => synchronization state + operational state + database state recovery health

SELECT
  g.name as ag_name,
  r.replica_server_name,
  DB_NAME(drs.database_id) AS [database_name],
  drs.is_local,
  drs.is_primary_replica,
  drs.synchronization_health_desc AS [synchronization_health],
  drs.synchronization_state_desc AS [synchronization_state],
  drs.database_state_desc AS [database_state],
  drs.is_suspended, drs.suspend_reason_desc AS [suspend_reason],
  drs.secondary_lag_seconds
FROM sys.dm_hadr_database_replica_states AS drs
JOIN sys.availability_replicas AS r ON r.replica_id = drs.replica_id
JOIN sys.availability_groups AS g ON g.group_id = drs.group_id
ORDER BY g.name, drs.is_primary_replica DESC, drs.database_id 
