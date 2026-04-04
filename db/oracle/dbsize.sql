REM     Script:     dbsize.sql
REM     Purpose:    Report Oracle database size breakdown with multitenant awareness.
REM                 If executed in CDB$ROOT, returns CDB/root/PDB totals, redo,
REM                 standby redo, controlfiles, per-container totals, tablespace
REM                 details, and AWR-based growth trends.
REM                 If executed inside a PDB, returns only the current PDB size
REM                 summary, local tablespace details, and local growth trend.

SET SERVEROUTPUT ON SIZE UNLIMITED
SET PAGESIZE 1000
SET LINESIZE 320
SET VERIFY OFF

COLUMN scope FORMAT A34
COLUMN container_name FORMAT A18
COLUMN open_mode FORMAT A12
COLUMN tablespace_name FORMAT A30
COLUMN contents FORMAT A12
COLUMN file_class FORMAT A8
COLUMN notes FORMAT A50
COLUMN current_size FORMAT A14
COLUMN max_size FORMAT A14
COLUMN used_size FORMAT A14
COLUMN free_size FORMAT A14
COLUMN perm_alloc_size FORMAT A14
COLUMN perm_used_size FORMAT A14
COLUMN perm_free_size FORMAT A14
COLUMN temp_alloc_size FORMAT A14
COLUMN total_alloc_size FORMAT A14
COLUMN total_max_size FORMAT A14
COLUMN current_used_size FORMAT A14
COLUMN current_alloc_size FORMAT A14
COLUMN used_growth_7d FORMAT A14
COLUMN used_growth_30d FORMAT A14
COLUMN alloc_growth_7d FORMAT A14
COLUMN alloc_growth_30d FORMAT A14
COLUMN usage_pct FORMAT 999,990.00

VAR dbsize_summary_rc REFCURSOR
VAR dbsize_container_rc REFCURSOR
VAR dbsize_tablespace_rc REFCURSOR
VAR dbsize_growth_rc REFCURSOR

DECLARE
  l_cdb        VARCHAR2(3);
  l_db_name    VARCHAR2(128);
  l_db_unique  VARCHAR2(128);
  l_con_id     NUMBER := TO_NUMBER(SYS_CONTEXT('USERENV', 'CON_ID'));
  l_con_name   VARCHAR2(128) := SYS_CONTEXT('USERENV', 'CON_NAME');
  l_mode_label VARCHAR2(30);

  PROCEDURE print_context IS
  BEGIN
    DBMS_OUTPUT.PUT_LINE(RPAD('*', 90, '*'));
    DBMS_OUTPUT.PUT_LINE('Database Name        : ' || l_db_name);
    DBMS_OUTPUT.PUT_LINE('Database Unique Name : ' || l_db_unique);
    DBMS_OUTPUT.PUT_LINE('CDB                  : ' || l_cdb);
    DBMS_OUTPUT.PUT_LINE('Current Container    : ' || l_con_name || ' (CON_ID=' || l_con_id || ')');
    DBMS_OUTPUT.PUT_LINE('Report Mode          : ' || l_mode_label);
    DBMS_OUTPUT.PUT_LINE(RPAD('*', 90, '*'));
  END print_context;

BEGIN
  SELECT cdb, name, db_unique_name
    INTO l_cdb, l_db_name, l_db_unique
    FROM v$database;

  IF l_cdb = 'YES' AND l_con_id = 1 THEN
    l_mode_label := 'CDB ROOT';
  ELSIF l_cdb = 'YES' THEN
    l_mode_label := 'PDB';
  ELSE
    l_mode_label := 'NON-CDB';
  END IF;

  print_context;

  IF l_cdb = 'YES' AND l_con_id = 1 THEN
    OPEN :dbsize_summary_rc FOR q'[
WITH data_files AS (
  SELECT con_id,
         COUNT(*) AS file_count,
         SUM(bytes) AS current_bytes,
         SUM(CASE WHEN autoextensible = 'YES' THEN GREATEST(maxbytes, bytes) ELSE bytes END) AS max_bytes
    FROM cdb_data_files
   GROUP BY con_id
),
temp_files AS (
  SELECT con_id,
         COUNT(*) AS file_count,
         SUM(bytes) AS current_bytes,
         SUM(CASE WHEN autoextensible = 'YES' THEN GREATEST(maxbytes, bytes) ELSE bytes END) AS max_bytes
    FROM cdb_temp_files
   GROUP BY con_id
),
perm_usage AS (
  SELECT m.con_id,
         SUM(m.used_space * t.block_size) AS used_bytes
    FROM cdb_tablespace_usage_metrics m
    JOIN cdb_tablespaces t
      ON t.con_id = m.con_id
     AND t.tablespace_name = m.tablespace_name
   GROUP BY m.con_id
),
container_sizes AS (
  SELECT c.con_id,
         c.name,
         c.open_mode,
         NVL(df.file_count, 0) AS datafile_count,
         NVL(tf.file_count, 0) AS tempfile_count,
         NVL(df.current_bytes, 0) AS perm_current_bytes,
         NVL(df.max_bytes, 0) AS perm_max_bytes,
         NVL(pu.used_bytes, 0) AS perm_used_bytes,
         GREATEST(NVL(df.current_bytes, 0) - NVL(pu.used_bytes, 0), 0) AS perm_free_bytes,
         NVL(tf.current_bytes, 0) AS temp_current_bytes,
         NVL(tf.max_bytes, 0) AS temp_max_bytes,
         NVL(df.current_bytes, 0) + NVL(tf.current_bytes, 0) AS total_current_bytes,
         NVL(df.max_bytes, 0) + NVL(tf.max_bytes, 0) AS total_max_bytes
    FROM v$containers c
    LEFT JOIN data_files df ON df.con_id = c.con_id
    LEFT JOIN temp_files tf ON tf.con_id = c.con_id
    LEFT JOIN perm_usage pu ON pu.con_id = c.con_id
),
base_summary AS (
  SELECT 10 AS sort_order,
         'Root only (CDB$ROOT)' AS scope,
         SUM(CASE WHEN con_id = 1 THEN total_current_bytes ELSE 0 END) AS current_bytes,
         SUM(CASE WHEN con_id = 1 THEN total_max_bytes ELSE 0 END) AS max_bytes,
         SUM(CASE WHEN con_id = 1 THEN perm_used_bytes ELSE 0 END) AS used_bytes,
         'Root container only' AS notes
    FROM container_sizes
  UNION ALL
  SELECT 20,
         'Seed only (PDB$SEED)',
         SUM(CASE WHEN con_id = 2 THEN total_current_bytes ELSE 0 END),
         SUM(CASE WHEN con_id = 2 THEN total_max_bytes ELSE 0 END),
         SUM(CASE WHEN con_id = 2 THEN perm_used_bytes ELSE 0 END),
         'PDB$SEED template'
    FROM container_sizes
  UNION ALL
  SELECT 30,
         'All user PDBs',
         SUM(CASE WHEN con_id > 2 THEN total_current_bytes ELSE 0 END),
         SUM(CASE WHEN con_id > 2 THEN total_max_bytes ELSE 0 END),
         SUM(CASE WHEN con_id > 2 THEN perm_used_bytes ELSE 0 END),
         'Sum of all PDBs except PDB$SEED'
    FROM container_sizes
  UNION ALL
  SELECT 40,
         'All containers',
         SUM(total_current_bytes),
         SUM(total_max_bytes),
         SUM(perm_used_bytes),
         'Root + PDB$SEED + all user PDBs'
    FROM container_sizes
),
infra_summary AS (
  SELECT 50 AS sort_order,
         'Redo logs' AS scope,
         NVL((SELECT SUM(bytes) FROM v$log), 0) AS current_bytes,
         NVL((SELECT SUM(bytes) FROM v$log), 0) AS max_bytes,
         CAST(NULL AS NUMBER) AS used_bytes,
         'Online redo logs' AS notes
    FROM dual
  UNION ALL
  SELECT 60,
         'Standby redo logs',
         NVL((SELECT SUM(bytes) FROM v$standby_log), 0),
         NVL((SELECT SUM(bytes) FROM v$standby_log), 0),
         CAST(NULL AS NUMBER),
         'Standby redo logs'
    FROM dual
  UNION ALL
  SELECT 70,
         'Controlfiles',
         NVL((SELECT SUM(block_size * file_size_blks) FROM v$controlfile), 0),
         NVL((SELECT SUM(block_size * file_size_blks) FROM v$controlfile), 0),
         CAST(NULL AS NUMBER),
         'Controlfile copies'
    FROM dual
),
grand_total AS (
  SELECT 80 AS sort_order,
         'Grand total' AS scope,
         NVL((SELECT current_bytes FROM base_summary WHERE scope = 'All containers'), 0)
         + NVL((SELECT current_bytes FROM infra_summary WHERE scope = 'Redo logs'), 0)
         + NVL((SELECT current_bytes FROM infra_summary WHERE scope = 'Standby redo logs'), 0)
         + NVL((SELECT current_bytes FROM infra_summary WHERE scope = 'Controlfiles'), 0) AS current_bytes,
         NVL((SELECT max_bytes FROM base_summary WHERE scope = 'All containers'), 0)
         + NVL((SELECT max_bytes FROM infra_summary WHERE scope = 'Redo logs'), 0)
         + NVL((SELECT max_bytes FROM infra_summary WHERE scope = 'Standby redo logs'), 0)
         + NVL((SELECT max_bytes FROM infra_summary WHERE scope = 'Controlfiles'), 0) AS max_bytes,
         NVL((SELECT used_bytes FROM base_summary WHERE scope = 'All containers'), 0) AS used_bytes,
         'Containers + redo + standby redo + controlfiles' AS notes
    FROM dual
),
combined AS (
  SELECT * FROM base_summary
  UNION ALL
  SELECT * FROM infra_summary
  UNION ALL
  SELECT * FROM grand_total
)
SELECT scope,
       CASE
         WHEN current_bytes IS NULL THEN NULL
         WHEN ABS(current_bytes) >= POWER(1024, 4) THEN TRIM(TO_CHAR(ROUND(current_bytes / POWER(1024, 4), 2), '999,999,999,990.00')) || ' TB'
         WHEN ABS(current_bytes) >= POWER(1024, 3) THEN TRIM(TO_CHAR(ROUND(current_bytes / POWER(1024, 3), 2), '999,999,999,990.00')) || ' GB'
         WHEN ABS(current_bytes) >= POWER(1024, 2) THEN TRIM(TO_CHAR(ROUND(current_bytes / POWER(1024, 2), 2), '999,999,999,990.00')) || ' MB'
         ELSE TRIM(TO_CHAR(ROUND(current_bytes / 1024, 2), '999,999,999,990.00')) || ' KB'
       END AS current_size,
       CASE
         WHEN max_bytes IS NULL THEN NULL
         WHEN ABS(max_bytes) >= POWER(1024, 4) THEN TRIM(TO_CHAR(ROUND(max_bytes / POWER(1024, 4), 2), '999,999,999,990.00')) || ' TB'
         WHEN ABS(max_bytes) >= POWER(1024, 3) THEN TRIM(TO_CHAR(ROUND(max_bytes / POWER(1024, 3), 2), '999,999,999,990.00')) || ' GB'
         WHEN ABS(max_bytes) >= POWER(1024, 2) THEN TRIM(TO_CHAR(ROUND(max_bytes / POWER(1024, 2), 2), '999,999,999,990.00')) || ' MB'
         ELSE TRIM(TO_CHAR(ROUND(max_bytes / 1024, 2), '999,999,999,990.00')) || ' KB'
       END AS max_size,
       CASE
         WHEN used_bytes IS NULL THEN NULL
         WHEN ABS(used_bytes) >= POWER(1024, 4) THEN TRIM(TO_CHAR(ROUND(used_bytes / POWER(1024, 4), 2), '999,999,999,990.00')) || ' TB'
         WHEN ABS(used_bytes) >= POWER(1024, 3) THEN TRIM(TO_CHAR(ROUND(used_bytes / POWER(1024, 3), 2), '999,999,999,990.00')) || ' GB'
         WHEN ABS(used_bytes) >= POWER(1024, 2) THEN TRIM(TO_CHAR(ROUND(used_bytes / POWER(1024, 2), 2), '999,999,999,990.00')) || ' MB'
         ELSE TRIM(TO_CHAR(ROUND(used_bytes / 1024, 2), '999,999,999,990.00')) || ' KB'
       END AS used_size,
       CASE
         WHEN used_bytes IS NULL THEN NULL
         WHEN ABS(GREATEST(current_bytes - used_bytes, 0)) >= POWER(1024, 4) THEN TRIM(TO_CHAR(ROUND(GREATEST(current_bytes - used_bytes, 0) / POWER(1024, 4), 2), '999,999,999,990.00')) || ' TB'
         WHEN ABS(GREATEST(current_bytes - used_bytes, 0)) >= POWER(1024, 3) THEN TRIM(TO_CHAR(ROUND(GREATEST(current_bytes - used_bytes, 0) / POWER(1024, 3), 2), '999,999,999,990.00')) || ' GB'
         WHEN ABS(GREATEST(current_bytes - used_bytes, 0)) >= POWER(1024, 2) THEN TRIM(TO_CHAR(ROUND(GREATEST(current_bytes - used_bytes, 0) / POWER(1024, 2), 2), '999,999,999,990.00')) || ' MB'
         ELSE TRIM(TO_CHAR(ROUND(GREATEST(current_bytes - used_bytes, 0) / 1024, 2), '999,999,999,990.00')) || ' KB'
       END AS free_size,
       notes
  FROM combined
 ORDER BY sort_order
]';

    OPEN :dbsize_container_rc FOR q'[
WITH data_files AS (
  SELECT con_id,
         COUNT(*) AS datafile_count,
         SUM(bytes) AS perm_current_bytes,
         SUM(CASE WHEN autoextensible = 'YES' THEN GREATEST(maxbytes, bytes) ELSE bytes END) AS perm_max_bytes
    FROM cdb_data_files
   GROUP BY con_id
),
temp_files AS (
  SELECT con_id,
         COUNT(*) AS tempfile_count,
         SUM(bytes) AS temp_current_bytes,
         SUM(CASE WHEN autoextensible = 'YES' THEN GREATEST(maxbytes, bytes) ELSE bytes END) AS temp_max_bytes
    FROM cdb_temp_files
   GROUP BY con_id
),
perm_usage AS (
  SELECT m.con_id,
         SUM(m.used_space * t.block_size) AS perm_used_bytes
    FROM cdb_tablespace_usage_metrics m
    JOIN cdb_tablespaces t
      ON t.con_id = m.con_id
     AND t.tablespace_name = m.tablespace_name
   GROUP BY m.con_id
)
SELECT c.con_id,
       c.name AS container_name,
       c.open_mode,
       NVL(df.datafile_count, 0) AS datafiles,
       NVL(tf.tempfile_count, 0) AS tempfiles,
       CASE
         WHEN NVL(df.perm_current_bytes, 0) >= POWER(1024, 4) THEN TRIM(TO_CHAR(ROUND(NVL(df.perm_current_bytes, 0) / POWER(1024, 4), 2), '999,999,999,990.00')) || ' TB'
         WHEN NVL(df.perm_current_bytes, 0) >= POWER(1024, 3) THEN TRIM(TO_CHAR(ROUND(NVL(df.perm_current_bytes, 0) / POWER(1024, 3), 2), '999,999,999,990.00')) || ' GB'
         WHEN NVL(df.perm_current_bytes, 0) >= POWER(1024, 2) THEN TRIM(TO_CHAR(ROUND(NVL(df.perm_current_bytes, 0) / POWER(1024, 2), 2), '999,999,999,990.00')) || ' MB'
         ELSE TRIM(TO_CHAR(ROUND(NVL(df.perm_current_bytes, 0) / 1024, 2), '999,999,999,990.00')) || ' KB'
       END AS perm_alloc_size,
       CASE
         WHEN NVL(pu.perm_used_bytes, 0) >= POWER(1024, 4) THEN TRIM(TO_CHAR(ROUND(NVL(pu.perm_used_bytes, 0) / POWER(1024, 4), 2), '999,999,999,990.00')) || ' TB'
         WHEN NVL(pu.perm_used_bytes, 0) >= POWER(1024, 3) THEN TRIM(TO_CHAR(ROUND(NVL(pu.perm_used_bytes, 0) / POWER(1024, 3), 2), '999,999,999,990.00')) || ' GB'
         WHEN NVL(pu.perm_used_bytes, 0) >= POWER(1024, 2) THEN TRIM(TO_CHAR(ROUND(NVL(pu.perm_used_bytes, 0) / POWER(1024, 2), 2), '999,999,999,990.00')) || ' MB'
         ELSE TRIM(TO_CHAR(ROUND(NVL(pu.perm_used_bytes, 0) / 1024, 2), '999,999,999,990.00')) || ' KB'
       END AS perm_used_size,
       CASE
         WHEN GREATEST(NVL(df.perm_current_bytes, 0) - NVL(pu.perm_used_bytes, 0), 0) >= POWER(1024, 4) THEN TRIM(TO_CHAR(ROUND(GREATEST(NVL(df.perm_current_bytes, 0) - NVL(pu.perm_used_bytes, 0), 0) / POWER(1024, 4), 2), '999,999,999,990.00')) || ' TB'
         WHEN GREATEST(NVL(df.perm_current_bytes, 0) - NVL(pu.perm_used_bytes, 0), 0) >= POWER(1024, 3) THEN TRIM(TO_CHAR(ROUND(GREATEST(NVL(df.perm_current_bytes, 0) - NVL(pu.perm_used_bytes, 0), 0) / POWER(1024, 3), 2), '999,999,999,990.00')) || ' GB'
         WHEN GREATEST(NVL(df.perm_current_bytes, 0) - NVL(pu.perm_used_bytes, 0), 0) >= POWER(1024, 2) THEN TRIM(TO_CHAR(ROUND(GREATEST(NVL(df.perm_current_bytes, 0) - NVL(pu.perm_used_bytes, 0), 0) / POWER(1024, 2), 2), '999,999,999,990.00')) || ' MB'
         ELSE TRIM(TO_CHAR(ROUND(GREATEST(NVL(df.perm_current_bytes, 0) - NVL(pu.perm_used_bytes, 0), 0) / 1024, 2), '999,999,999,990.00')) || ' KB'
       END AS perm_free_size,
       CASE
         WHEN NVL(tf.temp_current_bytes, 0) >= POWER(1024, 4) THEN TRIM(TO_CHAR(ROUND(NVL(tf.temp_current_bytes, 0) / POWER(1024, 4), 2), '999,999,999,990.00')) || ' TB'
         WHEN NVL(tf.temp_current_bytes, 0) >= POWER(1024, 3) THEN TRIM(TO_CHAR(ROUND(NVL(tf.temp_current_bytes, 0) / POWER(1024, 3), 2), '999,999,999,990.00')) || ' GB'
         WHEN NVL(tf.temp_current_bytes, 0) >= POWER(1024, 2) THEN TRIM(TO_CHAR(ROUND(NVL(tf.temp_current_bytes, 0) / POWER(1024, 2), 2), '999,999,999,990.00')) || ' MB'
         ELSE TRIM(TO_CHAR(ROUND(NVL(tf.temp_current_bytes, 0) / 1024, 2), '999,999,999,990.00')) || ' KB'
       END AS temp_alloc_size,
       CASE
         WHEN (NVL(df.perm_current_bytes, 0) + NVL(tf.temp_current_bytes, 0)) >= POWER(1024, 4) THEN TRIM(TO_CHAR(ROUND((NVL(df.perm_current_bytes, 0) + NVL(tf.temp_current_bytes, 0)) / POWER(1024, 4), 2), '999,999,999,990.00')) || ' TB'
         WHEN (NVL(df.perm_current_bytes, 0) + NVL(tf.temp_current_bytes, 0)) >= POWER(1024, 3) THEN TRIM(TO_CHAR(ROUND((NVL(df.perm_current_bytes, 0) + NVL(tf.temp_current_bytes, 0)) / POWER(1024, 3), 2), '999,999,999,990.00')) || ' GB'
         WHEN (NVL(df.perm_current_bytes, 0) + NVL(tf.temp_current_bytes, 0)) >= POWER(1024, 2) THEN TRIM(TO_CHAR(ROUND((NVL(df.perm_current_bytes, 0) + NVL(tf.temp_current_bytes, 0)) / POWER(1024, 2), 2), '999,999,999,990.00')) || ' MB'
         ELSE TRIM(TO_CHAR(ROUND((NVL(df.perm_current_bytes, 0) + NVL(tf.temp_current_bytes, 0)) / 1024, 2), '999,999,999,990.00')) || ' KB'
       END AS total_alloc_size,
       CASE
         WHEN (NVL(df.perm_max_bytes, 0) + NVL(tf.temp_max_bytes, 0)) >= POWER(1024, 4) THEN TRIM(TO_CHAR(ROUND((NVL(df.perm_max_bytes, 0) + NVL(tf.temp_max_bytes, 0)) / POWER(1024, 4), 2), '999,999,999,990.00')) || ' TB'
         WHEN (NVL(df.perm_max_bytes, 0) + NVL(tf.temp_max_bytes, 0)) >= POWER(1024, 3) THEN TRIM(TO_CHAR(ROUND((NVL(df.perm_max_bytes, 0) + NVL(tf.temp_max_bytes, 0)) / POWER(1024, 3), 2), '999,999,999,990.00')) || ' GB'
         WHEN (NVL(df.perm_max_bytes, 0) + NVL(tf.temp_max_bytes, 0)) >= POWER(1024, 2) THEN TRIM(TO_CHAR(ROUND((NVL(df.perm_max_bytes, 0) + NVL(tf.temp_max_bytes, 0)) / POWER(1024, 2), 2), '999,999,999,990.00')) || ' MB'
         ELSE TRIM(TO_CHAR(ROUND((NVL(df.perm_max_bytes, 0) + NVL(tf.temp_max_bytes, 0)) / 1024, 2), '999,999,999,990.00')) || ' KB'
       END AS total_max_size
  FROM v$containers c
  LEFT JOIN data_files df ON df.con_id = c.con_id
  LEFT JOIN temp_files tf ON tf.con_id = c.con_id
  LEFT JOIN perm_usage pu ON pu.con_id = c.con_id
 ORDER BY c.con_id
]';

    OPEN :dbsize_tablespace_rc FOR q'[
WITH file_sizes AS (
  SELECT con_id,
         tablespace_name,
         'DATA' AS file_class,
         SUM(bytes) AS current_bytes,
         SUM(CASE WHEN autoextensible = 'YES' THEN GREATEST(maxbytes, bytes) ELSE bytes END) AS max_bytes,
         COUNT(*) AS file_count
    FROM cdb_data_files
   GROUP BY con_id, tablespace_name
  UNION ALL
  SELECT con_id,
         tablespace_name,
         'TEMP' AS file_class,
         SUM(bytes) AS current_bytes,
         SUM(CASE WHEN autoextensible = 'YES' THEN GREATEST(maxbytes, bytes) ELSE bytes END) AS max_bytes,
         COUNT(*) AS file_count
    FROM cdb_temp_files
   GROUP BY con_id, tablespace_name
),
ts_usage AS (
  SELECT m.con_id,
         m.tablespace_name,
         SUM(m.used_space * t.block_size) AS used_bytes,
         SUM((m.tablespace_size - m.used_space) * t.block_size) AS free_bytes,
         MAX(m.used_percent) AS usage_pct
    FROM cdb_tablespace_usage_metrics m
    JOIN cdb_tablespaces t
      ON t.con_id = m.con_id
     AND t.tablespace_name = m.tablespace_name
   GROUP BY m.con_id, m.tablespace_name
)
SELECT c.name AS container_name,
       f.tablespace_name,
       t.contents,
       f.file_class,
       f.file_count,
       CASE
         WHEN f.current_bytes >= POWER(1024, 4) THEN TRIM(TO_CHAR(ROUND(f.current_bytes / POWER(1024, 4), 2), '999,999,999,990.00')) || ' TB'
         WHEN f.current_bytes >= POWER(1024, 3) THEN TRIM(TO_CHAR(ROUND(f.current_bytes / POWER(1024, 3), 2), '999,999,999,990.00')) || ' GB'
         WHEN f.current_bytes >= POWER(1024, 2) THEN TRIM(TO_CHAR(ROUND(f.current_bytes / POWER(1024, 2), 2), '999,999,999,990.00')) || ' MB'
         ELSE TRIM(TO_CHAR(ROUND(f.current_bytes / 1024, 2), '999,999,999,990.00')) || ' KB'
       END AS current_size,
       CASE
         WHEN NVL(u.used_bytes, 0) >= POWER(1024, 4) THEN TRIM(TO_CHAR(ROUND(NVL(u.used_bytes, 0) / POWER(1024, 4), 2), '999,999,999,990.00')) || ' TB'
         WHEN NVL(u.used_bytes, 0) >= POWER(1024, 3) THEN TRIM(TO_CHAR(ROUND(NVL(u.used_bytes, 0) / POWER(1024, 3), 2), '999,999,999,990.00')) || ' GB'
         WHEN NVL(u.used_bytes, 0) >= POWER(1024, 2) THEN TRIM(TO_CHAR(ROUND(NVL(u.used_bytes, 0) / POWER(1024, 2), 2), '999,999,999,990.00')) || ' MB'
         ELSE TRIM(TO_CHAR(ROUND(NVL(u.used_bytes, 0) / 1024, 2), '999,999,999,990.00')) || ' KB'
       END AS used_size,
       CASE
         WHEN GREATEST(f.current_bytes - NVL(u.used_bytes, 0), 0) >= POWER(1024, 4) THEN TRIM(TO_CHAR(ROUND(GREATEST(f.current_bytes - NVL(u.used_bytes, 0), 0) / POWER(1024, 4), 2), '999,999,999,990.00')) || ' TB'
         WHEN GREATEST(f.current_bytes - NVL(u.used_bytes, 0), 0) >= POWER(1024, 3) THEN TRIM(TO_CHAR(ROUND(GREATEST(f.current_bytes - NVL(u.used_bytes, 0), 0) / POWER(1024, 3), 2), '999,999,999,990.00')) || ' GB'
         WHEN GREATEST(f.current_bytes - NVL(u.used_bytes, 0), 0) >= POWER(1024, 2) THEN TRIM(TO_CHAR(ROUND(GREATEST(f.current_bytes - NVL(u.used_bytes, 0), 0) / POWER(1024, 2), 2), '999,999,999,990.00')) || ' MB'
         ELSE TRIM(TO_CHAR(ROUND(GREATEST(f.current_bytes - NVL(u.used_bytes, 0), 0) / 1024, 2), '999,999,999,990.00')) || ' KB'
       END AS free_size,
       CASE
         WHEN f.max_bytes >= POWER(1024, 4) THEN TRIM(TO_CHAR(ROUND(f.max_bytes / POWER(1024, 4), 2), '999,999,999,990.00')) || ' TB'
         WHEN f.max_bytes >= POWER(1024, 3) THEN TRIM(TO_CHAR(ROUND(f.max_bytes / POWER(1024, 3), 2), '999,999,999,990.00')) || ' GB'
         WHEN f.max_bytes >= POWER(1024, 2) THEN TRIM(TO_CHAR(ROUND(f.max_bytes / POWER(1024, 2), 2), '999,999,999,990.00')) || ' MB'
         ELSE TRIM(TO_CHAR(ROUND(f.max_bytes / 1024, 2), '999,999,999,990.00')) || ' KB'
       END AS max_size,
       ROUND(u.usage_pct, 2) AS usage_pct
  FROM file_sizes f
  JOIN cdb_tablespaces t
    ON t.con_id = f.con_id
   AND t.tablespace_name = f.tablespace_name
  JOIN v$containers c
    ON c.con_id = f.con_id
  LEFT JOIN ts_usage u
    ON u.con_id = f.con_id
   AND u.tablespace_name = f.tablespace_name
 ORDER BY c.con_id, f.current_bytes DESC, f.tablespace_name
]';

    OPEN :dbsize_growth_rc FOR q'[
WITH snapshots AS (
  SELECT dbid,
         snap_id,
         MIN(begin_interval_time) AS begin_interval_time
    FROM dba_hist_snapshot
   GROUP BY dbid, snap_id
),
hist_raw AS (
  SELECT h.con_id,
         sn.begin_interval_time,
         SUM(h.tablespace_size * t.block_size) AS alloc_bytes,
         SUM(h.tablespace_usedsize * t.block_size) AS used_bytes
    FROM cdb_hist_tbspc_space_usage h
    JOIN snapshots sn
      ON sn.dbid = h.dbid
     AND sn.snap_id = h.snap_id
    JOIN v$tablespace vt
      ON vt.con_id = h.con_id
     AND vt.ts# = h.tablespace_id
    JOIN cdb_tablespaces t
      ON t.con_id = vt.con_id
     AND t.tablespace_name = vt.name
   GROUP BY h.con_id, sn.begin_interval_time
),
curr AS (
  SELECT con_id, alloc_bytes, used_bytes
    FROM (
          SELECT con_id,
                 alloc_bytes,
                 used_bytes,
                 ROW_NUMBER() OVER (PARTITION BY con_id ORDER BY begin_interval_time DESC) AS rn
            FROM hist_raw
         )
   WHERE rn = 1
),
d7 AS (
  SELECT con_id, alloc_bytes, used_bytes
    FROM (
          SELECT con_id,
                 alloc_bytes,
                 used_bytes,
                 ROW_NUMBER() OVER (PARTITION BY con_id ORDER BY begin_interval_time ASC) AS rn
            FROM hist_raw
           WHERE begin_interval_time >= SYSDATE - 7
         )
   WHERE rn = 1
),
d30 AS (
  SELECT con_id, alloc_bytes, used_bytes
    FROM (
          SELECT con_id,
                 alloc_bytes,
                 used_bytes,
                 ROW_NUMBER() OVER (PARTITION BY con_id ORDER BY begin_interval_time ASC) AS rn
            FROM hist_raw
           WHERE begin_interval_time >= SYSDATE - 30
         )
   WHERE rn = 1
)
SELECT c.name AS container_name,
       CASE
         WHEN curr.used_bytes IS NULL THEN NULL
         WHEN curr.used_bytes >= POWER(1024, 4) THEN TRIM(TO_CHAR(ROUND(curr.used_bytes / POWER(1024, 4), 2), '999,999,999,990.00')) || ' TB'
         WHEN curr.used_bytes >= POWER(1024, 3) THEN TRIM(TO_CHAR(ROUND(curr.used_bytes / POWER(1024, 3), 2), '999,999,999,990.00')) || ' GB'
         WHEN curr.used_bytes >= POWER(1024, 2) THEN TRIM(TO_CHAR(ROUND(curr.used_bytes / POWER(1024, 2), 2), '999,999,999,990.00')) || ' MB'
         ELSE TRIM(TO_CHAR(ROUND(curr.used_bytes / 1024, 2), '999,999,999,990.00')) || ' KB'
       END AS current_used_size,
       CASE
         WHEN d7.used_bytes IS NULL THEN NULL
         WHEN ABS(curr.used_bytes - d7.used_bytes) >= POWER(1024, 4) THEN TRIM(TO_CHAR(ROUND((curr.used_bytes - d7.used_bytes) / POWER(1024, 4), 2), '999,999,999,990.00')) || ' TB'
         WHEN ABS(curr.used_bytes - d7.used_bytes) >= POWER(1024, 3) THEN TRIM(TO_CHAR(ROUND((curr.used_bytes - d7.used_bytes) / POWER(1024, 3), 2), '999,999,999,990.00')) || ' GB'
         WHEN ABS(curr.used_bytes - d7.used_bytes) >= POWER(1024, 2) THEN TRIM(TO_CHAR(ROUND((curr.used_bytes - d7.used_bytes) / POWER(1024, 2), 2), '999,999,999,990.00')) || ' MB'
         ELSE TRIM(TO_CHAR(ROUND((curr.used_bytes - d7.used_bytes) / 1024, 2), '999,999,999,990.00')) || ' KB'
       END AS used_growth_7d,
       CASE
         WHEN d30.used_bytes IS NULL THEN NULL
         WHEN ABS(curr.used_bytes - d30.used_bytes) >= POWER(1024, 4) THEN TRIM(TO_CHAR(ROUND((curr.used_bytes - d30.used_bytes) / POWER(1024, 4), 2), '999,999,999,990.00')) || ' TB'
         WHEN ABS(curr.used_bytes - d30.used_bytes) >= POWER(1024, 3) THEN TRIM(TO_CHAR(ROUND((curr.used_bytes - d30.used_bytes) / POWER(1024, 3), 2), '999,999,999,990.00')) || ' GB'
         WHEN ABS(curr.used_bytes - d30.used_bytes) >= POWER(1024, 2) THEN TRIM(TO_CHAR(ROUND((curr.used_bytes - d30.used_bytes) / POWER(1024, 2), 2), '999,999,999,990.00')) || ' MB'
         ELSE TRIM(TO_CHAR(ROUND((curr.used_bytes - d30.used_bytes) / 1024, 2), '999,999,999,990.00')) || ' KB'
       END AS used_growth_30d,
       CASE
         WHEN curr.alloc_bytes IS NULL THEN NULL
         WHEN curr.alloc_bytes >= POWER(1024, 4) THEN TRIM(TO_CHAR(ROUND(curr.alloc_bytes / POWER(1024, 4), 2), '999,999,999,990.00')) || ' TB'
         WHEN curr.alloc_bytes >= POWER(1024, 3) THEN TRIM(TO_CHAR(ROUND(curr.alloc_bytes / POWER(1024, 3), 2), '999,999,999,990.00')) || ' GB'
         WHEN curr.alloc_bytes >= POWER(1024, 2) THEN TRIM(TO_CHAR(ROUND(curr.alloc_bytes / POWER(1024, 2), 2), '999,999,999,990.00')) || ' MB'
         ELSE TRIM(TO_CHAR(ROUND(curr.alloc_bytes / 1024, 2), '999,999,999,990.00')) || ' KB'
       END AS current_alloc_size,
       CASE
         WHEN d7.alloc_bytes IS NULL THEN NULL
         WHEN ABS(curr.alloc_bytes - d7.alloc_bytes) >= POWER(1024, 4) THEN TRIM(TO_CHAR(ROUND((curr.alloc_bytes - d7.alloc_bytes) / POWER(1024, 4), 2), '999,999,999,990.00')) || ' TB'
         WHEN ABS(curr.alloc_bytes - d7.alloc_bytes) >= POWER(1024, 3) THEN TRIM(TO_CHAR(ROUND((curr.alloc_bytes - d7.alloc_bytes) / POWER(1024, 3), 2), '999,999,999,990.00')) || ' GB'
         WHEN ABS(curr.alloc_bytes - d7.alloc_bytes) >= POWER(1024, 2) THEN TRIM(TO_CHAR(ROUND((curr.alloc_bytes - d7.alloc_bytes) / POWER(1024, 2), 2), '999,999,999,990.00')) || ' MB'
         ELSE TRIM(TO_CHAR(ROUND((curr.alloc_bytes - d7.alloc_bytes) / 1024, 2), '999,999,999,990.00')) || ' KB'
       END AS alloc_growth_7d,
       CASE
         WHEN d30.alloc_bytes IS NULL THEN NULL
         WHEN ABS(curr.alloc_bytes - d30.alloc_bytes) >= POWER(1024, 4) THEN TRIM(TO_CHAR(ROUND((curr.alloc_bytes - d30.alloc_bytes) / POWER(1024, 4), 2), '999,999,999,990.00')) || ' TB'
         WHEN ABS(curr.alloc_bytes - d30.alloc_bytes) >= POWER(1024, 3) THEN TRIM(TO_CHAR(ROUND((curr.alloc_bytes - d30.alloc_bytes) / POWER(1024, 3), 2), '999,999,999,990.00')) || ' GB'
         WHEN ABS(curr.alloc_bytes - d30.alloc_bytes) >= POWER(1024, 2) THEN TRIM(TO_CHAR(ROUND((curr.alloc_bytes - d30.alloc_bytes) / POWER(1024, 2), 2), '999,999,999,990.00')) || ' MB'
         ELSE TRIM(TO_CHAR(ROUND((curr.alloc_bytes - d30.alloc_bytes) / 1024, 2), '999,999,999,990.00')) || ' KB'
       END AS alloc_growth_30d,
       'Earliest AWR snapshot inside 7d/30d windows' AS notes
  FROM curr
  JOIN v$containers c
    ON c.con_id = curr.con_id
  LEFT JOIN d7
    ON d7.con_id = curr.con_id
  LEFT JOIN d30
    ON d30.con_id = curr.con_id
 ORDER BY curr.con_id
]';

  ELSIF l_cdb = 'YES' THEN
    OPEN :dbsize_summary_rc FOR q'[
WITH data_files AS (
  SELECT COUNT(*) AS file_count,
         SUM(bytes) AS current_bytes,
         SUM(CASE WHEN autoextensible = 'YES' THEN GREATEST(maxbytes, bytes) ELSE bytes END) AS max_bytes
    FROM dba_data_files
),
temp_files AS (
  SELECT COUNT(*) AS file_count,
         SUM(bytes) AS current_bytes,
         SUM(CASE WHEN autoextensible = 'YES' THEN GREATEST(maxbytes, bytes) ELSE bytes END) AS max_bytes
    FROM dba_temp_files
),
perm_usage AS (
  SELECT SUM(m.used_space * t.block_size) AS used_bytes
    FROM dba_tablespace_usage_metrics m
    JOIN dba_tablespaces t
      ON t.tablespace_name = m.tablespace_name
)
SELECT scope,
       CASE
         WHEN current_bytes IS NULL THEN NULL
         WHEN ABS(current_bytes) >= POWER(1024, 4) THEN TRIM(TO_CHAR(ROUND(current_bytes / POWER(1024, 4), 2), '999,999,999,990.00')) || ' TB'
         WHEN ABS(current_bytes) >= POWER(1024, 3) THEN TRIM(TO_CHAR(ROUND(current_bytes / POWER(1024, 3), 2), '999,999,999,990.00')) || ' GB'
         WHEN ABS(current_bytes) >= POWER(1024, 2) THEN TRIM(TO_CHAR(ROUND(current_bytes / POWER(1024, 2), 2), '999,999,999,990.00')) || ' MB'
         ELSE TRIM(TO_CHAR(ROUND(current_bytes / 1024, 2), '999,999,999,990.00')) || ' KB'
       END AS current_size,
       CASE
         WHEN max_bytes IS NULL THEN NULL
         WHEN ABS(max_bytes) >= POWER(1024, 4) THEN TRIM(TO_CHAR(ROUND(max_bytes / POWER(1024, 4), 2), '999,999,999,990.00')) || ' TB'
         WHEN ABS(max_bytes) >= POWER(1024, 3) THEN TRIM(TO_CHAR(ROUND(max_bytes / POWER(1024, 3), 2), '999,999,999,990.00')) || ' GB'
         WHEN ABS(max_bytes) >= POWER(1024, 2) THEN TRIM(TO_CHAR(ROUND(max_bytes / POWER(1024, 2), 2), '999,999,999,990.00')) || ' MB'
         ELSE TRIM(TO_CHAR(ROUND(max_bytes / 1024, 2), '999,999,999,990.00')) || ' KB'
       END AS max_size,
       CASE
         WHEN used_bytes IS NULL THEN NULL
         WHEN ABS(used_bytes) >= POWER(1024, 4) THEN TRIM(TO_CHAR(ROUND(used_bytes / POWER(1024, 4), 2), '999,999,999,990.00')) || ' TB'
         WHEN ABS(used_bytes) >= POWER(1024, 3) THEN TRIM(TO_CHAR(ROUND(used_bytes / POWER(1024, 3), 2), '999,999,999,990.00')) || ' GB'
         WHEN ABS(used_bytes) >= POWER(1024, 2) THEN TRIM(TO_CHAR(ROUND(used_bytes / POWER(1024, 2), 2), '999,999,999,990.00')) || ' MB'
         ELSE TRIM(TO_CHAR(ROUND(used_bytes / 1024, 2), '999,999,999,990.00')) || ' KB'
       END AS used_size,
       CASE
         WHEN used_bytes IS NULL THEN NULL
         WHEN ABS(GREATEST(current_bytes - used_bytes, 0)) >= POWER(1024, 4) THEN TRIM(TO_CHAR(ROUND(GREATEST(current_bytes - used_bytes, 0) / POWER(1024, 4), 2), '999,999,999,990.00')) || ' TB'
         WHEN ABS(GREATEST(current_bytes - used_bytes, 0)) >= POWER(1024, 3) THEN TRIM(TO_CHAR(ROUND(GREATEST(current_bytes - used_bytes, 0) / POWER(1024, 3), 2), '999,999,999,990.00')) || ' GB'
         WHEN ABS(GREATEST(current_bytes - used_bytes, 0)) >= POWER(1024, 2) THEN TRIM(TO_CHAR(ROUND(GREATEST(current_bytes - used_bytes, 0) / POWER(1024, 2), 2), '999,999,999,990.00')) || ' MB'
         ELSE TRIM(TO_CHAR(ROUND(GREATEST(current_bytes - used_bytes, 0) / 1024, 2), '999,999,999,990.00')) || ' KB'
       END AS free_size,
       notes
  FROM (
        SELECT 10 AS sort_order,
               'Current PDB permanent' AS scope,
               NVL((SELECT current_bytes FROM data_files), 0) AS current_bytes,
               NVL((SELECT max_bytes FROM data_files), 0) AS max_bytes,
               NVL((SELECT used_bytes FROM perm_usage), 0) AS used_bytes,
               TO_CHAR(NVL((SELECT file_count FROM data_files), 0)) || ' datafiles' AS notes
          FROM dual
        UNION ALL
        SELECT 20,
               'Current PDB temp',
               NVL((SELECT current_bytes FROM temp_files), 0),
               NVL((SELECT max_bytes FROM temp_files), 0),
               CAST(NULL AS NUMBER),
               TO_CHAR(NVL((SELECT file_count FROM temp_files), 0)) || ' tempfiles'
          FROM dual
        UNION ALL
        SELECT 30,
               'Current PDB total',
               NVL((SELECT current_bytes FROM data_files), 0) + NVL((SELECT current_bytes FROM temp_files), 0),
               NVL((SELECT max_bytes FROM data_files), 0) + NVL((SELECT max_bytes FROM temp_files), 0),
               NVL((SELECT used_bytes FROM perm_usage), 0),
               'PDB-local files only; redo/controlfiles are CDB-level'
          FROM dual
       )
 ORDER BY sort_order
]';

    OPEN :dbsize_container_rc FOR q'[
SELECT 'Current PDB only' AS scope,
       CAST(NULL AS VARCHAR2(18)) AS container_name,
       CAST(NULL AS VARCHAR2(12)) AS open_mode,
       CAST(NULL AS VARCHAR2(14)) AS perm_alloc_size,
       CAST(NULL AS VARCHAR2(14)) AS total_max_size,
       'Per-container breakdown is available only in CDB$ROOT.' AS notes
  FROM dual
]';

    OPEN :dbsize_tablespace_rc FOR q'[
WITH file_sizes AS (
  SELECT tablespace_name,
         'DATA' AS file_class,
         SUM(bytes) AS current_bytes,
         SUM(CASE WHEN autoextensible = 'YES' THEN GREATEST(maxbytes, bytes) ELSE bytes END) AS max_bytes,
         COUNT(*) AS file_count
    FROM dba_data_files
   GROUP BY tablespace_name
  UNION ALL
  SELECT tablespace_name,
         'TEMP' AS file_class,
         SUM(bytes) AS current_bytes,
         SUM(CASE WHEN autoextensible = 'YES' THEN GREATEST(maxbytes, bytes) ELSE bytes END) AS max_bytes,
         COUNT(*) AS file_count
    FROM dba_temp_files
   GROUP BY tablespace_name
),
ts_usage AS (
  SELECT m.tablespace_name,
         SUM(m.used_space * t.block_size) AS used_bytes,
         SUM((m.tablespace_size - m.used_space) * t.block_size) AS free_bytes,
         MAX(m.used_percent) AS usage_pct
    FROM dba_tablespace_usage_metrics m
    JOIN dba_tablespaces t
      ON t.tablespace_name = m.tablespace_name
   GROUP BY m.tablespace_name
)
SELECT SYS_CONTEXT('USERENV', 'CON_NAME') AS container_name,
       f.tablespace_name,
       t.contents,
       f.file_class,
       f.file_count,
       CASE
         WHEN f.current_bytes >= POWER(1024, 4) THEN TRIM(TO_CHAR(ROUND(f.current_bytes / POWER(1024, 4), 2), '999,999,999,990.00')) || ' TB'
         WHEN f.current_bytes >= POWER(1024, 3) THEN TRIM(TO_CHAR(ROUND(f.current_bytes / POWER(1024, 3), 2), '999,999,999,990.00')) || ' GB'
         WHEN f.current_bytes >= POWER(1024, 2) THEN TRIM(TO_CHAR(ROUND(f.current_bytes / POWER(1024, 2), 2), '999,999,999,990.00')) || ' MB'
         ELSE TRIM(TO_CHAR(ROUND(f.current_bytes / 1024, 2), '999,999,999,990.00')) || ' KB'
       END AS current_size,
       CASE
         WHEN NVL(u.used_bytes, 0) >= POWER(1024, 4) THEN TRIM(TO_CHAR(ROUND(NVL(u.used_bytes, 0) / POWER(1024, 4), 2), '999,999,999,990.00')) || ' TB'
         WHEN NVL(u.used_bytes, 0) >= POWER(1024, 3) THEN TRIM(TO_CHAR(ROUND(NVL(u.used_bytes, 0) / POWER(1024, 3), 2), '999,999,999,990.00')) || ' GB'
         WHEN NVL(u.used_bytes, 0) >= POWER(1024, 2) THEN TRIM(TO_CHAR(ROUND(NVL(u.used_bytes, 0) / POWER(1024, 2), 2), '999,999,999,990.00')) || ' MB'
         ELSE TRIM(TO_CHAR(ROUND(NVL(u.used_bytes, 0) / 1024, 2), '999,999,999,990.00')) || ' KB'
       END AS used_size,
       CASE
         WHEN GREATEST(f.current_bytes - NVL(u.used_bytes, 0), 0) >= POWER(1024, 4) THEN TRIM(TO_CHAR(ROUND(GREATEST(f.current_bytes - NVL(u.used_bytes, 0), 0) / POWER(1024, 4), 2), '999,999,999,990.00')) || ' TB'
         WHEN GREATEST(f.current_bytes - NVL(u.used_bytes, 0), 0) >= POWER(1024, 3) THEN TRIM(TO_CHAR(ROUND(GREATEST(f.current_bytes - NVL(u.used_bytes, 0), 0) / POWER(1024, 3), 2), '999,999,999,990.00')) || ' GB'
         WHEN GREATEST(f.current_bytes - NVL(u.used_bytes, 0), 0) >= POWER(1024, 2) THEN TRIM(TO_CHAR(ROUND(GREATEST(f.current_bytes - NVL(u.used_bytes, 0), 0) / POWER(1024, 2), 2), '999,999,999,990.00')) || ' MB'
         ELSE TRIM(TO_CHAR(ROUND(GREATEST(f.current_bytes - NVL(u.used_bytes, 0), 0) / 1024, 2), '999,999,999,990.00')) || ' KB'
       END AS free_size,
       CASE
         WHEN f.max_bytes >= POWER(1024, 4) THEN TRIM(TO_CHAR(ROUND(f.max_bytes / POWER(1024, 4), 2), '999,999,999,990.00')) || ' TB'
         WHEN f.max_bytes >= POWER(1024, 3) THEN TRIM(TO_CHAR(ROUND(f.max_bytes / POWER(1024, 3), 2), '999,999,999,990.00')) || ' GB'
         WHEN f.max_bytes >= POWER(1024, 2) THEN TRIM(TO_CHAR(ROUND(f.max_bytes / POWER(1024, 2), 2), '999,999,999,990.00')) || ' MB'
         ELSE TRIM(TO_CHAR(ROUND(f.max_bytes / 1024, 2), '999,999,999,990.00')) || ' KB'
       END AS max_size,
       ROUND(u.usage_pct, 2) AS usage_pct
  FROM file_sizes f
  JOIN dba_tablespaces t
    ON t.tablespace_name = f.tablespace_name
  LEFT JOIN ts_usage u
    ON u.tablespace_name = f.tablespace_name
 ORDER BY f.current_bytes DESC, f.tablespace_name
]';

    OPEN :dbsize_growth_rc FOR q'[
WITH snapshots AS (
  SELECT dbid,
         snap_id,
         MIN(begin_interval_time) AS begin_interval_time
    FROM dba_hist_snapshot
   GROUP BY dbid, snap_id
),
hist_raw AS (
  SELECT sn.begin_interval_time,
         SUM(h.tablespace_size * t.block_size) AS alloc_bytes,
         SUM(h.tablespace_usedsize * t.block_size) AS used_bytes
    FROM dba_hist_tbspc_space_usage h
    JOIN snapshots sn
      ON sn.dbid = h.dbid
     AND sn.snap_id = h.snap_id
    JOIN v$tablespace vt
      ON vt.ts# = h.tablespace_id
    JOIN dba_tablespaces t
      ON t.tablespace_name = vt.name
   GROUP BY sn.begin_interval_time
),
curr AS (
  SELECT alloc_bytes, used_bytes
    FROM (
          SELECT alloc_bytes,
                 used_bytes,
                 ROW_NUMBER() OVER (ORDER BY begin_interval_time DESC) AS rn
            FROM hist_raw
         )
   WHERE rn = 1
),
d7 AS (
  SELECT alloc_bytes, used_bytes
    FROM (
          SELECT alloc_bytes,
                 used_bytes,
                 ROW_NUMBER() OVER (ORDER BY begin_interval_time ASC) AS rn
            FROM hist_raw
           WHERE begin_interval_time >= SYSDATE - 7
         )
   WHERE rn = 1
),
d30 AS (
  SELECT alloc_bytes, used_bytes
    FROM (
          SELECT alloc_bytes,
                 used_bytes,
                 ROW_NUMBER() OVER (ORDER BY begin_interval_time ASC) AS rn
            FROM hist_raw
           WHERE begin_interval_time >= SYSDATE - 30
         )
   WHERE rn = 1
)
SELECT SYS_CONTEXT('USERENV', 'CON_NAME') AS container_name,
       CASE
         WHEN curr.used_bytes IS NULL THEN NULL
         WHEN curr.used_bytes >= POWER(1024, 4) THEN TRIM(TO_CHAR(ROUND(curr.used_bytes / POWER(1024, 4), 2), '999,999,999,990.00')) || ' TB'
         WHEN curr.used_bytes >= POWER(1024, 3) THEN TRIM(TO_CHAR(ROUND(curr.used_bytes / POWER(1024, 3), 2), '999,999,999,990.00')) || ' GB'
         WHEN curr.used_bytes >= POWER(1024, 2) THEN TRIM(TO_CHAR(ROUND(curr.used_bytes / POWER(1024, 2), 2), '999,999,999,990.00')) || ' MB'
         ELSE TRIM(TO_CHAR(ROUND(curr.used_bytes / 1024, 2), '999,999,999,990.00')) || ' KB'
       END AS current_used_size,
       CASE
         WHEN d7.used_bytes IS NULL THEN NULL
         WHEN ABS(curr.used_bytes - d7.used_bytes) >= POWER(1024, 4) THEN TRIM(TO_CHAR(ROUND((curr.used_bytes - d7.used_bytes) / POWER(1024, 4), 2), '999,999,999,990.00')) || ' TB'
         WHEN ABS(curr.used_bytes - d7.used_bytes) >= POWER(1024, 3) THEN TRIM(TO_CHAR(ROUND((curr.used_bytes - d7.used_bytes) / POWER(1024, 3), 2), '999,999,999,990.00')) || ' GB'
         WHEN ABS(curr.used_bytes - d7.used_bytes) >= POWER(1024, 2) THEN TRIM(TO_CHAR(ROUND((curr.used_bytes - d7.used_bytes) / POWER(1024, 2), 2), '999,999,999,990.00')) || ' MB'
         ELSE TRIM(TO_CHAR(ROUND((curr.used_bytes - d7.used_bytes) / 1024, 2), '999,999,999,990.00')) || ' KB'
       END AS used_growth_7d,
       CASE
         WHEN d30.used_bytes IS NULL THEN NULL
         WHEN ABS(curr.used_bytes - d30.used_bytes) >= POWER(1024, 4) THEN TRIM(TO_CHAR(ROUND((curr.used_bytes - d30.used_bytes) / POWER(1024, 4), 2), '999,999,999,990.00')) || ' TB'
         WHEN ABS(curr.used_bytes - d30.used_bytes) >= POWER(1024, 3) THEN TRIM(TO_CHAR(ROUND((curr.used_bytes - d30.used_bytes) / POWER(1024, 3), 2), '999,999,999,990.00')) || ' GB'
         WHEN ABS(curr.used_bytes - d30.used_bytes) >= POWER(1024, 2) THEN TRIM(TO_CHAR(ROUND((curr.used_bytes - d30.used_bytes) / POWER(1024, 2), 2), '999,999,999,990.00')) || ' MB'
         ELSE TRIM(TO_CHAR(ROUND((curr.used_bytes - d30.used_bytes) / 1024, 2), '999,999,999,990.00')) || ' KB'
       END AS used_growth_30d,
       CASE
         WHEN curr.alloc_bytes IS NULL THEN NULL
         WHEN curr.alloc_bytes >= POWER(1024, 4) THEN TRIM(TO_CHAR(ROUND(curr.alloc_bytes / POWER(1024, 4), 2), '999,999,999,990.00')) || ' TB'
         WHEN curr.alloc_bytes >= POWER(1024, 3) THEN TRIM(TO_CHAR(ROUND(curr.alloc_bytes / POWER(1024, 3), 2), '999,999,999,990.00')) || ' GB'
         WHEN curr.alloc_bytes >= POWER(1024, 2) THEN TRIM(TO_CHAR(ROUND(curr.alloc_bytes / POWER(1024, 2), 2), '999,999,999,990.00')) || ' MB'
         ELSE TRIM(TO_CHAR(ROUND(curr.alloc_bytes / 1024, 2), '999,999,999,990.00')) || ' KB'
       END AS current_alloc_size,
       CASE
         WHEN d7.alloc_bytes IS NULL THEN NULL
         WHEN ABS(curr.alloc_bytes - d7.alloc_bytes) >= POWER(1024, 4) THEN TRIM(TO_CHAR(ROUND((curr.alloc_bytes - d7.alloc_bytes) / POWER(1024, 4), 2), '999,999,999,990.00')) || ' TB'
         WHEN ABS(curr.alloc_bytes - d7.alloc_bytes) >= POWER(1024, 3) THEN TRIM(TO_CHAR(ROUND((curr.alloc_bytes - d7.alloc_bytes) / POWER(1024, 3), 2), '999,999,999,990.00')) || ' GB'
         WHEN ABS(curr.alloc_bytes - d7.alloc_bytes) >= POWER(1024, 2) THEN TRIM(TO_CHAR(ROUND((curr.alloc_bytes - d7.alloc_bytes) / POWER(1024, 2), 2), '999,999,999,990.00')) || ' MB'
         ELSE TRIM(TO_CHAR(ROUND((curr.alloc_bytes - d7.alloc_bytes) / 1024, 2), '999,999,999,990.00')) || ' KB'
       END AS alloc_growth_7d,
       CASE
         WHEN d30.alloc_bytes IS NULL THEN NULL
         WHEN ABS(curr.alloc_bytes - d30.alloc_bytes) >= POWER(1024, 4) THEN TRIM(TO_CHAR(ROUND((curr.alloc_bytes - d30.alloc_bytes) / POWER(1024, 4), 2), '999,999,999,990.00')) || ' TB'
         WHEN ABS(curr.alloc_bytes - d30.alloc_bytes) >= POWER(1024, 3) THEN TRIM(TO_CHAR(ROUND((curr.alloc_bytes - d30.alloc_bytes) / POWER(1024, 3), 2), '999,999,999,990.00')) || ' GB'
         WHEN ABS(curr.alloc_bytes - d30.alloc_bytes) >= POWER(1024, 2) THEN TRIM(TO_CHAR(ROUND((curr.alloc_bytes - d30.alloc_bytes) / POWER(1024, 2), 2), '999,999,999,990.00')) || ' MB'
         ELSE TRIM(TO_CHAR(ROUND((curr.alloc_bytes - d30.alloc_bytes) / 1024, 2), '999,999,999,990.00')) || ' KB'
       END AS alloc_growth_30d,
       'Earliest AWR snapshot inside 7d/30d windows' AS notes
  FROM curr
  LEFT JOIN d7
    ON 1 = 1
  LEFT JOIN d30
    ON 1 = 1
]';
  END IF;
END;
/

PROMPT
PROMPT Summary
PRINT dbsize_summary_rc

PROMPT
PROMPT Container Breakdown
PRINT dbsize_container_rc

PROMPT
PROMPT Tablespace Breakdown
PRINT dbsize_tablespace_rc

PROMPT
PROMPT Growth Trend
PRINT dbsize_growth_rc
