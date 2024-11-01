WITH Waits AS (
    SELECT
        wait_type,
        wait_time_ms / 1000.0 AS wait_time_s,
        (wait_time_ms - signal_wait_time_ms) / 1000.0 AS resource_wait_time_s,
        signal_wait_time_ms / 1000.0 AS signal_wait_time_s,
        waiting_tasks_count,
        100.0 * wait_time_ms / SUM(wait_time_ms) OVER() AS percent_total_waits
    FROM
        sys.dm_os_wait_stats
    WHERE
        wait_type NOT IN (
            'SLEEP_TASK', 'BROKER_TASK_STOP', 'BROKER_TO_FLUSH', 'SQLTRACE_BUFFER_FLUSH', 
            'CLR_AUTO_EVENT', 'CLR_MANUAL_EVENT', 'LAZYWRITER_SLEEP', 'SLEEP_SYSTEMTASK', 
            'SLEEP_BPOOL_FLUSH', 'BROKER_EVENTHANDLER', 'XE_DISPATCHER_WAIT', 'XE_TIMER_EVENT', 
            'FT_IFTS_SCHEDULER_IDLE_WAIT', 'CHECKPOINT_QUEUE', 'REQUEST_FOR_DEADLOCK_SEARCH', 
            'XE_DISPATCHER_JOIN', 'WAITFOR', 'LOGMGR_QUEUE', 'RBIO_COMM_RECV_IDLE', 'DISPATCHER_QUEUE_SEMAPHORE', 
            'FT_IFTSHC_MUTEX', 'SQLTRACE_INCREMENTAL_FLUSH_SLEEP', 'BROKER_TRANSMITTER', 'RBIO_COMM_SEND_IDLE', 
            'ONDEMAND_TASK_QUEUE', 'QDS_CLEANUP_STALE_QUERIES_TASK_MAIN_LOOP_SLEEP', 'QDS_PERSIST_TASK_MAIN_LOOP_SLEEP'
        )
)
SELECT 
    wait_type AS WaitType,
    SUM(wait_time_s) AS WaitTimeSeconds,
    SUM(resource_wait_time_s) AS ResourceWaitTimeSeconds,
    SUM(signal_wait_time_s) AS SignalWaitTimeSeconds,
    SUM(waiting_tasks_count) AS WaitingTasksCount,
    AVG(percent_total_waits) AS PercentTotalWaits
FROM 
    Waits
GROUP BY 
    wait_type
ORDER BY 
    WaitTimeSeconds DESC;
