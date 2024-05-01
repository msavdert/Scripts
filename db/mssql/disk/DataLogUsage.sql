 if object_id('tempdb..#dbserversize') is not null
    DROP TABLE #dbserversize;

    create table dbo.#dbserversize (
     [id] int identity (1,1)
    ,[databaseName] sysname
    ,[Drive]    varchar(3)
    ,[Logical Name] sysname
    ,[Physical Name]    varchar(max)
    ,[File Size MB] decimal(38, 2)
    ,[Space Used MB]    decimal(38, 2)
    ,[Free Space]   decimal(38, 2)
    ,[%Free Space]  decimal(38, 2)
    ,[Max Size] varchar(max)
    ,[Growth Rate]  varchar(max)
    )

    declare @id int
    declare @threshold int
    declare @dbname sysname

    declare @sqltext nvarchar(max)

select @dbname = min(name) from sys.databases where database_id > 4 and [state] = 0 

    while @dbname is not NULL

    begin
        select @dbname = name from sys.databases where name = @dbname and database_id > 4 and [state] = 0 
            --- Modified from Erin's blog : Proactive SQL Server Health Checks, Part 1 : Disk Space
            --- source http://sqlperformance.com/2014/12/io-subsystem/proactive-sql-server-health-checks-1
        set @sqltext =  ' use '+@dbname+';'+' 
            insert into dbo.#dbserversize
            select '''+@dbname+''' as [databaseName]
                ,substring([physical_name], 1, 3) as [Drive]
                ,[name] as [Logical Name]
                ,[physical_name] as [Physical Name]
                ,cast(CAST([size] as decimal(38, 2)) / 128.0 as decimal(38, 2)) as [File Size MB]
                ,cast(CAST(FILEPROPERTY([name], ''SpaceUsed'') as decimal(38, 2)) / 128.0 as decimal(38, 2)) as [Space Used MB]
                ,cast((CAST([size] as decimal(38, 0)) / 128) - (CAST(FILEPROPERTY([name], ''SpaceUsed'') as decimal(38, 0)) / 128.) as decimal(38, 2)) as [Free Space]
                ,cast(((CAST([size] as decimal(38, 2)) / 128) - (CAST(FILEPROPERTY([name], ''SpaceUsed'') as decimal(38, 2)) / 128.0)) * 100.0 / (CAST([size] as decimal(38, 2)) / 128) as decimal(38, 2)) as [%Free Space]
                ,case 
                    when cast([max_size] as varchar(max)) = - 1
                        then ''UNLIMITED''
                    else cast([max_size] as varchar(max))
                    end as [Max Size]
                ,case 
                    when is_percent_growth = 1
                        then cast([growth] as varchar(20)) + ''%''
                    else cast([growth] as varchar(20)) + ''MB''
                    end as [Growth Rate]
                from sys.database_files
              --  where type = 0 -- for Rows , 1 = LOG'
            --print @sqltext
            exec (@sqltext)


            select @dbname = min(name) from sys.databases where name > @dbname and database_id > 4 and [state] = 0 
    end

select * from dbo.#dbserversize order by databaseName

drop table dbo.#dbserversize
