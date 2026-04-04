REM     Script:     recognize_oracle_db_arch.sql
REM     Purpose:    Summarize Oracle deployment topology and key database details.
REM                 Supports single instance, RAC, Data Guard visibility, CDB/PDB
REM                 awareness, and instance/database uptime reporting.
REM     Notes:      Run with a user that can query dynamic performance views.

SET SERVEROUTPUT ON SIZE UNLIMITED;

DECLARE
	c_sep CONSTANT VARCHAR2(79) := RPAD('*', 79, '*');

	l_service_names      VARCHAR2(4000);
	l_local_listener     VARCHAR2(4000);
	l_remote_listener    VARCHAR2(4000);
	l_listener_port      VARCHAR2(32);
	l_cluster_database   VARCHAR2(10);

	l_db_name            VARCHAR2(128);
	l_db_unique_name     VARCHAR2(128);
	l_dbid               NUMBER;
	l_platform_name      VARCHAR2(200);
	l_open_mode          VARCHAR2(40);
	l_log_mode           VARCHAR2(40);
	l_database_role      VARCHAR2(40);
	l_protection_mode    VARCHAR2(40);
	l_protection_level   VARCHAR2(40);
	l_switchover_status  VARCHAR2(40);
	l_flashback_on       VARCHAR2(10);
	l_force_logging      VARCHAR2(10);
	l_base_arch          VARCHAR2(30);
	l_architecture       VARCHAR2(60);
	l_dg_config          VARCHAR2(4000);
	l_cdb                VARCHAR2(10) := 'NO';
	l_instance_count     NUMBER := 0;
	l_dg_dest_count      NUMBER := 0;
	l_pdb_count          NUMBER := 0;
	l_oldest_startup     DATE;

	FUNCTION get_parameter(p_name IN VARCHAR2) RETURN VARCHAR2 IS
		l_value v$parameter.value%TYPE;
	BEGIN
		SELECT value
			INTO l_value
			FROM v$parameter
		 WHERE name = p_name;

		RETURN l_value;
	EXCEPTION
		WHEN NO_DATA_FOUND THEN
			RETURN NULL;
	END get_parameter;

	FUNCTION get_host_ip(p_host_name IN VARCHAR2) RETURN VARCHAR2 IS
	BEGIN
		RETURN utl_inaddr.get_host_address(p_host_name);
	EXCEPTION
		WHEN OTHERS THEN
			RETURN 'N/A';
	END get_host_ip;

	FUNCTION format_uptime(p_startup_time IN DATE) RETURN VARCHAR2 IS
		l_total_minutes NUMBER;
		l_days          NUMBER;
		l_hours         NUMBER;
		l_minutes       NUMBER;
	BEGIN
		IF p_startup_time IS NULL THEN
			RETURN 'N/A';
		END IF;

		l_total_minutes := FLOOR((SYSDATE - p_startup_time) * 24 * 60);
		l_days := FLOOR(l_total_minutes / 1440);
		l_hours := FLOOR(MOD(l_total_minutes, 1440) / 60);
		l_minutes := MOD(l_total_minutes, 60);

		RETURN l_days || 'd ' || LPAD(l_hours, 2, '0') || 'h ' || LPAD(l_minutes, 2, '0') || 'm';
	END format_uptime;

	PROCEDURE put_value(p_label IN VARCHAR2, p_value IN VARCHAR2) IS
	BEGIN
		DBMS_OUTPUT.PUT_LINE(RPAD(p_label, 36, ' ') || ': ' || NVL(p_value, 'N/A'));
	END put_value;

BEGIN
	l_service_names := get_parameter('service_names');
	l_local_listener := get_parameter('local_listener');
	l_remote_listener := get_parameter('remote_listener');
	l_cluster_database := UPPER(NVL(get_parameter('cluster_database'), 'FALSE'));
	l_dg_config := get_parameter('log_archive_config');
	l_listener_port := REGEXP_SUBSTR(l_local_listener, 'PORT=([0-9]+)', 1, 1, NULL, 1);

	SELECT name,
				 db_unique_name,
				 dbid,
				 platform_name,
				 open_mode,
				 log_mode,
				 database_role,
				 protection_mode,
				 protection_level,
				 switchover_status,
				 flashback_on,
				 force_logging
		INTO l_db_name,
				 l_db_unique_name,
				 l_dbid,
				 l_platform_name,
				 l_open_mode,
				 l_log_mode,
				 l_database_role,
				 l_protection_mode,
				 l_protection_level,
				 l_switchover_status,
				 l_flashback_on,
				 l_force_logging
		FROM v$database;

	SELECT COUNT(*), MIN(startup_time)
		INTO l_instance_count, l_oldest_startup
		FROM gv$instance;

	SELECT COUNT(*)
		INTO l_dg_dest_count
		FROM v$archive_dest
	 WHERE destination IS NOT NULL
		 AND target IN ('PRIMARY', 'STANDBY');

	IF l_cluster_database = 'TRUE' OR l_instance_count > 1 THEN
		l_base_arch := 'RAC';
	ELSE
		l_base_arch := 'Single Instance';
	END IF;

	IF l_database_role <> 'PRIMARY'
		 OR l_dg_dest_count > 0
		 OR UPPER(NVL(l_dg_config, '')) LIKE '%DG_CONFIG%' THEN
		l_architecture := l_base_arch || ' + Data Guard';
	ELSE
		l_architecture := l_base_arch;
	END IF;

	$IF DBMS_DB_VERSION.VERSION >= 12 $THEN
		SELECT cdb INTO l_cdb FROM v$database;
		SELECT COUNT(*) INTO l_pdb_count FROM v$pdbs WHERE con_id > 2;
	$END

	DBMS_OUTPUT.PUT_LINE(c_sep);
	put_value('Oracle Database Architecture', l_architecture);
	put_value('Oracle Database Name', l_db_name);
	put_value('Oracle Database Unique Name', l_db_unique_name);
	put_value('Oracle Database DBID', TO_CHAR(l_dbid));
	put_value('Oracle Database Platform Name', l_platform_name);
	put_value('Oracle Database Open Mode', l_open_mode);
	put_value('Oracle Database Log Mode', l_log_mode);
	put_value('Oracle Database Role', l_database_role);
	put_value('Oracle Database Protection Mode', l_protection_mode);
	put_value('Oracle Database Protection Level', l_protection_level);
	put_value('Oracle Database Switchover Status', l_switchover_status);
	put_value('Oracle Database Flashback', l_flashback_on);
	put_value('Oracle Database Force Logging', l_force_logging);
	put_value('Oracle Database Service Names', l_service_names);
	put_value('Oracle Database Local Listener', l_local_listener);
	put_value('Oracle Database Remote Listener', l_remote_listener);
	put_value('Oracle Database Listener Port', l_listener_port);
	put_value('Oracle Database DG Config', l_dg_config);
	put_value('Oracle Database Multitenant', l_cdb);
	IF l_cdb = 'YES' THEN
		put_value('Oracle Database PDB Count', TO_CHAR(l_pdb_count));
	END IF;
	put_value('Oracle Database Instance Count', TO_CHAR(l_instance_count));
	put_value('Database Startup Time (Oldest)', TO_CHAR(l_oldest_startup, 'YYYY-MM-DD HH24:MI:SS'));
	put_value('Database Uptime (Oldest)', format_uptime(l_oldest_startup));
	DBMS_OUTPUT.PUT_LINE(c_sep);

	$IF DBMS_DB_VERSION.VERSION >= 19 $THEN
		FOR cur_instance IN (
			SELECT inst_id,
						 instance_name,
						 host_name,
						 version,
						 version_full,
						 startup_time,
						 status,
						 parallel,
						 archiver,
						 thread#,
						 instance_role
				FROM gv$instance
			 ORDER BY inst_id
		)
		LOOP
			put_value('Oracle Instance ID', TO_CHAR(cur_instance.inst_id));
			put_value('Oracle Instance Name', cur_instance.instance_name);
			put_value('Oracle Instance Host Name', cur_instance.host_name);
			put_value('Oracle Instance IP Address', get_host_ip(cur_instance.host_name));
			put_value('Oracle Instance Version', NVL(cur_instance.version_full, cur_instance.version));
			put_value('Oracle Instance Status', cur_instance.status);
			put_value('Oracle Instance Role', cur_instance.instance_role);
			put_value('Oracle Instance Thread#', TO_CHAR(cur_instance.thread#));
			put_value('Oracle Instance Parallel', cur_instance.parallel);
			put_value('Oracle Instance Archiver', cur_instance.archiver);
			put_value('Oracle Instance Startup Time', TO_CHAR(cur_instance.startup_time, 'YYYY-MM-DD HH24:MI:SS'));
			put_value('Oracle Instance Uptime', format_uptime(cur_instance.startup_time));
			DBMS_OUTPUT.PUT_LINE(c_sep);
		END LOOP;
	$ELSE
		FOR cur_instance IN (
			SELECT inst_id,
						 instance_name,
						 host_name,
						 version,
						 startup_time,
						 status,
						 parallel,
						 archiver,
						 thread#,
						 instance_role
				FROM gv$instance
			 ORDER BY inst_id
		)
		LOOP
			put_value('Oracle Instance ID', TO_CHAR(cur_instance.inst_id));
			put_value('Oracle Instance Name', cur_instance.instance_name);
			put_value('Oracle Instance Host Name', cur_instance.host_name);
			put_value('Oracle Instance IP Address', get_host_ip(cur_instance.host_name));
			put_value('Oracle Instance Version', cur_instance.version);
			put_value('Oracle Instance Status', cur_instance.status);
			put_value('Oracle Instance Role', cur_instance.instance_role);
			put_value('Oracle Instance Thread#', TO_CHAR(cur_instance.thread#));
			put_value('Oracle Instance Parallel', cur_instance.parallel);
			put_value('Oracle Instance Archiver', cur_instance.archiver);
			put_value('Oracle Instance Startup Time', TO_CHAR(cur_instance.startup_time, 'YYYY-MM-DD HH24:MI:SS'));
			put_value('Oracle Instance Uptime', format_uptime(cur_instance.startup_time));
			DBMS_OUTPUT.PUT_LINE(c_sep);
		END LOOP;
	$END

	FOR cur_dest IN (
		SELECT dest_id,
					 target,
					 status,
					 db_unique_name,
					 destination,
					 error
			FROM v$archive_dest
		 WHERE destination IS NOT NULL
			 AND target IN ('PRIMARY', 'STANDBY')
		 ORDER BY dest_id
	)
	LOOP
		DBMS_OUTPUT.PUT_LINE(
			'Archive Destination ' || cur_dest.dest_id || ': ' ||
			'target=' || cur_dest.target ||
			', status=' || NVL(cur_dest.status, 'N/A') ||
			', db_unique_name=' || NVL(cur_dest.db_unique_name, 'N/A') ||
			', destination=' || cur_dest.destination ||
			CASE
				WHEN cur_dest.error IS NOT NULL THEN ', error=' || cur_dest.error
				ELSE NULL
			END
		);
	END LOOP;

	$IF DBMS_DB_VERSION.VERSION >= 12 $THEN
		IF l_cdb = 'YES' THEN
			DBMS_OUTPUT.PUT_LINE(c_sep);
			FOR cur_pdb IN (
				SELECT name,
							 open_mode,
							 restricted,
							 total_size
					FROM v$pdbs
				 WHERE con_id > 2
				 ORDER BY name
			)
			LOOP
				DBMS_OUTPUT.PUT_LINE(
					'PDB ' || RPAD(cur_pdb.name, 20, ' ') ||
					' open_mode=' || cur_pdb.open_mode ||
					', restricted=' || cur_pdb.restricted ||
					', total_size_mb=' || ROUND(cur_pdb.total_size / 1024 / 1024)
				);
			END LOOP;
			DBMS_OUTPUT.PUT_LINE(c_sep);
		END IF;
	$END
END;
/
