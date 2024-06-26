#!/usr/bin/env bash
# Author: Vitaliy Kukharik (vitabaks@gmail.com)
# Title: /usr/bin/pg_auto_reindexer - Automatic reindexing of B-tree indexes
# Reference: https://github.com/vitabaks/pg_auto_reindexer

version=1.3

while getopts ":-:" optchar; do
  [[ "${optchar}" == "-" ]] || continue
  case "${OPTARG}" in
    pghost=* )
      PGHOST=${OPTARG#*=}
      ;;
    pgport=* )
      PGPORT=${OPTARG#*=}
      ;;
    dbname=* )
      DBNAME=${OPTARG#*=}
      ;;
    dbuser=* )
      DBUSER=${OPTARG#*=}
      ;;
    index_bloat=* )
      INDEX_BLOAT=${OPTARG#*=}
      ;;
    index_minsize=* )
      INDEX_MINSIZE=${OPTARG#*=}
      ;;
    index_maxsize=* )
      INDEX_MAXSIZE=${OPTARG#*=}
      ;;
    bloat_search_method=* )
      BLOAT_SEARCH_METHOD=${OPTARG#*=}
      ;;
    maintenance_start=* )
      MAINTENANCE_START=${OPTARG#*=}
      ;;
    maintenance_stop=* )
      MAINTENANCE_STOP=${OPTARG#*=}
      ;;
    failed_reindex_limit* )
      FAILED_REINDEX_LIMIT=${OPTARG#*=}
      ;;
  esac
done

function help(){
echo -e "
$(basename "$0") - Automatic reindexing of B-tree indexes

\e[1m--pghost=\e[0m
    PostgreSQL host (default: /var/run/postgresql)

\e[1m--pgport=\e[0m
    PostgreSQL port (default: 5432)

\e[1m--dbname=\e[0m
    PostgreSQL database (default: all databases)

\e[1m--dbuser=\e[0m
    PostgreSQL database user name (default: postgres)

\e[1m--index_bloat=\e[0m
    Index bloat in % (default: 30)

\e[1m--index_minsize=\e[0m
    Minimum index size in MB (default: 1)
    Exclude indexes less than specified size

\e[1m--index_maxsize=\e[0m
    Maximum index size in MB (default: 1000000)
    Exclude indexes larger than specified size

\e[1m--maintenance_start=\e[0mHHMM \e[1m--maintenance_stop=\e[0mHHMM
    Determine the time range of the maintenance window (24 hour format: %H%M) [ optional ]
    Example: 2200 (22 hours 00 minutes)

\e[1m--bloat_search_method=\e[0m
    estimate - index bloat estimation (default)
    pgstattuple - use pgstattuple extension to search bloat indexes (could cause I/O spikes) [ optional ]

\e[1m--failed_reindex_limit=\e[0m
    The maximum number of reindex errors during database maintenance (default: 1)
    Example: canceling statement due to lock timeout
    After reaching the limit - the script moves to the next database.

-h, --help
    show this help, then exit

-V, --version
    output version information, then exit

Examples:
  $(basename "$0") --index_bloat=20 --maintenance_start=0100 --maintenance_stop=0600

Dependencies:
  postgresql-<version>-repack package (for postgresql <= 11)
"
exit
}
[ "$1" = "-v" ] || [ "$1" = "-V" ] || [ "$1" = "-version" ] || [ "$1" = "--version" ] && echo "$(basename "$0") v${version}" && exit
[ "$1" = "-h" ] || [ "$1" = "help" ] || [ "$1" = "-help" ] || [ "$1" = "--help" ] && help

function info(){
  if [ -n "$1" ]; then
    msg="$1"
  else
    read -r msg
    msg="  $msg"
  fi
  echo -e "$(date "+%F %T") INFO: $msg"
  logger -p user.notice -t "$(basename "$0")" "$msg"
}
function warnmsg(){
  if [ -n "$1" ]; then
    msg="$1"
  else
    read -r msg
    msg="  $msg"
    if [[ $msg == "  " ]]; then
      return 0
    fi
  fi
  echo -e "$(date "+%F %T") WARN: $msg"
  logger -p user.notice -t "$(basename "$0")" "$msg"
  return 1
}
function errmsg(){
  if [ -n "$1" ]; then
    msg="$1"
  else
    read -r msg
    msg="  $msg"
  fi
  echo -e "$(date "+%F %T") ERROR: $msg"
  logger -p user.error -t "$(basename "$0")" "$msg"
  exit 1
}

if [[ -z $PGHOST ]]; then PGHOST="/var/run/postgresql"; fi
if [[ -z $PGPORT ]]; then PGPORT="5432"; fi
if [[ -z $DBUSER ]]; then DBUSER="postgres"; fi
if [[ -z $DBNAME ]]; then if ! DBNAME=$(psql -h "${PGHOST}" -p "${PGPORT}" -U "${DBUSER}" -d postgres -tAXc "select datname from pg_database where not datistemplate"); then errmsg "Unable to connect to database postgres on ${PGHOST}:${PGPORT} "; fi; fi
if [[ -z $INDEX_BLOAT ]]; then INDEX_BLOAT="30"; fi
if [[ -z $BLOAT_SEARCH_METHOD ]]; then BLOAT_SEARCH_METHOD="estimate"; fi
if [[ -z $INDEX_MINSIZE ]]; then INDEX_MINSIZE="1"; fi
if [[ -z $INDEX_MAXSIZE ]]; then INDEX_MAXSIZE="1000000"; fi
if [[ -z $FAILED_REINDEX_LIMIT ]]; then FAILED_REINDEX_LIMIT="1"; fi

PG_VERSION=$(psql -h "${PGHOST}" -p "${PGPORT}" -U "${DBUSER}" -d $(echo ${DBNAME}|awk '{print $1}') -tAXc "select setting::integer/10000 from pg_settings where name = 'server_version_num'")

function pg_isready(){
  if ! psql -h "${PGHOST}" -p "${PGPORT}" -U "${DBUSER}" -d $(echo ${DBNAME}|awk '{print $1}') -tAXc "select 1" 1> /dev/null; then
    errmsg "PostgreSQL server ${PGHOST}:${PGPORT} no response"
  else
  # in recovery mode?
  state=$(psql -h "${PGHOST}" -p "${PGPORT}" -U "${DBUSER}" -d $(echo ${DBNAME}|awk '{print $1}') -tAXc 'SELECT pg_is_in_recovery()') 2>/dev/null
    if [ "$state" = "t" ]; then
      warnmsg "This server is in recovery mode. Index maintenance will not be performed on that server."
      exit
    fi
  fi
}

function create_extension_pgstattuple(){
  if [[ "${BLOAT_SEARCH_METHOD}" = "pgstattuple" ]]; then
    psql -h "${PGHOST}" -p "${PGPORT}" -U "${DBUSER}" -d "$db" -tAXc "create extension if not exists pgstattuple;" &>/dev/null
  fi
}

function create_extension_pg_repack(){
  psql -h "${PGHOST}" -p "${PGPORT}" -U "${DBUSER}" -d "$db" -tAXc "create extension if not exists pg_repack" &>/dev/null
}

function check_index_size(){
  psql -h "${PGHOST}" -p "${PGPORT}" -U "${DBUSER}" -d "$db" -tAXc "select pg_relation_size('$1')/1024/1024"
}

function maintenance_window(){
  if [ -n "${MAINTENANCE_START}" ] && [ -n "${MAINTENANCE_STOP}" ]; then
    currentTime=$(date "+%H%M")
    if [ "$currentTime" -lt "${MAINTENANCE_START}" ] || [ "$currentTime" -gt "${MAINTENANCE_STOP}" ]; then
      warnmsg "Current time: $(date "+%R %Z"). This is outside of the maintenance window: $(date --date="${MAINTENANCE_START}" "+%R")-$(date --date="${MAINTENANCE_STOP}" "+%R"). Exit."
      exit
    fi
  fi
}


if [[ "${BLOAT_SEARCH_METHOD}" = "pgstattuple" ]]; then
# Based on https://github.com/dataegret/pg-utils/blob/master/sql/index_bloat.sql
INDEX_BLOAT_SQL="
with indexes as (
  select * from pg_stat_user_indexes
)
select quote_ident(schemaname)||'.'||quote_ident(indexrelname) as index_full_name
from (
  select schemaname, indexrelname,
  (select (case when avg_leaf_density = 'NaN' then 0
    else greatest(ceil(index_size * (1 - avg_leaf_density / (coalesce((SELECT (regexp_matches(reloptions::text, E'.*fillfactor=(\\d+).*'))[1]),'90')::real)))::bigint, 0) end)
    from pgstatindex(p.indexrelid::regclass::text)
  ) as free_space,
  pg_relation_size(p.indexrelid) as index_size
  from indexes p
  join pg_class c on p.indexrelid = c.oid
  join pg_index i on i.indexrelid = p.indexrelid
  where pg_get_indexdef(p.indexrelid) like '%USING btree%'
  and i.indisvalid and c.relpersistence = 'p'
  and pg_relation_size(p.indexrelid)/1024/1024 >= ${INDEX_MINSIZE}
  and pg_relation_size(p.indexrelid)/1024/1024 <= ${INDEX_MAXSIZE}
  and schemaname <> 'pg_catalog' --exclude system catalog
) t
where round((free_space*100/index_size)::numeric, 1) >= ${INDEX_BLOAT}
order by index_size asc;
"
elif [[ "${BLOAT_SEARCH_METHOD}" = "estimate" ]]; then
# Based on https://github.com/ioguix/pgsql-bloat-estimation/blob/master/btree/btree_bloat.sql
INDEX_BLOAT_SQL="
WITH bloat_indexes AS (
SELECT quote_ident(nspname)||'.'||quote_ident(idxname) as index_full_name,
  bs*(relpages)::bigint AS index_size,
  round((100 * (relpages-est_pages_ff)::float / relpages)::numeric, 1) AS bloat_ratio
FROM (
  SELECT coalesce(1 +
         ceil(reltuples/floor((bs-pageopqdata-pagehdr)/(4+nulldatahdrwidth)::float)), 0 -- ItemIdData size + computed avg size of a tuple (nulldatahdrwidth)
      ) AS est_pages,
      coalesce(1 +
         ceil(reltuples/floor((bs-pageopqdata-pagehdr)*fillfactor/(100*(4+nulldatahdrwidth)::float))), 0
      ) AS est_pages_ff,
      bs, nspname, tblname, idxname, relpages, fillfactor, is_na
  FROM (
      SELECT maxalign, bs, nspname, tblname, idxname, reltuples, relpages, idxoid, fillfactor,
            ( index_tuple_hdr_bm +
                maxalign - CASE -- Add padding to the index tuple header to align on MAXALIGN
                  WHEN index_tuple_hdr_bm%maxalign = 0 THEN maxalign
                  ELSE index_tuple_hdr_bm%maxalign
                END
              + nulldatawidth + maxalign - CASE -- Add padding to the data to align on MAXALIGN
                  WHEN nulldatawidth = 0 THEN 0
                  WHEN nulldatawidth::integer%maxalign = 0 THEN maxalign
                  ELSE nulldatawidth::integer%maxalign
                END
            )::numeric AS nulldatahdrwidth, pagehdr, pageopqdata, is_na
      FROM (
          SELECT n.nspname, i.tblname, i.idxname, i.reltuples, i.relpages,
              i.idxoid, i.fillfactor, current_setting('block_size')::numeric AS bs,
              CASE -- MAXALIGN: 4 on 32bits, 8 on 64bits (and mingw32 ?)
                WHEN version() ~ 'mingw32' OR version() ~ '64-bit|x86_64|ppc64|ia64|amd64' THEN 8
                ELSE 4
              END AS maxalign,
              /* per page header, fixed size: 20 for 7.X, 24 for others */
              24 AS pagehdr,
              /* per page btree opaque data */
              16 AS pageopqdata,
              /* per tuple header: add IndexAttributeBitMapData if some cols are null-able */
              CASE WHEN max(coalesce(s.null_frac,0)) = 0
                  THEN 8 -- IndexTupleData size
                  ELSE 8 + (( 32 + 8 - 1 ) / 8) -- IndexTupleData size + IndexAttributeBitMapData size ( max num filed per index + 8 - 1 /8)
              END AS index_tuple_hdr_bm,
              /* data len: we remove null values save space using it fractionnal part from stats */
              sum( (1-coalesce(s.null_frac, 0)) * coalesce(s.avg_width, 1024)) AS nulldatawidth,
              max( CASE WHEN i.atttypid = 'pg_catalog.name'::regtype THEN 1 ELSE 0 END ) > 0 AS is_na
          FROM (
              SELECT ct.relname AS tblname, ct.relnamespace, ic.idxname, ic.attpos, ic.indkey, ic.indkey[ic.attpos], ic.reltuples, ic.relpages, ic.tbloid, ic.idxoid, ic.fillfactor,
                  coalesce(a1.attnum, a2.attnum) AS attnum, coalesce(a1.attname, a2.attname) AS attname, coalesce(a1.atttypid, a2.atttypid) AS atttypid,
                  CASE WHEN a1.attnum IS NULL
                  THEN ic.idxname
                  ELSE ct.relname
                  END AS attrelname
              FROM (
                  SELECT idxname, reltuples, relpages, tbloid, idxoid, fillfactor, indkey,
                      pg_catalog.generate_series(1,indnatts) AS attpos
                  FROM (
                      SELECT ci.relname AS idxname, ci.reltuples, ci.relpages, i.indrelid AS tbloid,
                          i.indexrelid AS idxoid,
                          coalesce(substring(
                              array_to_string(ci.reloptions, ' ')
                              from 'fillfactor=([0-9]+)')::smallint, 90) AS fillfactor,
                          i.indnatts,
                          pg_catalog.string_to_array(pg_catalog.textin(
                              pg_catalog.int2vectorout(i.indkey)),' ')::int[] AS indkey
                      FROM pg_catalog.pg_index i
                      JOIN pg_catalog.pg_class ci ON ci.oid = i.indexrelid
                      WHERE ci.relam=(SELECT oid FROM pg_am WHERE amname = 'btree')
                      AND ci.relpages > 0
                  ) AS idx_data
              ) AS ic
              JOIN pg_catalog.pg_class ct ON ct.oid = ic.tbloid
              LEFT JOIN pg_catalog.pg_attribute a1 ON
                  ic.indkey[ic.attpos] <> 0
                  AND a1.attrelid = ic.tbloid
                  AND a1.attnum = ic.indkey[ic.attpos]
              LEFT JOIN pg_catalog.pg_attribute a2 ON
                  ic.indkey[ic.attpos] = 0
                  AND a2.attrelid = ic.idxoid
                  AND a2.attnum = ic.attpos
            ) i
            JOIN pg_catalog.pg_namespace n ON n.oid = i.relnamespace
            JOIN pg_catalog.pg_stats s ON s.schemaname = n.nspname
                                      AND s.tablename = i.attrelname
                                      AND s.attname = i.attname
            WHERE schemaname <> 'pg_catalog' --exclude system catalog
            GROUP BY 1,2,3,4,5,6,7,8,9,10,11
      ) AS rows_data_stats
  ) AS rows_hdr_pdg_stats
) AS relation_stats
WHERE bs*(relpages)::bigint/1024/1024 >= ${INDEX_MINSIZE}
AND bs*(relpages)::bigint/1024/1024 <= ${INDEX_MAXSIZE}
AND round((100 * (relpages-est_pages_ff)::float / relpages)::numeric, 1) >= ${INDEX_BLOAT}
ORDER BY index_size ASC
)
SELECT index_full_name FROM bloat_indexes;
"
fi

# SET PGOPTIONS
PGOPTIONS="-c statement_timeout=0 -c lock_timeout=1s"
# disable parallel maintenance workers
if [[ $PG_VERSION -ge 11 ]]; then
PGOPTIONS+=" -c max_parallel_maintenance_workers=0"
fi

# Check current time
maintenance_window

# REINDEX
total_maintenance_benefit=0
for db in $DBNAME; do
  db_maintenance_benefit=0
  if pg_isready; then
    create_extension_pgstattuple
    info "Started index maintenance for database: $db"
    bloat_indexes=$(psql -h "${PGHOST}" -p "${PGPORT}" -U "${DBUSER}" -d "$db" -tAXc "$INDEX_BLOAT_SQL")
    if [[ -z "$bloat_indexes" ]]; then
      info "  no bloat indexes were found"
      info "Completed index maintenance for database: $db"
    else
      failed_reindex_count=0
      # if postgres <= 11 use pg_repack
      if [[ $PG_VERSION -le 11 ]]; then
        create_extension_pg_repack
        for index in $bloat_indexes; do
          retry_n=0
          if [[ $failed_reindex_count -ge $FAILED_REINDEX_LIMIT ]]; then
            warnmsg "Index maintenance for database: $db exceeded $FAILED_REINDEX_LIMIT failed index repacking. Skipping."
            break
          fi
          pg_isready
          maintenance_window
          index_size_before=$(check_index_size "$index")
          for delay in 0 10 30 60; do
            sleep $delay
            if [[ $retry_n -eq 0 ]]; then
              info "  repack index $index (size: $index_size_before MB)"
            else
              info "  [retry ${retry_n}/3] repack index $index (size: $index_size_before MB)"
            fi
            if bash -c "PGOPTIONS=\"${PGOPTIONS}\" pg_repack -h ${PGHOST} -p ${PGPORT} -U ${DBUSER} -d $db -i '$index' --elevel=WARNING" 2>&1 | warnmsg; then
              index_size_after=$(check_index_size "$index")
              info "  completed repack index $index (size after: $index_size_after MB)"
              break
            else
              # check for invalid temporary indexes with the suffix "index_"
              invalid_index=$(psql -h "${PGHOST}" -p "${PGPORT}" -U "${DBUSER}" -d "$db" -tAXc "SELECT string_agg(quote_ident(schemaname)||'.'||quote_ident(indexrelname), ', ') FROM pg_stat_user_indexes sui JOIN pg_index i USING (indexrelid) WHERE NOT indisvalid AND indexrelname like 'index_%'")
              if [ -n "$invalid_index" ]; then
                warnmsg "  A temporary index apparently created by pg_repack has been left behind."
                warnmsg "  failed to repack index \"$index\". Skipping"
                failed_reindex_count=$((failed_reindex_count+1))
                continue 2
              fi
              retry_n=$((retry_n+1))
              # Skipping repack after all attempts
              if [[ $delay -eq 60 ]]; then
                warnmsg "  failed to repack index \"$index\" after all attempts. Skipping"
                failed_reindex_count=$((failed_reindex_count+1))
                continue 2
              fi
            fi
          done
          db_maintenance_benefit=$((db_maintenance_benefit+index_size_before-index_size_after))
        sleep 2s
        done
      # if postgres >= 12 use reindex concurrently
      elif [[ $PG_VERSION -ge 12 ]]; then
        for index in $bloat_indexes; do
          retry_n=0
          if [[ $failed_reindex_count -ge $FAILED_REINDEX_LIMIT ]]; then
            warnmsg "Index maintenance for database: $db exceeded $FAILED_REINDEX_LIMIT failed reindex. Skipping."
            break
          fi
          pg_isready
          maintenance_window
          index_size_before=$(check_index_size "$index")
          for delay in 0 10 30 60; do
            sleep $delay
            if [[ $retry_n -eq 0 ]]; then
              info "  reindex index $index (size: $index_size_before MB)"
            else
              info "  [retry ${retry_n}/3] reindex index $index (size: $index_size_before MB)"
            fi
            if bash -c "PGOPTIONS=\"${PGOPTIONS}\" psql -h ${PGHOST} -p ${PGPORT} -U ${DBUSER} -d $db -tAXc 'REINDEX INDEX CONCURRENTLY $index' 1> /dev/null" 2>&1 | warnmsg; then
              index_size_after=$(check_index_size "$index")
              info "  completed reindex index $index (size after: $index_size_after MB)"
              break
            else
              retry_n=$((retry_n+1))
              # drop invalid index
              invalid_index=$(psql -h "${PGHOST}" -p "${PGPORT}" -U "${DBUSER}" -d "$db" -tAXc "SELECT quote_ident(schemaname)||'.'||quote_ident(indexrelname) as invalid_index FROM pg_stat_user_indexes sui JOIN pg_index i USING (indexrelid) WHERE NOT indisvalid AND quote_ident(schemaname)||'.'||quote_ident(indexrelname) = '${index}_ccnew'")
              if [[ -n "$invalid_index" ]]; then
                if ! bash -c "PGOPTIONS=\"${PGOPTIONS}\" psql -h ${PGHOST} -p ${PGPORT} -U ${DBUSER} -d $db -tAXc 'DROP INDEX CONCURRENTLY $invalid_index' &> /dev/null"; then
                  warnmsg "  failed to drop invalid index $invalid_index"
                  warnmsg "  The index marked INVALID with the suffixed ccnew corresponds to the transient index created during the concurrent operation, and the recommended recovery method is to drop it using DROP INDEX CONCURRENTLY and try the pg_auto_reindexer again."
                fi
              fi
              # Skipping reindex after all attempts
              if [[ $delay -eq 60 ]]; then
                warnmsg "  failed to reindex index \"$index\" after all attempts. Skipping"
                failed_reindex_count=$((failed_reindex_count+1))
                continue 2
              fi
            fi
          done
          db_maintenance_benefit=$((db_maintenance_benefit+index_size_before-index_size_after))
          sleep 2s
        done
      fi
    fi
  fi
  total_maintenance_benefit=$((total_maintenance_benefit+db_maintenance_benefit))
  if [[ -n "$bloat_indexes" ]] && [[ $failed_reindex_count -lt $FAILED_REINDEX_LIMIT ]]; then
    info "Completed index maintenance for database: $db (released: $db_maintenance_benefit MB)"
  fi
  invalid_index_drop_commands=$(psql -h "${PGHOST}" -p "${PGPORT}" -U "${DBUSER}" -d "$db" -tAXc "SELECT string_agg('DROP INDEX CONCURRENTLY '||quote_ident(schemaname)||'.'||quote_ident(indexrelname), '; ')||';' FROM pg_stat_user_indexes sui JOIN pg_index i USING (indexrelid) WHERE NOT indisvalid AND indexrelname like 'index_%'")
  if [ -n "$invalid_index_drop_commands" ]; then
    info "A temporary index(es) apparently created by pg_repack has been left behind, and we do not want to risk dropping this index ourselves."
    info "If the index was in fact created by an old pg_repack job which didn't get cleaned up, you should just use next commands:"
    info "$invalid_index_drop_commands" 
    info "and run pg_auto_reindexer again."
  fi
done
info "Total amount released during maintenance: $total_maintenance_benefit MB"
exit
