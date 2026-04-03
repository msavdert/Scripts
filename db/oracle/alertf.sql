col alert_file format a100

select d.value||'/alert_'||i.instance_name||'.log' as alert_file
from v$diag_info d, v$instance i
where d.name = 'Diag Trace';