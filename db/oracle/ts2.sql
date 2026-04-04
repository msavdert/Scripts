REM     Script:     ts2.sql
REM     Purpose:    Display tablespace allocation, autoextend capacity, and free
REM                 space details.

col dfc format 999
col contents format a10
col tablespace_name format a25
col "CURRENT_SIZE_MB" format a20
col "USED_MB" format a20
col "MAX_SIZE_MB" format a20
col "MAX_FREE_MB" format a20

PRO
PRO ALTER DATABASE DATAFILE '/ucw1db03/oracle/oradata/dosicprd/users_02.dbf' AUTOEXTEND OFF MAXSIZE 4096M;
PRO
PRO ALTER TABLESPACE TEST ADD DATAFILE 'E:\ORACLE\ORADATA\SKY\RAPXQPROD55.DBF' SIZE 100M AUTOEXTEND ON NEXT 512M MAXSIZE UNLIMITED;
PRO
PRO ALTER DATABASE DATAFILE '/cpm1db02/oracle/oradata/cpmprd/tscpmidxh02.dbf' RESIZE 12000M;
PRO
PRO ALTER TABLESPACE DATA ADD DATAFILE 'I:\ORACLE\ORADATA\STDBY\DATA24.DBF' SIZE 2048M AUTOEXTEND OFF;
PRO

SELECT
    a.tablespace_name "TABLESPACE_NAME",
    a.df_count dfc, a.non_ext_df_count nonext_dfc,
    trim(to_char(a.current_mb, '999,999,999,999')) "CURRENT_SIZE_MB",
    trim(to_char((a.current_mb - c.free), '999,999,999,999')) "USED_MB",
    trim(to_char(a.max_mb, '999,999,999,999')) "MAX_SIZE_MB",
    trim(to_char((a.max_mb - (a.current_mb - c.free)), '999,999,999,999')) "MAX_FREE_MB",
    round(((a.current_mb - c.free)*100)/a.max_mb,1) "USED_PCT",
    c.block_size, c.contents, c.segment_space_management ssm, c.bigfile
 FROM
    ( SELECT tablespace_name,
             (COUNT(*) - SUM(decode(a.autoextensible, 'YES', 1, 0))) non_ext_df_count, COUNT(*) df_count,
             SUM(a.bytes)/(1024*1024) current_mb, SUM(decode(a.autoextensible, 'NO', a.bytes/(1024*1024), GREATEST (a.maxbytes/(1024*1024),a.bytes/(1024*1024)))) max_mb
         FROM dba_data_files a GROUP BY tablespace_name
    ) a,
    ( SELECT d.tablespace_name,
             d.block_size, d.contents, d.segment_space_management, d.bigfile,
             sum(nvl(c.bytes/(1024*1024),0)) free
       FROM dba_tablespaces d, dba_free_space c
       WHERE d.tablespace_name = c.tablespace_name(+)
             -- AND d.contents='PERMANENT'
             -- AND d.status='ONLINE'
       GROUP BY  d.tablespace_name, d.block_size, d.contents, d.segment_space_management, d.bigfile
    ) c
 WHERE a.tablespace_name = c.tablespace_name
 ORDER BY 8 DESC;