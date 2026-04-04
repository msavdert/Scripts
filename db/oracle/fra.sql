REM     Script:     fra.sql
REM     Purpose:    Report Fast Recovery Area configuration, allocation, and
REM                 usage status.

Prompt +FRA Status
Prompt ========================
select
   name,
  floor(space_limit / 1024 / 1024) "Size MB",
  ceil(space_used / 1024 / 1024) "Used MB"
from v$recovery_file_dest;

Prompt FLASH_RECOVERY_AREA_USAGE
Prompt ========================
SELECT * FROM V$FLASH_RECOVERY_AREA_USAGE;

Prompt Location and size of the FRA
Prompt ========================
show parameter db_recovery_file_dest
Prompt
Prompt Size, used, Reclaimable 
Prompt ========================

SELECT
  ROUND((A.SPACE_LIMIT / 1024 / 1024 / 1024), 2) AS FLASH_IN_GB, 
  ROUND((A.SPACE_USED / 1024 / 1024 / 1024), 2) AS FLASH_USED_IN_GB, 
  ROUND((A.SPACE_RECLAIMABLE / 1024 / 1024 / 1024), 2) AS FLASH_RECLAIMABLE_GB,
  SUM(B.PERCENT_SPACE_USED)  AS PERCENT_OF_SPACE_USED
FROM
  V$RECOVERY_FILE_DEST A,
  V$FLASH_RECOVERY_AREA_USAGE B
GROUP BY
  SPACE_LIMIT, 
  SPACE_USED , 
  SPACE_RECLAIMABLE ;
 
Prompt After that you can resize the FRA with:
Prompt ========================
Prompt ALTER SYSTEM SET db_recovery_file_dest_size=xxG;
Prompt
Prompt Or change the FRA to a new location (new archives will be created to this new location):
Prompt ========================
Prompt ALTER SYSTEM SET DB_RECOVERY_FILE_DEST='/u....';
Prompt