col "Time+Delta" for a15
col "Metric" for a75

col inst1 for 99999999999
col inst2 for 99999999999
col "SUM" for 99999999999

SELECT    TO_CHAR (MIN (begin_time), 'hh24:mi:ss')
         || ' /'
         || ROUND (AVG (intsize_csec / 100), 0)
         || 's'
            "Time+Delta",
         metric_name || ' - ' || metric_unit "Metric",
         SUM (value_inst1) inst1,
         SUM (value_inst2) inst2,
         SUM (value_inst2) + SUM (value_inst1) "SUM"
    FROM (SELECT begin_time,
                 intsize_csec,
                 metric_name,
                 metric_unit,
                 metric_id,
                 GROUP_ID,
                 CASE inst_id WHEN 1 THEN ROUND (VALUE, 1) END value_inst1,
                 CASE inst_id WHEN 2 THEN ROUND (VALUE, 1) END value_inst2,
                 CASE inst_id WHEN 3 THEN ROUND (VALUE, 1) END value_inst3,
                 CASE inst_id WHEN 4 THEN ROUND (VALUE, 1) END value_inst4,
                 CASE inst_id WHEN 5 THEN ROUND (VALUE, 1) END value_inst5,
                 CASE inst_id WHEN 6 THEN ROUND (VALUE, 1) END value_inst6
            FROM gv$sysmetric
           WHERE metric_name IN
                    ('Host CPU Utilization (%)',
                     'Current OS Load',
                     'Physical Write Total IO Requests Per Sec',
                     'Physical Write Total Bytes Per Sec',
                     'Physical Write IO Requests Per Sec',
                     'Physical Write Bytes Per Sec',
                     'I/O Requests per Second',
                     'I/O Megabytes per Second',
                     'Physical Read Total Bytes Per Sec',
                     'Physical Read Total IO Requests Per Sec',
                     'Physical Read IO Requests Per Sec',
                     'CPU Usage Per Sec',
                     'Network Traffic Volume Per Sec',
                     'Logons Per Sec',
                     'Redo Generated Per Sec',
                     'User Transaction Per Sec',
                     'Average Active Sessions',
                     'Average Synchronous Single-Block Read Latency',
                     'Logical Reads Per Sec',
                     'DB Block Changes Per Sec'))
GROUP BY metric_id,
         GROUP_ID,
         metric_name,
         metric_unit
ORDER BY metric_name;