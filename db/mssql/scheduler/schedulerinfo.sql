
SELECT
  sj.name AS [Job Name],
--  sj.[description] AS [Job Description], 
  SUSER_SNAME(sj.owner_sid) AS [Job Owner],
  sj.date_created AS [Date Created], sj.[enabled] AS [Job Enabled],
       CASE(s.freq_type)
            WHEN 1  THEN 'Once'
            WHEN 4  THEN 'Daily'
            WHEN 8  THEN (case when (s.freq_recurrence_factor > 1) then  'Every ' + convert(varchar(3),s.freq_recurrence_factor) + ' Weeks'  else 'Weekly'  end)
            WHEN 16 THEN (case when (s.freq_recurrence_factor > 1) then  'Every ' + convert(varchar(3),s.freq_recurrence_factor) + ' Months' else 'Monthly' end)
            WHEN 32 THEN 'Every ' + convert(varchar(3),s.freq_recurrence_factor) + ' Months' -- RELATIVE
            WHEN 64 THEN 'SQL Startup'
            WHEN 128 THEN 'SQL Idle'
            ELSE '??'
        END AS Frequency,
       CASE
            WHEN (freq_type = 1)                       then 'One time only'
            WHEN (freq_type = 4 and freq_interval = 1) then 'Every Day'
            WHEN (freq_type = 4 and freq_interval > 1) then 'Every ' + convert(varchar(10),freq_interval) + ' Days'
            WHEN (freq_type = 8) then (select 'Weekly Schedule' = MIN(D1+ D2+D3+D4+D5+D6+D7 )
                                        from (select SS.schedule_id,
                                                        freq_interval, 
                                                        'D1' = CASE WHEN (freq_interval & 1  <> 0) then 'Sun ' ELSE '' END,
                                                        'D2' = CASE WHEN (freq_interval & 2  <> 0) then 'Mon '  ELSE '' END,
                                                        'D3' = CASE WHEN (freq_interval & 4  <> 0) then 'Tue '  ELSE '' END,
                                                        'D4' = CASE WHEN (freq_interval & 8  <> 0) then 'Wed '  ELSE '' END,
                                                    'D5' = CASE WHEN (freq_interval & 16 <> 0) then 'Thu '  ELSE '' END,
                                                        'D6' = CASE WHEN (freq_interval & 32 <> 0) then 'Fri '  ELSE '' END,
                                                        'D7' = CASE WHEN (freq_interval & 64 <> 0) then 'Sat '  ELSE '' END
                                                    from msdb..sysschedules ss
                                                where freq_type = 8
                                            ) as F
                                        where schedule_id = js.schedule_id
                                    )
            WHEN (freq_type = 16) then 'Day ' + convert(varchar(2),freq_interval) 
            WHEN (freq_type = 32) then (select  freq_rel + WDAY 
                                        from (select SS.schedule_id,
                                                        'freq_rel' = CASE(freq_relative_interval)
                                                                    WHEN 1 then 'First'
                                                                    WHEN 2 then 'Second'
                                                                    WHEN 4 then 'Third'
                                                                    WHEN 8 then 'Fourth'
                                                                    WHEN 16 then 'Last'
                                                                    ELSE '??'
                                                                    END,
                                                    'WDAY'     = CASE (freq_interval)
                                                                    WHEN 1 then ' Sun'
                                                                    WHEN 2 then ' Mon'
                                                                    WHEN 3 then ' Tue'
                                                                    WHEN 4 then ' Wed'
                                                                    WHEN 5 then ' Thu'
                                                                    WHEN 6 then ' Fri'
                                                                    WHEN 7 then ' Sat'
                                                                    WHEN 8 then ' Day'
                                                                    WHEN 9 then ' Weekday'
                                                                    WHEN 10 then ' Weekend'
                                                                    ELSE '??'
                                                                    END
                                                from msdb..sysschedules SS
                                                where SS.freq_type = 32
                                                ) as WS 
                                        where WS.schedule_id = s.schedule_id
                                        ) 
        END AS Interval,
        CASE (freq_subday_type)
            WHEN 1 then   left(stuff((stuff((replicate('0', 6 - len(active_start_time)))+ convert(varchar(6),active_start_time),3,0,':')),6,0,':'),8)
            WHEN 2 then 'Every ' + convert(varchar(10),freq_subday_interval) + ' seconds'
            WHEN 4 then 'Every ' + convert(varchar(10),freq_subday_interval) + ' minutes'
            WHEN 8 then 'Every ' + convert(varchar(10),freq_subday_interval) + ' hours'
            ELSE '??'
        END AS [Time],
  sj.notify_email_operator_id, sj.notify_level_email, sc.name AS [CategoryName],
  s.[enabled] AS [Sched Enabled], js.next_run_date, js.next_run_time,
        LastRunOutcome = CASE (select top 1 jbh.run_status from msdb..sysjobhistory jbh where jbh.step_id = 0 and jbh.job_id = sj.job_id order by run_date desc) 
        when 0 then 'Failed' 
        when 1 then 'Succeeded' 
        when 2 then 'Retry' 
        when 3 then 'Canceled' 
        when 4 then 'In Progress' 
        else ''
        end
FROM msdb.dbo.sysjobs AS sj WITH (NOLOCK)
INNER JOIN msdb.dbo.syscategories AS sc WITH (NOLOCK)
ON sj.category_id = sc.category_id
LEFT OUTER JOIN msdb.dbo.sysjobschedules AS js WITH (NOLOCK)
ON sj.job_id = js.job_id
LEFT OUTER JOIN msdb.dbo.sysschedules AS s WITH (NOLOCK)
ON js.schedule_id = s.schedule_id
ORDER BY sj.name OPTION (RECOMPILE);
