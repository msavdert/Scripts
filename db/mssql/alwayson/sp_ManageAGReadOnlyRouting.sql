-- https://github.com/ahmetrende/database-scripts/blob/main/sp_ManageAGReadOnlyRouting/sp_ManageAGReadOnlyRouting.sql
USE master -- Specify the database name in which you would like to store the script.
GO

CREATE OR ALTER PROC sp_ManageAGReadOnlyRouting

	    @AgName			VARCHAR(200) = NULL
	   ,@DatabaseName		VARCHAR(200) = NULL
	   ,@ThresholdSec		INT				
	   ,@HistoryTableFQDN		VARCHAR(500)	

AS

-- ============================================= 
/*
-- File: sp_ManageAGReadOnlyRouting.sql
-- Author: Ahmet Rende      
-- Create date: 2024-10-10
-- Description: This stored procedure manages read-only routing for Availability Groups.
--              You only need to set your read-only routing configuration once and schedule this stored procedure.
-- GitHub: https://github.com/ahmetrende
-- Version: 2024-10-10 (Initial version)
*/
-- =============================================

SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
SET NOCOUNT ON;

DECLARE 
	    @estimated_data_loss_seconds	BIGINT
	   ,@routing_query					NVARCHAR(4000)	= ''
	   ,@disable_routing_sql			NVARCHAR(4000)	= ''
	   ,@rank							INT = 1
	   ,@priority						INT = 1
	   ,@primary_replica				VARCHAR(200)
	   ,@_routing_query 				VARCHAR(8000) = ''
	   ,@insert_table_query				NVARCHAR(4000)
	   ,@_query							NVARCHAR(4000)
	   ,@revert_status					BIT
	   ,@rowid							BIGINT
	   ,@is_primary_replica				VARCHAR(200)

IF OBJECT_ID(N'tempdb..#tmp_current_read_only_routing') IS NOT NULL DROP TABLE #tmp_current_read_only_routing
IF OBJECT_ID(N'tempdb..#tmp_ag_latency') IS NOT NULL DROP TABLE #tmp_ag_latency
IF OBJECT_ID(N'tempdb..#tmp_result') IS NOT NULL DROP TABLE #tmp_result

PRINT FORMAT(SYSDATETIME(), '"Started: "yyyy-MM-dd HH:mm:ss.fff')
PRINT '//--- Availability Group Read-Only Routing Manager ---//'
PRINT ''


SELECT TOP 1 @is_primary_replica = d.database_name FROM sys.availability_groups ag
JOIN sys.availability_databases_cluster d on ag.group_id = d.group_id
WHERE ag.name = ISNULL(@AgName, ag.name)
	AND d.database_name = ISNULL(@DatabaseName, d.database_name)

IF(sys.fn_hadr_is_primary_replica (@is_primary_replica) = 0)
BEGIN
	PRINT 'This is not the primary replica. Exiting.'
	GOTO quit;
END

IF(@DatabaseName IS NOT NULL AND @AgName IS NOT NULL)
BEGIN
	PRINT '@DatabaseName is specified, @AgName will be ignored.'
	SET @AgName = NULL
END

ELSE IF (@DatabaseName IS NULL AND @AgName IS NULL)
BEGIN
	THROW 51000, '@DatabaseName or @AgName must be specified.', 1;
END

IF (@DatabaseName IS NOT NULL)
BEGIN
	SELECT @AgName = ag.name 
	FROM sys.availability_databases_cluster d
		JOIN sys.availability_groups ag on d.group_id = ag.group_id
	WHERE d.database_name = @DatabaseName
END


PRINT 'Checking replication latency for ' + IIF(@AgName IS NOT NULL, QUOTENAME(@AgName), '') + '.' + IIF(@DatabaseName IS NOT NULL, QUOTENAME(@DatabaseName), '[*]') + CHAR(13) + 'Threshold: ' + CAST(@ThresholdSec AS VARCHAR(50)) + ' second(s).'

IF OBJECT_ID(@HistoryTableFQDN) IS NULL 
BEGIN
	
	PRINT 'The table "' + @HistoryTableFQDN + '" was not found and will be created.'
	SET @_query = '
		CREATE TABLE ' + @HistoryTableFQDN + '
		(
			[id] [bigint] IDENTITY(1,1) NOT NULL PRIMARY KEY CLUSTERED ,
			[server_name] [nvarchar](128) NULL,
			[ag_name] [varchar](200) NULL,
			[database_name] [varchar](200) NULL,
			[routing_query] [nvarchar](4000) NULL,
			[estimated_data_loss_seconds] [bigint] NULL,
			[revert_status] [bit] NOT NULL,
			[created_date] [datetime2](7) NOT NULL,
			[updated_date] [datetime2](7) NOT NULL
		)'
	EXEC sys.sp_executesql @_query

END

CREATE TABLE #tmp_ag_latency 
(
	[ag_replica_server] [nvarchar](100),
	[ag_name] [nvarchar](100),
	[database_name] [nvarchar](100),
	[connected_state_desc] [nvarchar](100),
	[synchronization_health_desc] [nvarchar](100),
	[estimated_data_loss_time] [nvarchar](100),
	[estimated_data_loss_seconds] AS DATEDIFF_BIG(SECOND, secondary_last_commit_time, primary_last_commit_time),
	[primary_last_commit_time] [datetime],
	[secondary_last_commit_time] [datetime],
	[collection_time] DATETIME2(3) DEFAULT (SYSDATETIME())
)


PRINT ''

SELECT DISTINCT	
		 ag.name AS ag_name
		,r.replica_server_name AS primary_replica
		,ro.routing_priority AS priority
		,r2.replica_server_name AS secondary_replica
		,DENSE_RANK() OVER (ORDER BY ag.name, r.replica_server_name) AS rank
	INTO #tmp_current_read_only_routing
FROM	sys.availability_replicas r
		JOIN sys.availability_read_only_routing_lists ro ON  r.replica_id = ro.replica_id
		JOIN sys.availability_replicas r2 ON ro.read_only_replica_id = r2.replica_id
		JOIN sys.availability_groups ag ON ag.group_id=r.group_id
		JOIN sys.availability_databases_cluster d ON d.group_id = ag.group_id 
WHERE ag.name = ISNULL(@AgName, ag.name)
		  AND d.database_name = ISNULL(@DatabaseName, d.database_name)

WHILE EXISTS(SELECT 1 FROM #tmp_current_read_only_routing WHERE rank = @rank)
BEGIN
	SET @AgName = (SELECT TOP 1 ag_name FROM #tmp_current_read_only_routing WHERE rank = @rank)
	SET @primary_replica = (SELECT TOP 1 primary_replica FROM #tmp_current_read_only_routing WHERE rank = @rank)

	WHILE EXISTS(SELECT 1 FROM #tmp_current_read_only_routing WHERE rank = @rank AND priority = @priority)
	BEGIN
		SELECT @_routing_query = @_routing_query + '(' +STRING_AGG('N''' + secondary_replica + '''', ',') + ')'
		FROM #tmp_current_read_only_routing WHERE rank = @rank and priority = @priority
		SET @priority += 1
	END
	
	SET @_routing_query = REPLACE(@_routing_query, ')(', '),(')
	SET @routing_query += CHAR(9) + 'USE master; ALTER AVAILABILITY GROUP ' + QUOTENAME(@AgName) + ' MODIFY REPLICA ON N''' + @primary_replica + ''' WITH (PRIMARY_ROLE(READ_ONLY_ROUTING_LIST = (' + @_routing_query + ')));' + CHAR(13) 
	SET @_routing_query = ''
	SET @priority = 1
	SET @rank += 1

END

;WITH PrimaryCTE as (
	SELECT ag.name AS ag_name, ar.replica_server_name AS ag_replica_server, DB_NAME(dr_state.database_id) as database_name, 
	is_ag_replica_local = CASE 
	WHEN ar_state.is_local = 1 THEN N'LOCAL' 
	ELSE 'REMOTE' 
	END , 
	ag_replica_role = CASE 
	WHEN ar_state.role_desc IS NULL THEN N'DISCONNECTED' 
	ELSE ar_state.role_desc 
	END, 
	ar_state.connected_state_desc,
	dr_state.synchronization_health_desc,
	dr_state.last_commit_time
	FROM (( sys.availability_groups AS ag (nolock) JOIN sys.availability_replicas AS ar (nolock) ON ag.group_id = ar.group_id ) 
	JOIN sys.dm_hadr_availability_replica_states AS ar_state (nolock) ON ar.replica_id = ar_state.replica_id) 
	JOIN sys.dm_hadr_database_replica_states dr_state (nolock) on ag.group_id = dr_state.group_id and dr_state.replica_id = ar_state.replica_id
	where ar_state.is_local = 1
		AND ag.name = ISNULL(@AgName, ag.name)
		AND DB_NAME(dr_state.database_id) = ISNULL(@DatabaseName, DB_NAME(dr_state.database_id))
) 
, SecondaryCTE as (
	SELECT ag.name AS ag_name, ar.replica_server_name AS ag_replica_server, DB_NAME(dr_state.database_id) as database_name, 
	is_ag_replica_local = CASE 
	WHEN ar_state.is_local = 1 THEN N'LOCAL' 
	ELSE 'REMOTE' 
	END , 
	ag_replica_role = CASE 
	WHEN ar_state.role_desc IS NULL THEN N'DISCONNECTED' 
	ELSE ar_state.role_desc 
	END, 
	ar_state.connected_state_desc,
	dr_state.synchronization_health_desc,
	dr_state.last_commit_time
	FROM (( sys.availability_groups AS ag (nolock) JOIN sys.availability_replicas AS ar (nolock) ON ag.group_id = ar.group_id ) 
	JOIN sys.dm_hadr_availability_replica_states AS ar_state (nolock) ON ar.replica_id = ar_state.replica_id) 
	JOIN sys.dm_hadr_database_replica_states dr_state (nolock) on ag.group_id = dr_state.group_id and dr_state.replica_id = ar_state.replica_id
	where ar_state.is_local = 0
		AND ag.name = ISNULL(@AgName, ag.name)
		AND DB_NAME(dr_state.database_id) = ISNULL(@DatabaseName, DB_NAME(dr_state.database_id))
)

INSERT INTO #tmp_ag_latency 
(ag_replica_server, ag_name, database_name, connected_state_desc, synchronization_health_desc, estimated_data_loss_time, primary_last_commit_time, secondary_last_commit_time)
SELECT  
 b.ag_replica_server
,b.ag_name
,b.database_name
,b.connected_state_desc
,b.synchronization_health_desc
,ISNULL(RIGHT('00'+CAST((((DATEDIFF(SECOND, b.last_commit_time, a.last_commit_time))%86400000)/3600000) AS VARCHAR(2)),2) + ':'+
RIGHT('00'+CAST(((((DATEDIFF(SECOND, b.last_commit_time, a.last_commit_time))%86400000)%3600000)/60000) AS VARCHAR(2)),2) + ':'+
RIGHT('00'+CAST((((((DATEDIFF(SECOND, b.last_commit_time, a.last_commit_time))%86400000)%3600000)%60000)/1000) AS VARCHAR(2)),2) --+ ':' +
,'') as estimated_data_loss_time
,a.last_commit_time as primary_last_commit_time
,b.last_commit_time as secondary_last_commit_time
FROM PrimaryCTE a (NOLOCK)
JOIN SecondaryCTE b (NOLOCK)
ON a.database_name = b.database_name
ORDER BY b.synchronization_health_desc DESC
		,DATEDIFF(MILLISECOND, b.last_commit_time, a.last_commit_time) DESC
		,b.connected_state_desc DESC
		,b.ag_name
		,b.ag_replica_server 
		,b.database_name

SET @estimated_data_loss_seconds = (SELECT MAX(estimated_data_loss_seconds) FROM #tmp_ag_latency)
IF EXISTS(SELECT 1 FROM #tmp_ag_latency WHERE estimated_data_loss_seconds >= @ThresholdSec AND database_name = ISNULL(@DatabaseName, database_name) AND ag_name = ISNULL(@AgName, ag_name))
BEGIN
	
	PRINT 'There is latency between replicas!!! Estimated data loss: ' + CAST(@estimated_data_loss_seconds AS VARCHAR(10)) + ' second(s).'

	IF (ISNULL(@routing_query, N'') <> N'')
	BEGIN
		PRINT 'The read requests are redirected to the primary node.'
		SELECT @@servername as server_name, @AgName as ag_name, @DatabaseName AS database_name, @routing_query AS routing_query, @estimated_data_loss_seconds AS estimated_data_loss_seconds, CAST(0 AS BIT) revert_status, SYSDATETIME() AS created_date, SYSDATETIME() AS updated_date
			INTO #tmp_result

		SET @insert_table_query = 'INSERT INTO ' + @HistoryTableFQDN + ' SELECT * FROM #tmp_result;'
		EXEC sys.sp_executesql @insert_table_query
		PRINT 'Inserted current configuration into ' + @HistoryTableFQDN

		SELECT @disable_routing_sql = @disable_routing_sql + CHAR(9) + 
		'USE master; ALTER AVAILABILITY GROUP ' + QUOTENAME(@AgName) + ' MODIFY REPLICA ON N''' + replica_server_name + 
		''' WITH (PRIMARY_ROLE(READ_ONLY_ROUTING_LIST = NONE));' + CHAR(13)
		FROM sys.availability_replicas r
		JOIN sys.availability_groups ag ON ag.group_id=r.group_id
		WHERE ag.name = @AgName

		PRINT 'Executing:'
		PRINT TRIM(@disable_routing_sql)
		EXEC sys.sp_executesql @disable_routing_sql
	END
	ELSE
	BEGIN
		PRINT 'No redirection to read replica(s).'

	END
	
END
ELSE
BEGIN

	SELECT TOP 1
		 @revert_status = revert_status 
		,@routing_query = routing_query
		,@rowid = id
	FROM DBA.dbo.ag_read_only_routing_history
		where ag_name = @AgName
		ORDER BY id DESC

	IF(@revert_status = 0)
	BEGIN
		PRINT 'OK! Estimated data loss: ' + CAST(@estimated_data_loss_seconds AS VARCHAR(10)) + ' second(s).'
		PRINT 'The read requests are being redirected back to the read replica(s).'
		PRINT 'Executing:'
		PRINT TRIM(@routing_query)
		EXEC sys.sp_executesql @routing_query

		SET @_query = N'UPDATE ' + @HistoryTableFQDN + ' SET revert_status = 1, updated_date = SYSDATETIME() WHERE id = ' + CAST(@rowid AS VARCHAR(50))  
		EXEC sys.sp_executesql @_query

		PRINT 'The latest configuration was restored from  ' + @HistoryTableFQDN

	END
	ELSE
	BEGIN
		PRINT 'Estimated data loss: ' + CAST(@estimated_data_loss_seconds AS VARCHAR(10)) + ' second(s).'
		PRINT 'No change. Enjoy!'
	END

END

quit:
PRINT ''
PRINT FORMAT(SYSDATETIME(), '"Finished: "yyyy-MM-dd HH:mm:ss.fff')

GO
