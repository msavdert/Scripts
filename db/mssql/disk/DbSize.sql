IF OBJECT_ID('tempdb..#spacetable') IS NOT NULL 
DROP TABLE tempdb..#spacetable 
create table #spacetable
(
dbname varchar(50) ,
total_data_size_in_bytes int,
used_data_space_in_bytes int,
free_data_space_in_bytes int,
used_data_space_in_percent float,
total_log_size_in_bytes int,
used_log_space_in_bytes int,
free_log_space_in_bytes int,
used_log_space_in_percent char(50),
[total_db_size_in_bytes] int,
[total_size_used] int,
[total_size_free] int
)
insert into #spacetable
EXECUTE master.sys.sp_MSforeachdb 'USE [?];
select x.[DATABASE NAME],x.[total size data],x.[space util],x.[total size data]-x.[space util] [space left data],
x.[percent fill],y.[total size log],y.[space util],
y.[total size log]-y.[space util] [space left log],y.[percent fill],
y.[total size log]+x.[total size data] ''total db size''
,x.[space util]+y.[space util] ''total size used'',
(y.[total size log]+x.[total size data])-(y.[space util]+x.[space util]) ''total size left''
 from (select DB_NAME() ''DATABASE NAME'',
sum(size*8*1024) ''total size data'',sum(FILEPROPERTY(name,''SpaceUsed'')*8*1024) ''space util''
,case when sum(size*8*1024)=0 then ''divide by zero'' else
substring(cast((sum(FILEPROPERTY(name,''SpaceUsed''))*1.0*100/sum(size)) as CHAR(50)),1,6) end ''percent fill''
from sys.master_files where database_id=DB_ID(DB_NAME()) and type=0
group by type_desc  ) as x ,
(select 
sum(size*8*1024) ''total size log'',sum(FILEPROPERTY(name,''SpaceUsed'')*8*1024) ''space util''
,case when sum(size*8*1024)=0 then ''divide by zero'' else
substring(cast((sum(FILEPROPERTY(name,''SpaceUsed''))*1.0*100/sum(size)) as CHAR(50)),1,6) end ''percent fill''
from sys.master_files where database_id=DB_ID(DB_NAME())  and  type=1
group by type_desc )y'
select    REPLACE(@@SERVERNAME,'\\',':') AS [sql_instance],s.* from #spacetable s
order by dbname
drop table #spacetable
