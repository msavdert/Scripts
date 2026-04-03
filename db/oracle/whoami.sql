declare
v_version number;
v_cdb varchar2(3);
begin
SELECT substr(version,0,2) into v_version FROM v$instance;
SELECT CDB into v_cdb FROM V$DATABASE;
dbms_output.put_line('USER: '||sys_context('userenv','session_user'));
dbms_output.put_line('SESSION ID: '||sys_context('userenv','sid'));
dbms_output.put_line('CURRENT_SCHEMA: '||sys_context('userenv','current_schema'));
dbms_output.put_line('INSTANCE NAME: '||sys_context('userenv','instance_name'));
if v_version >=  12 and v_cdb='YES' then
dbms_output.put_line('CDB NAME: '||sys_context('userenv','cdb_name'));
dbms_output.put_line('CONTAINER NAME: '||sys_context('userenv','con_name'));
end if;
dbms_output.put_line('DATABASE ROLE: '||sys_context('userenv','database_role'));
dbms_output.put_line('OS USER: '||sys_context('userenv','os_user'));
dbms_output.put_line('CLIENT IP ADDRESS: '||sys_context('userenv','ip_address'));
dbms_output.put_line('CLIENT HOSTNAME: '||sys_context('userenv','host'));
--dbms_output.put_line('SERVER IP ADDRESS: ' || UTL_INADDR.GET_HOST_ADDRESS);
dbms_output.put_line('SERVER HOSTNAME: '||sys_context('userenv','server_host'));
dbms_output.put_line('DATABASE VERSION: ' ||DBMS_DB_VERSION.VERSION || '.' || DBMS_DB_VERSION.RELEASE);
end;
/

set lines 200
set pages 200
col current_scn for 9999999999999999

select name, instance_name, open_mode, database_role, log_mode, flashback_on , current_scn from v$database,v$instance
/

set feedback on