---
database: PostgreSQL
title: Backup and Recovery
class: pgBackRest
created: 05/28/2024 00:09
---
## Backup on Same Host

### Environment

| Hostname | IP Address  | OS            | Role                |
| -------- | ----------- | ------------- | ------------------- |
| pg01     | 172.28.5.11 | Rocky Linux 9 | PostgreSQL Database |

### pgBackRest Installation

[[pgBackRest 2.5x Installation]]

### pgBackRest repository location
#### Local repository

**Create pgBackRest configuration file and directories**

```bash
sudo mkdir -p -m 770 /var/log/pgbackrest
sudo chown postgres:postgres /var/log/pgbackrest
sudo mkdir -p /etc/pgbackrest/conf.d
sudo touch /etc/pgbackrest/pgbackrest.conf
sudo chmod 640 /etc/pgbackrest/pgbackrest.conf
sudo chown -R postgres:postgres /etc/pgbackrest/
```

**Create pgBackRest repository directory**

```sh
sudo mkdir -p /backup/pgbackrest
sudo chown postgres:postgres /backup/pgbackrest
```

**PostgreSQL parameter configuraitons**

```bash
sudo -u postgres psql -c "select name, setting from pg_settings where name in ('archive_command','archive_mode','log_filename','max_wal_senders','wal_level','listen_addresses');"

      name       |      setting
-----------------+-------------------
 archive_command | (disabled)
 archive_mode    | off
 log_filename    | postgresql-%a.log
 max_wal_senders | 10
 wal_level       | replica
listen_addresses | localhost
```

>[!note]
>Change " --stanza=pg01"

```bash
sudo -u postgres psql <<EOF
alter system set archive_command to 'pgbackrest --stanza=pg01 archive-push %p';
alter system set archive_mode=on;
alter system set log_filename='postgresql.log';
-- alter system set max_wal_senders = 3;
alter system set wal_level = replica;
alter system set listen_addresses = '*';
EOF
```

**PostgreSQL service restart/reload**

```bash
postgres=# SELECT pg_reload_conf();
 pg_reload_conf
----------------
 t

postgres=# select name, setting, pending_restart from pg_settings where pending_restart;
     name     | setting | pending_restart
--------------+---------+-----------------
 archive_mode | off     | t
```

```bash
sudo systemctl restart postgresql-16.service
```

**Repository Encryption**

```bash
sudo openssl rand -base64 48

6S7bJ8VBfGRbekNUkfIt4wzA8e2oCRdJUpehdPJ1YoOmtDCU5emCiB3/u2ya5FzA
```

**pgBackRest Configuration**

```sh
cat << EOF | tee "/etc/pgbackrest/pgbackrest.conf"
[pg01]
pg1-path=/var/lib/pgsql/16/data

[global]
repo1-path=/backup/pgbackrest
repo1-retention-full=2
repo1-block=y
repo1-bundle=y
repo1-cipher-pass=6S7bJ8VBfGRbekNUkfIt4wzA8e2oCRdJUpehdPJ1YoOmtDCU5emCiB3/u2ya5FzA
repo1-cipher-type=aes-256-cbc

log-level-console=info
log-level-file=detail
process-max=2
start-fast=y
delta=y
EOF
```

**Create and check stanza**

```sh
sudo -u postgres pgbackrest --stanza=pg01 stanza-create
```

```
2024-05-28 09:13:36.240 P00   INFO: stanza-create command begin 2.52: --exec-id=1223-d7572d21 --log-level-console=info --log-level-file=detail --pg1-path=/var/lib/pgsql/16/data --repo1-path=/backup/pgbackrest --stanza=pg01
2024-05-28 09:13:36.844 P00   INFO: stanza-create for stanza 'pg01' on repo1
2024-05-28 09:13:36.851 P00   INFO: stanza-create command end: completed successfully (614ms)
```

```sh
sudo -u postgres pgbackrest --stanza=pg01 check
```

```
2024-05-28 09:13:51.825 P00   INFO: check command begin 2.52: --exec-id=1226-128215ba --log-level-console=info --log-level-file=detail --pg1-path=/var/lib/pgsql/16/data --repo1-path=/backup/pgbackrest --stanza=pg01
2024-05-28 09:13:52.429 P00   INFO: check repo1 configuration (primary)
2024-05-28 09:13:52.630 P00   INFO: check repo1 archive for WAL (primary)
2024-05-28 09:13:52.730 P00   INFO: WAL segment 000000010000000000000001 successfully archived to '/backup/pgbackrest/archive/pg01/16-1/0000000100000000/000000010000000000000001-133ac708f1db2413dd739712aee509237e544763.gz' on repo1
2024-05-28 09:13:52.730 P00   INFO: check command end: completed successfully (907ms)
```

**Backup**

```sh
sudo -iu postgres pgbackrest --stanza=pg01 --type=full backup
```

```
2024-05-28 09:14:10.131 P00   INFO: backup command begin 2.52: --delta --exec-id=1262-9b36c647 --log-level-console=info --log-level-file=detail --pg1-path=/var/lib/pgsql/16/data --process-max=2 --repo1-block --repo1-bundle --repo1-path=/backup/pgbackrest --repo1-retention-full=2 --stanza=pg01 --start-fast --type=full
2024-05-28 09:14:10.835 P00   INFO: execute non-exclusive backup start: backup begins after the requested immediate checkpoint completes
2024-05-28 09:14:11.336 P00   INFO: backup start archive = 000000010000000000000003, lsn = 0/3000060
2024-05-28 09:14:11.336 P00   INFO: check archive for prior segment 000000010000000000000002
2024-05-28 09:14:12.860 P00   INFO: execute non-exclusive backup stop and wait for all WAL segments to archive
2024-05-28 09:14:13.061 P00   INFO: backup stop archive = 000000010000000000000003, lsn = 0/3000138
2024-05-28 09:14:13.062 P00   INFO: check archive for segment(s) 000000010000000000000003:000000010000000000000003
2024-05-28 09:14:13.068 P00   INFO: new backup label = 20240528-091410F
2024-05-28 09:14:13.093 P00   INFO: full backup size = 22.1MB, file total = 969
2024-05-28 09:14:13.093 P00   INFO: backup command end: completed successfully (2964ms)
2024-05-28 09:14:13.094 P00   INFO: expire command begin 2.52: --exec-id=1262-9b36c647 --log-level-console=info --log-level-file=detail --repo1-path=/backup/pgbackrest --repo1-retention-full=2 --stanza=pg01
2024-05-28 09:14:13.097 P00   INFO: expire command end: completed successfully (4ms)
```

```sh
sudo -iu postgres pgbackrest info
sudo -iu postgres pgbackrest --stanza=pg01 info
```

```
stanza: pg01
    status: ok
    cipher: none

    db (current)
        wal archive min/max (16): 000000010000000000000001/000000010000000000000003

        full backup: 20240528-091410F
            timestamp start/stop: 2024-05-28 09:14:10-04 / 2024-05-28 09:14:12-04
            wal start/stop: 000000010000000000000003 / 000000010000000000000003
            database size: 22.1MB, database backup size: 22.1MB
            repo1: backup size: 2.9MB
```

#### S3-Compatible Object Store

[pgBackRest multi-repositories tips and tricks | pgstef’s blog](https://pgstef.github.io/2022/04/15/pgbackrest_multi-repositories_tips_and_tricks.html)

**pgBackRest Configuration**

```sh
cat << EOF | tee "/etc/pgbackrest/pgbackrest.conf"
[pg01]
pg1-path=/var/lib/pgsql/16/data

[global]
## Local repository
repo1-path=/backup/pgbackrest
repo1-retention-full=2
repo1-block=y
repo1-bundle=y
repo1-cipher-pass=6S7bJ8VBfGRbekNUkfIt4wzA8e2oCRdJUpehdPJ1YoOmtDCU5emCiB3/u2ya5FzA
repo1-cipher-type=aes-256-cbc

## OCI S3-compatible bucket repository
repo2-type=s3
repo2-storage-verify-tls=n
repo2-s3-endpoint=https://frkaqewuw7qz.compat.objectstorage.eu-frankfurt-1.oraclecloud.com
repo2-s3-uri-style=path
repo2-s3-bucket=ocigelibolbucket
repo2-s3-key=3167461162edd5f0d67b092fd777bae183e75194
repo2-s3-key-secret=mqey2WEBNEpnLhN6t/2E3vYMchLhjY5LTHdCP7JjAZk=
repo2-s3-region=eu-frankfurt-1
repo2-path=/pgbackrest
repo2-retention-full=2
repo2-block=y
repo2-bundle=y
repo2-cipher-pass=6S7bJ8VBfGRbekNUkfIt4wzA8e2oCRdJUpehdPJ1YoOmtDCU5emCiB3/u2ya5FzA
repo2-cipher-type=aes-256-cbc

log-level-console=info
log-level-file=detail
process-max=2
start-fast=y
delta=y
EOF
```

**Create and check stanza**

```sh
sudo -u postgres pgbackrest --stanza=pg01 stanza-create
```

```
2024-05-28 09:30:33.146 P00   INFO: stanza-create command begin 2.52: --exec-id=1572-409c1da4 --log-level-console=info --log-level-file=detail --pg1-path=/var/lib/pgsql/16/data --repo1-path=/backup/pgbackrest --repo2-path=/pgbackrest --repo2-s3-bucket=ocigelibolbucket --repo2-s3-endpoint=https://frkaqewuw7qz.compat.objectstorage.eu-frankfurt-1.oraclecloud.com --repo2-s3-key=<redacted> --repo2-s3-key-secret=<redacted> --repo2-s3-region=eu-frankfurt-1 --repo2-s3-uri-style=path --no-repo2-storage-verify-tls --repo2-type=s3 --stanza=pg01
2024-05-28 09:30:33.750 P00   INFO: stanza-create for stanza 'pg01' on repo1
2024-05-28 09:30:33.750 P00   INFO: stanza 'pg01' already exists on repo1 and is valid
2024-05-28 09:30:33.750 P00   INFO: stanza-create for stanza 'pg01' on repo2
2024-05-28 09:30:35.615 P00   INFO: stanza-create command end: completed successfully (2471ms)
```

```sh
sudo -u postgres pgbackrest --stanza=pg01 check
```

```
2024-05-28 09:30:42.354 P00   INFO: check command begin 2.52: --exec-id=1575-e544f1d1 --log-level-console=info --log-level-file=detail --pg1-path=/var/lib/pgsql/16/data --repo1-path=/backup/pgbackrest --repo2-path=/pgbackrest --repo2-s3-bucket=ocigelibolbucket --repo2-s3-endpoint=https://frkaqewuw7qz.compat.objectstorage.eu-frankfurt-1.oraclecloud.com --repo2-s3-key=<redacted> --repo2-s3-key-secret=<redacted> --repo2-s3-region=eu-frankfurt-1 --repo2-s3-uri-style=path --no-repo2-storage-verify-tls --repo2-type=s3 --stanza=pg01
2024-05-28 09:30:42.958 P00   INFO: check repo1 configuration (primary)
2024-05-28 09:30:42.959 P00   INFO: check repo2 configuration (primary)
2024-05-28 09:30:43.756 P00   INFO: check repo1 archive for WAL (primary)
2024-05-28 09:30:44.358 P00   INFO: WAL segment 000000010000000000000004 successfully archived to '/backup/pgbackrest/archive/pg01/16-1/0000000100000000/000000010000000000000004-91250f236465651e87e6c565576047329a0741b7.gz' on repo1
2024-05-28 09:30:44.358 P00   INFO: check repo2 archive for WAL (primary)
2024-05-28 09:30:45.010 P00   INFO: WAL segment 000000010000000000000004 successfully archived to '/pgbackrest/archive/pg01/16-1/0000000100000000/000000010000000000000004-91250f236465651e87e6c565576047329a0741b7.gz' on repo2
2024-05-28 09:30:45.010 P00   INFO: check command end: completed successfully (2658ms)
```

**Backup**

```sh
sudo -iu postgres pgbackrest --stanza=pg01 --type=full backup
sudo -iu postgres pgbackrest --stanza=pg01 --type=full backup --repo=1
sudo -iu postgres pgbackrest --stanza=pg01 --type=full backup --repo=2
```

```
2024-05-28 09:31:55.702 P00   INFO: backup command begin 2.52: --delta --exec-id=1594-cebf3f3e --log-level-console=info --log-level-file=detail --pg1-path=/var/lib/pgsql/16/data --process-max=2 --repo1-block --repo2-block --repo1-bundle --repo2-bundle --repo1-path=/backup/pgbackrest --repo2-path=/pgbackrest --repo1-retention-full=2 --repo2-retention-full=2 --repo2-s3-bucket=ocigelibolbucket --repo2-s3-endpoint=https://frkaqewuw7qz.compat.objectstorage.eu-frankfurt-1.oraclecloud.com --repo2-s3-key=<redacted> --repo2-s3-key-secret=<redacted> --repo2-s3-region=eu-frankfurt-1 --repo2-s3-uri-style=path --no-repo2-storage-verify-tls --repo2-type=s3 --stanza=pg01 --start-fast --type=full
2024-05-28 09:31:55.702 P00   INFO: repo option not specified, defaulting to repo1
2024-05-28 09:31:56.406 P00   INFO: execute non-exclusive backup start: backup begins after the requested immediate checkpoint completes
2024-05-28 09:31:56.906 P00   INFO: backup start archive = 000000010000000000000006, lsn = 0/6000028
2024-05-28 09:31:56.906 P00   INFO: check archive for prior segment 000000010000000000000005
2024-05-28 09:31:59.857 P00   INFO: execute non-exclusive backup stop and wait for all WAL segments to archive
2024-05-28 09:32:00.057 P00   INFO: backup stop archive = 000000010000000000000006, lsn = 0/6000100
2024-05-28 09:32:00.060 P00   INFO: check archive for segment(s) 000000010000000000000006:000000010000000000000006
2024-05-28 09:32:00.668 P00   INFO: new backup label = 20240528-093156F
2024-05-28 09:32:00.700 P00   INFO: full backup size = 22.1MB, file total = 969
2024-05-28 09:32:00.700 P00   INFO: backup command end: completed successfully (5001ms)
2024-05-28 09:32:00.701 P00   INFO: expire command begin 2.52: --exec-id=1594-cebf3f3e --log-level-console=info --log-level-file=detail --repo1-path=/backup/pgbackrest --repo2-path=/pgbackrest --repo1-retention-full=2 --repo2-retention-full=2 --repo2-s3-bucket=ocigelibolbucket --repo2-s3-endpoint=https://frkaqewuw7qz.compat.objectstorage.eu-frankfurt-1.oraclecloud.com --repo2-s3-key=<redacted> --repo2-s3-key-secret=<redacted> --repo2-s3-region=eu-frankfurt-1 --repo2-s3-uri-style=path --no-repo2-storage-verify-tls --repo2-type=s3 --stanza=pg01
2024-05-28 09:32:00.705 P00   INFO: repo1: 16-1 remove archive, start = 000000010000000000000001, stop = 000000010000000000000002
2024-05-28 09:32:01.844 P00   INFO: expire command end: completed successfully (1144ms)
```

```sh
sudo -iu postgres pgbackrest info
sudo -iu postgres pgbackrest --repo=1 info
sudo -iu postgres pgbackrest --repo=2 info
```

```
stanza: pg01
    status: ok
    cipher: none

    db (current)
        wal archive min/max (16): 000000010000000000000006/00000001000000000000000C

        full backup: 20240528-093156F
            timestamp start/stop: 2024-05-28 09:31:56-04 / 2024-05-28 09:31:59-04
            wal start/stop: 000000010000000000000006 / 000000010000000000000006
            database size: 22.1MB, database backup size: 22.1MB
            repo1: backup size: 2.9MB

        full backup: 20240528-093312F
            timestamp start/stop: 2024-05-28 09:33:12-04 / 2024-05-28 09:33:15-04
            wal start/stop: 000000010000000000000008 / 000000010000000000000008
            database size: 22.1MB, database backup size: 22.1MB
            repo1: backup size: 2.9MB

        full backup: 20240528-093324F
            timestamp start/stop: 2024-05-28 09:33:24-04 / 2024-05-28 09:33:28-04
            wal start/stop: 00000001000000000000000A / 00000001000000000000000A
            database size: 22.1MB, database backup size: 22.1MB
            repo2: backup size: 2.9MB

        full backup: 20240528-093432F
            timestamp start/stop: 2024-05-28 09:34:32-04 / 2024-05-28 09:34:38-04
            wal start/stop: 00000001000000000000000C / 00000001000000000000000C
            database size: 22.1MB, database backup size: 22.1MB
            repo2: backup size: 2.9MB
```

## Backup on Dedicated Repository Host

### Environment

| Hostname   | IP Address  | OS            | Role                     | Verison |
| ---------- | ----------- | ------------- | ------------------------ | ------- |
| pg01       | 172.28.5.11 | Rocky Linux 9 | PostgreSQL Database      | 16.3    |
| pg02       | 172.28.5.12 | Rocky Linux 9 | PostgreSQL Database      | 16.3    |
| pgbackup01 | 172.28.5.15 | Rocky Linux 9 | pgBackRest Backup Server | 2.51    |

### pgBackRest Installation

>[!note]
>Install pgBackRest on all database and repository servers

[[pgBackRest 2.5x Installation]]

### pgBackRest Configuration
#### Repository Server Configuration

**Create pgBackRest user**

```bash
sudo groupadd pgbackrest
sudo adduser -gpgbackrest -n pgbackrest
```

**Create pgBackRest configuration file and directories**

```bash
sudo mkdir -p -m 770 /var/log/pgbackrest
sudo chown pgbackrest:pgbackrest /var/log/pgbackrest
sudo mkdir -p /etc/pgbackrest/conf.d
sudo touch /etc/pgbackrest/pgbackrest.conf
sudo chmod 640 /etc/pgbackrest/pgbackrest.conf
sudo chown -R pgbackrest:pgbackrest /etc/pgbackrest/
```

**Create the pgBackRest repository**

```bash
sudo mkdir -p /backup/pgbackrest
sudo chmod 750 /backup/pgbackrest
sudo chown pgbackrest:pgbackrest /backup/pgbackrest
```

**Repository Encryption**

```bash
# repo1-cipher-pass
sudo openssl rand -base64 48
6S7bJ8VBfGRbekNUkfIt4wzA8e2oCRdJUpehdPJ1YoOmtDCU5emCiB3/u2ya5FzA
```

**Edit pgbackrest.conf configuration file**

```sh
cat << EOF | tee "/etc/pgbackrest/pgbackrest.conf"
[global]
repo1-path=/backup/pgbackrest
repo1-retention-full=2
repo1-cipher-pass=6S7bJ8VBfGRbekNUkfIt4wzA8e2oCRdJUpehdPJ1YoOmtDCU5emCiB3/u2ya5FzA
repo1-cipher-type=aes-256-cbc
repo1-block=y
repo1-bundle=y

log-level-console=info
log-level-file=detail
process-max=2
start-fast=y
delta=y
EOF
```

#### PostgreSQL Server Configuration

**Create pgBackRest configuration file and directories**

```bash
sudo mkdir -p -m 770 /var/log/pgbackrest
sudo chown postgres:postgres /var/log/pgbackrest
sudo mkdir -p /etc/pgbackrest/conf.d
sudo touch /etc/pgbackrest/pgbackrest.conf
sudo chmod 640 /etc/pgbackrest/pgbackrest.conf
sudo chown -R postgres:postgres /etc/pgbackrest/
```

**PostgreSQL parameter configuraitons**

```bash
sudo -u postgres psql -c "select name, setting from pg_settings where name in ('archive_command','archive_mode','log_filename','max_wal_senders','wal_level','listen_addresses');"

      name       |      setting
-----------------+-------------------
 archive_command | (disabled)
 archive_mode    | off
 log_filename    | postgresql-%a.log
 max_wal_senders | 10
 wal_level       | replica
listen_addresses | localhost
```

>[!note]
>Change "--stanza=pg01"

```bash
sudo -u postgres psql <<EOF
alter system set archive_command to 'pgbackrest --stanza=pg01 archive-push %p';
alter system set archive_mode=on;
alter system set log_filename='postgresql.log';
-- alter system set max_wal_senders = 3;
alter system set wal_level = replica;
alter system set listen_addresses = '*';
EOF
```

**Restart or reload PostgreSQL service**

```bash
postgres=# SELECT pg_reload_conf();
 pg_reload_conf
----------------
 t

postgres=# select name, setting, pending_restart from pg_settings where pending_restart;
     name     | setting | pending_restart
--------------+---------+-----------------
 archive_mode | off     | t
```

```bash
sudo systemctl restart postgresql-16.service
```

### pgBackRest enable communication between the hosts

#### Option 1: Setup Passwordless SSH

**repository ⇒**
```bash
sudo -u pgbackrest ssh-keygen -f /home/pgbackrest/.ssh/id_rsa -t rsa -b 4096 -N ""
sudo -iu pgbackrest ssh-copy-id -i /home/pgbackrest/.ssh/id_rsa.pub postgres@pg01
sudo -iu pgbackrest ssh-copy-id -i /home/pgbackrest/.ssh/id_rsa.pub postgres@pg02
```

**pg01-pg02 ⇒**
```bash
sudo -u postgres ssh-keygen -f /var/lib/pgsql/.ssh/id_rsa -t rsa -b 4096 -N ""
sudo -iu postgres ssh-copy-id -i /var/lib/pgsql/.ssh/id_rsa.pub pgbackrest@pgbackup01
```

Test that connections can be made from **repository** to **pgmel34** and vice versa.

**repository ⇒** Test connection from **repository** to **pg01**
```bash
sudo -u pgbackrest ssh postgres@pg01 date
sudo -u pgbackrest ssh postgres@pg02 date
```

**pg01-pg02 ⇒** Test connection from **pg01** to **repository**
```bash
sudo -u postgres ssh pgbackrest@pgbackup01 date
```

**Edit pgbackrest.conf configuration file**

**repository ⇒**
```sh
cat << EOF | tee "/etc/pgbackrest/conf.d/pg01.conf"
[pg01]
pg1-host=pg01
pg1-path=/var/lib/pgsql/16/data
EOF

cat << EOF | tee "/etc/pgbackrest/conf.d/pg02.conf"
[pg02]
pg1-host=pg02
pg1-path=/var/lib/pgsql/16/data
EOF

chown -R pgbackrest:pgbackrest /etc/pgbackrest/conf.d/
```

**pg01-pg02 ⇒**
```sh
cat << EOF | tee "/etc/pgbackrest/pgbackrest.conf"
[global]
repo1-host=pgbackup01

process-max=2
log-level-console=info
log-level-file=detail
start-fast=y
delta=y
EOF
```

**pg01 ⇒**
```sh
cat << EOF | tee "/etc/pgbackrest/conf.d/pg01.conf"
[pg01]
pg1-path=/var/lib/pgsql/16/data
EOF
chown -R postgres:postgres /etc/pgbackrest/conf.d/
```

**pg02 ⇒**
```sh
cat << EOF | tee "/etc/pgbackrest/conf.d/pg02.conf"
[pg02]
pg1-path=/var/lib/pgsql/16/data
EOF
chown -R postgres:postgres /etc/pgbackrest/conf.d/
```

**Create and check stanza**

```sh
sudo -u pgbackrest pgbackrest --stanza=pg01 stanza-create
sudo -u pgbackrest pgbackrest --stanza=pg02 stanza-create
```

```
2024-05-28 10:54:01.276 P00   INFO: stanza-create command begin 2.52: --exec-id=1595-6ff8d756 --log-level-console=info --log-level-file=detail --pg1-host=pg01 --pg1-path=/var/lib/pgsql/16/data --repo1-cipher-pass=<redacted> --repo1-cipher-type=aes-256-cbc --repo1-path=/backup/pgbackrest --stanza=pg01
2024-05-28 10:54:02.038 P00   INFO: stanza-create for stanza 'pg01' on repo1
2024-05-28 10:54:02.145 P00   INFO: stanza-create command end: completed successfully (871ms)
```

```sh
sudo -u pgbackrest pgbackrest --stanza=pg01 check
sudo -u pgbackrest pgbackrest --stanza=pg02 check
```

```
2024-05-28 10:54:19.529 P00   INFO: check command begin 2.52: --exec-id=1602-3eebec63 --log-level-console=info --log-level-file=detail --pg1-host=pg01 --pg1-path=/var/lib/pgsql/16/data --repo1-cipher-pass=<redacted> --repo1-cipher-type=aes-256-cbc --repo1-path=/backup/pgbackrest --stanza=pg01
2024-05-28 10:54:20.285 P00   INFO: check repo1 configuration (primary)
2024-05-28 10:54:20.487 P00   INFO: check repo1 archive for WAL (primary)
2024-05-28 10:54:21.088 P00   INFO: WAL segment 000000010000000000000001 successfully archived to '/backup/pgbackrest/archive/pg01/16-1/0000000100000000/000000010000000000000001-c2d8e71823577905d72faf049cf073652aa04191.gz' on repo1
2024-05-28 10:54:21.188 P00   INFO: check command end: completed successfully (1661ms)
```

**Backup**

```sh
sudo -iu pgbackrest pgbackrest --stanza=pg01 --type=full backup
sudo -iu pgbackrest pgbackrest --stanza=pg02 --type=full backup
```

```
2024-05-28 10:54:54.581 P00   INFO: backup command begin 2.52: --compress-type=gz --delta --exec-id=1643-3e7b5a55 --log-level-console=info --log-level-file=detail --pg1-host=pg01 --pg1-path=/var/lib/pgsql/16/data --process-max=2 --repo1-block --repo1-bundle --repo1-cipher-pass=<redacted> --repo1-cipher-type=aes-256-cbc --repo1-path=/backup/pgbackrest --repo1-retention-full=2 --stanza=pg01 --start-fast --type=full
2024-05-28 10:54:55.440 P00   INFO: execute non-exclusive backup start: backup begins after the requested immediate checkpoint completes
2024-05-28 10:54:55.942 P00   INFO: backup start archive = 000000010000000000000003, lsn = 0/3000028
2024-05-28 10:54:55.942 P00   INFO: check archive for prior segment 000000010000000000000002
2024-05-28 10:54:58.377 P00   INFO: execute non-exclusive backup stop and wait for all WAL segments to archive
2024-05-28 10:54:58.578 P00   INFO: backup stop archive = 000000010000000000000003, lsn = 0/3000138
2024-05-28 10:54:58.583 P00   INFO: check archive for segment(s) 000000010000000000000003:000000010000000000000003
2024-05-28 10:54:58.992 P00   INFO: new backup label = 20240528-105455F
2024-05-28 10:54:59.020 P00   INFO: full backup size = 22.1MB, file total = 969
2024-05-28 10:54:59.020 P00   INFO: backup command end: completed successfully (4441ms)
2024-05-28 10:54:59.021 P00   INFO: expire command begin 2.52: --exec-id=1643-3e7b5a55 --log-level-console=info --log-level-file=detail --repo1-cipher-pass=<redacted> --repo1-cipher-type=aes-256-cbc --repo1-path=/backup/pgbackrest --repo1-retention-full=2 --stanza=pg01
2024-05-28 10:54:59.024 P00   INFO: expire command end: completed successfully (4ms)
```

```sh
sudo -iu pgbackrest pgbackrest info
sudo -iu pgbackrest pgbackrest --stanza=pg01 info
```

```
stanza: pg01
    status: ok
    cipher: aes-256-cbc

    db (current)
        wal archive min/max (16): 000000010000000000000001/000000010000000000000003

        full backup: 20240528-105455F
            timestamp start/stop: 2024-05-28 10:54:55-04 / 2024-05-28 10:54:58-04
            wal start/stop: 000000010000000000000003 / 000000010000000000000003
            database size: 22.1MB, database backup size: 22.1MB
            repo1: backup size: 3.0MB

stanza: pg02
    status: ok
    cipher: aes-256-cbc

    db (current)
        wal archive min/max (16): 000000010000000000000001/000000010000000000000003

        full backup: 20240528-105511F
            timestamp start/stop: 2024-05-28 10:55:11-04 / 2024-05-28 10:55:14-04
            wal start/stop: 000000010000000000000003 / 000000010000000000000003
            database size: 22.1MB, database backup size: 22.1MB
            repo1: backup size: 3.0MB
```

#### Option 2: Setup TLS

**Create environment variables to simplify the config file creation:**

**repository-pg01-pg02: ⇒**
```sh
export REPO_SRV_NAME="pgbackup01"
export NODE_NAME=`hostname -f`
export NODE1_NAME="pg01"
export NODE2_NAME="pg02"
export CA_PATH="/etc/pgbackrest/certs"
```

**Edit pgbackrest.conf configuration file**

**repository: ⇒**
```sh
cat <<EOF >> /etc/pgbackrest/pgbackrest.conf

########## Server TLS options ##########
tls-server-address=*
tls-server-cert-file=${CA_PATH}/${REPO_SRV_NAME}.crt
tls-server-key-file=${CA_PATH}/${REPO_SRV_NAME}.key
tls-server-ca-file=${CA_PATH}/ca.crt 

### Auth entry ###
tls-server-auth=${NODE1_NAME}=${NODE1_NAME}
tls-server-auth=${NODE2_NAME}=${NODE2_NAME}
EOF
```

**repository: ⇒**
```sh
cat << EOF | tee "/etc/pgbackrest/conf.d/pg01.conf"
[${NODE1_NAME}]
pg1-host=${NODE1_NAME}
pg1-host-port=8432
pg1-port=5432
pg1-path=/var/lib/pgsql/16/data
pg1-host-type=tls
pg1-host-cert-file=${CA_PATH}/${REPO_SRV_NAME}.crt
pg1-host-key-file=${CA_PATH}/${REPO_SRV_NAME}.key
pg1-host-ca-file=${CA_PATH}/ca.crt
EOF

cat << EOF | tee "/etc/pgbackrest/conf.d/pg02.conf"
[${NODE2_NAME}]
pg1-host=${NODE2_NAME}
pg1-host-port=8432
pg1-port=5432
pg1-path=/var/lib/pgsql/16/data
pg1-host-type=tls
pg1-host-cert-file=${CA_PATH}/${REPO_SRV_NAME}.crt
pg1-host-key-file=${CA_PATH}/${REPO_SRV_NAME}.key
pg1-host-ca-file=${CA_PATH}/ca.crt
EOF

chown -R pgbackrest:pgbackrest /etc/pgbackrest/conf.d/
```

**pg01-pg02 ⇒**
```sh
cat << EOF | tee "/etc/pgbackrest/pgbackrest.conf"
[global]
repo1-host=${REPO_SRV_NAME}
repo1-host-user=postgres
repo1-host-type=tls
repo1-host-cert-file=${CA_PATH}/${NODE_NAME}.crt
repo1-host-key-file=${CA_PATH}/${NODE_NAME}.key
repo1-host-ca-file=${CA_PATH}/ca.crt

# general options
process-max=2
log-level-console=info
log-level-file=detail
start-fast=y
delta=y

# tls server options
tls-server-address=*
tls-server-cert-file=${CA_PATH}/${NODE_NAME}.crt
tls-server-key-file=${CA_PATH}/${NODE_NAME}.key
tls-server-ca-file=${CA_PATH}/ca.crt
tls-server-auth=${REPO_SRV_NAME}=${NODE_NAME}
EOF
```

**pg01-pg02 ⇒**
```sh
cat << EOF | tee "/etc/pgbackrest/conf.d/${NODE_NAME}.conf"
[${NODE_NAME}]
pg1-path=/var/lib/pgsql/16/data
EOF
chown -R postgres:postgres /etc/pgbackrest/conf.d/
```

**Create the certificate files**

**repository: ⇒**
```sh
mkdir -p ${CA_PATH}
openssl req -new -x509 -days 365 -nodes -out ${CA_PATH}/ca.crt -keyout ${CA_PATH}/ca.key -subj "/CN=root-ca"

for node in ${REPO_SRV_NAME} ${NODE1_NAME} ${NODE2_NAME} ${NODE3_NAME}
do
openssl req -new -nodes -out ${CA_PATH}/$node.csr -keyout ${CA_PATH}/$node.key -subj "/CN=$node";
done

for node in ${REPO_SRV_NAME} ${NODE1_NAME} ${NODE2_NAME} ${NODE3_NAME}
do
openssl x509 -req -in ${CA_PATH}/$node.csr -days 365 -CA ${CA_PATH}/ca.crt -CAkey ${CA_PATH}/ca.key -CAcreateserial -out ${CA_PATH}/$node.crt;
done

rm -f ${CA_PATH}/*.csr
chown pgbackrest:pgbackrest -R ${CA_PATH}
chmod 0600 ${CA_PATH}/*
```

Then, you have to deploy it on each server (`ca.crt` + `server_name.crt` + `server_name.key`).

**pg01-pg02: ⇒**
```bash
mkdir -p ${CA_PATH}
scp pgbackrest@${REPO_SRV_NAME}:${CA_PATH}/{ca.crt,`hostname`.*} ${CA_PATH}/
chown postgres:postgres -R ${CA_PATH}
chmod 0600 ${CA_PATH}/* 
```

```bash
ls

ca.crt	pg01.crt  pg01.key
```

**Create the `pgbackrest` daemon service**

**repository: ⇒**
```sh
cat << EOF | tee "/etc/systemd/system/pgbackrest.service"
[Unit]
Description=pgBackRest Server
Documentation=https://pgbackrest.org/configuration.html
After=network.target
StartLimitIntervalSec=0

[Service]
Type=simple

User=pgbackrest
Group=pgbackrest

Restart=always
RestartSec=1

ExecStart=/usr/bin/pgbackrest server
ExecReload=kill -HUP $MAINPID

[Install]
WantedBy=multi-user.target
EOF
```

**pg01-pg02:**
```sh
cat << EOF | tee "/etc/systemd/system/pgbackrest.service"
[Unit]
Description=pgBackRest Server
Documentation=https://pgbackrest.org/configuration.html
After=network.target
StartLimitIntervalSec=0

[Service]
Type=simple

User=postgres
Group=postgres

Restart=always
RestartSec=1

ExecStart=/usr/bin/pgbackrest server
ExecReload=kill -HUP $MAINPID

[Install]
WantedBy=multi-user.target
EOF
```

**Start pgBackRest service on all database and repository servers**

```bash
sudo systemctl daemon-reload
sudo systemctl enable --now pgbackrest
sudo systemctl status pgbackrest --no-pager

sudo -u postgres pgbackrest server-ping
```

**Create and check stanza**

```sh
sudo -u pgbackrest pgbackrest --stanza=pg01 stanza-create
sudo -u pgbackrest pgbackrest --stanza=pg02 stanza-create
```

```
2024-05-28 11:55:58.299 P00   INFO: stanza-create command begin 2.52: --exec-id=2915-ab6fa826 --log-level-console=info --log-level-file=detail --pg1-host=pg01 --pg1-host-ca-file=/etc/pgbackrest/certs/ca.crt --pg1-host-cert-file=/etc/pgbackrest/certs/pgbackup01.crt --pg1-host-key-file=/etc/pgbackrest/certs/pgbackup01.key --pg1-host-port=8432 --pg1-host-type=tls --pg1-path=/var/lib/pgsql/16/data --pg1-port=5432 --repo1-cipher-pass=<redacted> --repo1-cipher-type=aes-256-cbc --repo1-path=/backup/pgbackrest --stanza=pg01
2024-05-28 11:55:58.913 P00   INFO: stanza-create for stanza 'pg01' on repo1
2024-05-28 11:55:58.919 P00   INFO: stanza-create command end: completed successfully (622ms)
```

```sh
sudo -u pgbackrest pgbackrest --stanza=pg01 check
sudo -u pgbackrest pgbackrest --stanza=pg02 check
```

```
2024-05-28 11:56:15.729 P00   INFO: check command begin 2.52: --exec-id=2927-0178253a --log-level-console=info --log-level-file=detail --pg1-host=pg01 --pg1-host-ca-file=/etc/pgbackrest/certs/ca.crt --pg1-host-cert-file=/etc/pgbackrest/certs/pgbackup01.crt --pg1-host-key-file=/etc/pgbackrest/certs/pgbackup01.key --pg1-host-port=8432 --pg1-host-type=tls --pg1-path=/var/lib/pgsql/16/data --pg1-port=5432 --repo1-cipher-pass=<redacted> --repo1-cipher-type=aes-256-cbc --repo1-path=/backup/pgbackrest --stanza=pg01
2024-05-28 11:56:16.342 P00   INFO: check repo1 configuration (primary)
2024-05-28 11:56:16.543 P00   INFO: check repo1 archive for WAL (primary)
2024-05-28 11:56:16.644 P00   INFO: WAL segment 000000010000000000000004 successfully archived to '/backup/pgbackrest/archive/pg01/16-1/0000000100000000/000000010000000000000004-3c0280b1da0a5abcaba4d9f69cc3ead90b9793ef.gz' on repo1
2024-05-28 11:56:16.644 P00   INFO: check command end: completed successfully (917ms)
```

**Backup**

```sh
sudo -iu pgbackrest pgbackrest --stanza=pg01 --type=full backup
sudo -iu pgbackrest pgbackrest --stanza=pg02 --type=full backup
```

```
2024-05-28 11:56:31.720 P00   INFO: backup command begin 2.52: --compress-type=gz --delta --exec-id=2930-6b0da1f5 --log-level-console=info --log-level-file=detail --pg1-host=pg01 --pg1-host-ca-file=/etc/pgbackrest/certs/ca.crt --pg1-host-cert-file=/etc/pgbackrest/certs/pgbackup01.crt --pg1-host-key-file=/etc/pgbackrest/certs/pgbackup01.key --pg1-host-port=8432 --pg1-host-type=tls --pg1-path=/var/lib/pgsql/16/data --pg1-port=5432 --process-max=2 --repo1-block --repo1-bundle --repo1-cipher-pass=<redacted> --repo1-cipher-type=aes-256-cbc --repo1-path=/backup/pgbackrest --repo1-retention-full=2 --stanza=pg01 --start-fast --type=full
2024-05-28 11:56:32.435 P00   INFO: execute non-exclusive backup start: backup begins after the requested immediate checkpoint completes
2024-05-28 11:56:32.937 P00   INFO: backup start archive = 000000010000000000000006, lsn = 0/6000028
2024-05-28 11:56:32.937 P00   INFO: check archive for prior segment 000000010000000000000005
2024-05-28 11:56:34.003 P00   INFO: execute non-exclusive backup stop and wait for all WAL segments to archive
2024-05-28 11:56:34.204 P00   INFO: backup stop archive = 000000010000000000000006, lsn = 0/6000100
2024-05-28 11:56:34.206 P00   INFO: check archive for segment(s) 000000010000000000000006:000000010000000000000006
2024-05-28 11:56:34.213 P00   INFO: new backup label = 20240528-115632F
2024-05-28 11:56:34.242 P00   INFO: full backup size = 22.1MB, file total = 969
2024-05-28 11:56:34.242 P00   INFO: backup command end: completed successfully (2524ms)
2024-05-28 11:56:34.243 P00   INFO: expire command begin 2.52: --exec-id=2930-6b0da1f5 --log-level-console=info --log-level-file=detail --repo1-cipher-pass=<redacted> --repo1-cipher-type=aes-256-cbc --repo1-path=/backup/pgbackrest --repo1-retention-full=2 --stanza=pg01
2024-05-28 11:56:34.246 P00   INFO: expire command end: completed successfully (4ms)
```

```sh
sudo -iu pgbackrest pgbackrest info
sudo -iu pgbackrest pgbackrest --stanza=pg01 info
sudo -iu pgbackrest pgbackrest --stanza=pg02 info
```

```
stanza: pg01
    status: ok
    cipher: aes-256-cbc

    db (current)
        wal archive min/max (16): 000000010000000000000004/000000010000000000000006

        full backup: 20240528-115632F
            timestamp start/stop: 2024-05-28 11:56:32-04 / 2024-05-28 11:56:34-04
            wal start/stop: 000000010000000000000006 / 000000010000000000000006
            database size: 22.1MB, database backup size: 22.1MB
            repo1: backup size: 3.0MB

stanza: pg02
    status: ok
    cipher: aes-256-cbc

    db (current)
        wal archive min/max (16): 000000010000000000000004/000000010000000000000005

        full backup: 20240528-115637F
            timestamp start/stop: 2024-05-28 11:56:37-04 / 2024-05-28 11:56:40-04
            wal start/stop: 000000010000000000000005 / 000000010000000000000005
            database size: 22.1MB, database backup size: 22.1MB
            repo1: backup size: 3.0MB
```

### S3-Compatible Object Store

**pgBackRest Configuration**

**repository: ⇒**
```sh
cat <<EOF >> /etc/pgbackrest/pgbackrest.conf

########## OCI S3-compatible bucket repository ##########
repo2-type=s3
repo2-storage-verify-tls=n
repo2-s3-endpoint=https://frkaqewuw7qz.compat.objectstorage.eu-frankfurt-1.oraclecloud.com
repo2-s3-uri-style=path
repo2-s3-bucket=ocigelibolbucket
repo2-s3-key=3167461162edd5f0d67b092fd777bae183e75194
repo2-s3-key-secret=mqey2WEBNEpnLhN6t/2E3vYMchLhjY5LTHdCP7JjAZk=
repo2-s3-region=eu-frankfurt-1
repo2-path=/pgbackrest
repo2-retention-full=2
repo2-block=y
repo2-bundle=y
repo2-cipher-pass=6S7bJ8VBfGRbekNUkfIt4wzA8e2oCRdJUpehdPJ1YoOmtDCU5emCiB3/u2ya5FzA
repo2-cipher-type=aes-256-cbc
EOF
```

**pg01: ⇒**
```sh
cat <<EOF >> /etc/pgbackrest/pgbackrest.conf

########## OCI S3-compatible bucket repository ##########
repo2-type=s3
repo2-storage-verify-tls=n
repo2-s3-endpoint=https://frkaqewuw7qz.compat.objectstorage.eu-frankfurt-1.oraclecloud.com
repo2-s3-uri-style=path
repo2-s3-bucket=ocigelibolbucket
repo2-s3-key=3167461162edd5f0d67b092fd777bae183e75194
repo2-s3-key-secret=mqey2WEBNEpnLhN6t/2E3vYMchLhjY5LTHdCP7JjAZk=
repo2-s3-region=eu-frankfurt-1
repo2-path=/pgbackrest
repo2-retention-full=2
repo2-block=y
repo2-bundle=y
repo2-cipher-pass=6S7bJ8VBfGRbekNUkfIt4wzA8e2oCRdJUpehdPJ1YoOmtDCU5emCiB3/u2ya5FzA
repo2-cipher-type=aes-256-cbc
EOF
```

**Create and check stanza**

```sh
sudo -u pgbackrest pgbackrest --stanza=pg01 stanza-create
```

```
2024-05-28 12:01:49.728 P00   INFO: stanza-create command begin 2.52: --exec-id=3074-cd42a6a9 --log-level-console=info --log-level-file=detail --pg1-host=pg01 --pg1-host-ca-file=/etc/pgbackrest/certs/ca.crt --pg1-host-cert-file=/etc/pgbackrest/certs/pgbackup01.crt --pg1-host-key-file=/etc/pgbackrest/certs/pgbackup01.key --pg1-host-port=8432 --pg1-host-type=tls --pg1-path=/var/lib/pgsql/16/data --pg1-port=5432 --repo1-cipher-pass=<redacted> --repo2-cipher-pass=<redacted> --repo1-cipher-type=aes-256-cbc --repo2-cipher-type=aes-256-cbc --repo1-path=/backup/pgbackrest --repo2-path=/pgbackrest --repo2-s3-bucket=ocigelibolbucket --repo2-s3-endpoint=https://frkaqewuw7qz.compat.objectstorage.eu-frankfurt-1.oraclecloud.com --repo2-s3-key=<redacted> --repo2-s3-key-secret=<redacted> --repo2-s3-region=eu-frankfurt-1 --repo2-s3-uri-style=path --no-repo2-storage-verify-tls --repo2-type=s3 --stanza=pg01
2024-05-28 12:01:50.342 P00   INFO: stanza-create for stanza 'pg01' on repo1
2024-05-28 12:01:50.343 P00   INFO: stanza 'pg01' already exists on repo1 and is valid
2024-05-28 12:01:50.343 P00   INFO: stanza-create for stanza 'pg01' on repo2
2024-05-28 12:01:52.200 P00   INFO: stanza-create command end: completed successfully (2474ms)
```

```sh
sudo -u pgbackrest pgbackrest --stanza=pg01 check
```

```
2024-05-28 13:06:14.193 P00   INFO: check command begin 2.52: --exec-id=3950-1dba2b44 --log-level-console=info --log-level-file=detail --pg1-host=pg01 --pg1-host-ca-file=/etc/pgbackrest/certs/ca.crt --pg1-host-cert-file=/etc/pgbackrest/certs/pgbackup01.crt --pg1-host-key-file=/etc/pgbackrest/certs/pgbackup01.key --pg1-host-port=8432 --pg1-host-type=tls --pg1-path=/var/lib/pgsql/16/data --pg1-port=5432 --repo1-cipher-pass=<redacted> --repo2-cipher-pass=<redacted> --repo1-cipher-type=aes-256-cbc --repo2-cipher-type=aes-256-cbc --repo1-path=/backup/pgbackrest --repo2-path=/pgbackrest --repo2-s3-bucket=ocigelibolbucket --repo2-s3-endpoint=https://frkaqewuw7qz.compat.objectstorage.eu-frankfurt-1.oraclecloud.com --repo2-s3-key=<redacted> --repo2-s3-key-secret=<redacted> --repo2-s3-region=eu-frankfurt-1 --repo2-s3-uri-style=path --no-repo2-storage-verify-tls --repo2-type=s3 --stanza=pg01
2024-05-28 13:06:14.807 P00   INFO: check repo1 configuration (primary)
2024-05-28 13:06:14.807 P00   INFO: check repo2 configuration (primary)
2024-05-28 13:06:16.123 P00   INFO: check repo1 archive for WAL (primary)
2024-05-28 13:06:17.224 P00   INFO: WAL segment 00000001000000000000000F successfully archived to '/backup/pgbackrest/archive/pg01/16-1/0000000100000000/00000001000000000000000F-beeaaf109549c99957d423a5c0e8e4666e734813.gz' on repo1
2024-05-28 13:06:17.224 P00   INFO: check repo2 archive for WAL (primary)
2024-05-28 13:06:17.323 P00   INFO: WAL segment 00000001000000000000000F successfully archived to '/pgbackrest/archive/pg01/16-1/0000000100000000/00000001000000000000000F-beeaaf109549c99957d423a5c0e8e4666e734813.gz' on repo2
2024-05-28 13:06:17.323 P00   INFO: check command end: completed successfully (3132ms)
```

**Backup**

```sh
sudo -iu pgbackrest pgbackrest --stanza=pg01 --type=full backup
sudo -iu pgbackrest pgbackrest --stanza=pg01 --type=full backup --repo=1
sudo -iu pgbackrest pgbackrest --stanza=pg01 --type=full backup --repo=2
```

```
2024-05-28 13:06:44.876 P00   INFO: backup command begin 2.52: --compress-type=gz --delta --exec-id=3972-af426f21 --log-level-console=info --log-level-file=detail --pg1-host=pg01 --pg1-host-ca-file=/etc/pgbackrest/certs/ca.crt --pg1-host-cert-file=/etc/pgbackrest/certs/pgbackup01.crt --pg1-host-key-file=/etc/pgbackrest/certs/pgbackup01.key --pg1-host-port=8432 --pg1-host-type=tls --pg1-path=/var/lib/pgsql/16/data --pg1-port=5432 --process-max=2 --repo1-block --repo2-block --repo1-bundle --repo2-bundle --repo1-cipher-pass=<redacted> --repo2-cipher-pass=<redacted> --repo1-cipher-type=aes-256-cbc --repo2-cipher-type=aes-256-cbc --repo1-path=/backup/pgbackrest --repo2-path=/pgbackrest --repo1-retention-full=2 --repo2-retention-full=2 --repo2-s3-bucket=ocigelibolbucket --repo2-s3-endpoint=https://frkaqewuw7qz.compat.objectstorage.eu-frankfurt-1.oraclecloud.com --repo2-s3-key=<redacted> --repo2-s3-key-secret=<redacted> --repo2-s3-region=eu-frankfurt-1 --repo2-s3-uri-style=path --no-repo2-storage-verify-tls --repo2-type=s3 --stanza=pg01 --start-fast --type=full
2024-05-28 13:06:44.876 P00   INFO: repo option not specified, defaulting to repo1
2024-05-28 13:06:45.590 P00   INFO: execute non-exclusive backup start: backup begins after the requested immediate checkpoint completes
2024-05-28 13:06:46.093 P00   INFO: backup start archive = 000000010000000000000011, lsn = 0/11000028
2024-05-28 13:06:46.093 P00   INFO: check archive for prior segment 000000010000000000000010
2024-05-28 13:06:48.007 P00   INFO: execute non-exclusive backup stop and wait for all WAL segments to archive
2024-05-28 13:06:48.207 P00   INFO: backup stop archive = 000000010000000000000011, lsn = 0/11000100
2024-05-28 13:06:48.209 P00   INFO: check archive for segment(s) 000000010000000000000011:000000010000000000000011
2024-05-28 13:06:48.818 P00   INFO: new backup label = 20240528-130645F
2024-05-28 13:06:48.845 P00   INFO: full backup size = 22.1MB, file total = 969
2024-05-28 13:06:48.845 P00   INFO: backup command end: completed successfully (3972ms)
2024-05-28 13:06:48.845 P00   INFO: expire command begin 2.52: --exec-id=3972-af426f21 --log-level-console=info --log-level-file=detail --repo1-cipher-pass=<redacted> --repo2-cipher-pass=<redacted> --repo1-cipher-type=aes-256-cbc --repo2-cipher-type=aes-256-cbc --repo1-path=/backup/pgbackrest --repo2-path=/pgbackrest --repo1-retention-full=2 --repo2-retention-full=2 --repo2-s3-bucket=ocigelibolbucket --repo2-s3-endpoint=https://frkaqewuw7qz.compat.objectstorage.eu-frankfurt-1.oraclecloud.com --repo2-s3-key=<redacted> --repo2-s3-key-secret=<redacted> --repo2-s3-region=eu-frankfurt-1 --repo2-s3-uri-style=path --no-repo2-storage-verify-tls --repo2-type=s3 --stanza=pg01
2024-05-28 13:06:48.849 P00   INFO: repo1: 16-1 remove archive, start = 000000010000000000000004, stop = 000000010000000000000005
2024-05-28 13:06:49.967 P00   INFO: expire command end: completed successfully (1122ms)
```

```sh
sudo -iu pgbackrest pgbackrest info
sudo -iu pgbackrest pgbackrest --repo=1 info
sudo -iu pgbackrest pgbackrest --repo=2 info
```

```
stanza: pg01
    status: ok
    cipher: aes-256-cbc

    db (current)
        wal archive min/max (16): 00000001000000000000000F/000000010000000000000015

        full backup: 20240528-130645F
            timestamp start/stop: 2024-05-28 13:06:45-04 / 2024-05-28 13:06:48-04
            wal start/stop: 000000010000000000000011 / 000000010000000000000011
            database size: 22.1MB, database backup size: 22.1MB
            repo1: backup size: 3.0MB

        full backup: 20240528-130651F
            timestamp start/stop: 2024-05-28 13:06:51-04 / 2024-05-28 13:06:55-04
            wal start/stop: 000000010000000000000012 / 000000010000000000000013
            database size: 22.1MB, database backup size: 22.1MB
            repo1: backup size: 3.0MB

        full backup: 20240528-130658F
            timestamp start/stop: 2024-05-28 13:06:58-04 / 2024-05-28 13:07:05-04
            wal start/stop: 000000010000000000000014 / 000000010000000000000015
            database size: 22.1MB, database backup size: 22.1MB
            repo2: backup size: 3.0MB

stanza: pg02
    status: mixed
        repo1: ok
        repo2: error (missing stanza path)
    cipher: aes-256-cbc

    db (current)
        wal archive min/max (16): 000000010000000000000004/000000010000000000000005

        full backup: 20240528-115637F
            timestamp start/stop: 2024-05-28 11:56:37-04 / 2024-05-28 11:56:40-04
            wal start/stop: 000000010000000000000005 / 000000010000000000000005
            database size: 22.1MB, database backup size: 22.1MB
            repo1: backup size: 3.0MB
```

## Restore on Same Host

**pg01: ⇒**
```sh
systemctl stop postgresql-16
sudo find /var/lib/pgsql/16/data -mindepth 1 -delete
systemctl start postgresql-16

Job for postgresql-16.service failed because the control process exited with error code.
See "systemctl status postgresql-16.service" and "journalctl -xeu postgresql-16.service" for details.
```

```sh
sudo -u postgres pgbackrest --stanza=pg01 restore
```

```
2024-05-28 13:15:21.436 P00   INFO: restore command begin 2.52: --exec-id=4466-37a7702d --log-level-console=info --log-level-file=detail --pg1-path=/var/lib/pgsql/16/data --process-max=2 --repo2-cipher-pass=<redacted> --repo2-cipher-type=aes-256-cbc --repo1-host=pgbackup01 --repo1-host-ca-file=/etc/pgbackrest/certs/ca.crt --repo1-host-cert-file=/etc/pgbackrest/certs/pg01.crt --repo1-host-key-file=/etc/pgbackrest/certs/pg01.key --repo1-host-type=tls --repo1-host-user=postgres --repo2-path=/pgbackrest --repo2-s3-bucket=ocigelibolbucket --repo2-s3-endpoint=https://frkaqewuw7qz.compat.objectstorage.eu-frankfurt-1.oraclecloud.com --repo2-s3-key=<redacted> --repo2-s3-key-secret=<redacted> --repo2-s3-region=eu-frankfurt-1 --repo2-s3-uri-style=path --no-repo2-storage-verify-tls --repo2-type=s3 --stanza=pg01
2024-05-28 13:15:21.450 P00   INFO: repo1: restore backup set 20240528-130651F, recovery will start at 2024-05-28 13:06:51
2024-05-28 13:15:23.045 P00   INFO: write updated /var/lib/pgsql/16/data/postgresql.auto.conf
2024-05-28 13:15:23.049 P00   INFO: restore global/pg_control (performed last to ensure aborted restores cannot be started)
2024-05-28 13:15:23.049 P00   INFO: restore size = 22.1MB, file total = 969
2024-05-28 13:15:23.049 P00   INFO: restore command end: completed successfully (1616ms)
```

```sh
systemctl start postgresql-16
systemctl status postgresql-16 --no-pager

● postgresql-16.service - PostgreSQL 16 database server
     Loaded: loaded (/usr/lib/systemd/system/postgresql-16.service; enabled; preset: disabled)
     Active: active (running) since Mon 2024-05-27 17:17:33 EDT; 30s ago
       Docs: https://www.postgresql.org/docs/16/static/
    Process: 1774 ExecStartPre=/usr/pgsql-16/bin/postgresql-16-check-db-dir ${PGDATA} (code=exited, status=0/SUCCESS)
   Main PID: 1779 (postgres)
      Tasks: 8 (limit: 22765)
     Memory: 82.0M
     CGroup: /docker/c7a3358ce92c21988f3bfd2cc2ddd2a3d0c259437f3703febb1f1b4cfc896a5b/system.slice/postgresql-16.service
             ├─1779 /usr/pgsql-16/bin/postgres -D /var/lib/pgsql/16/data/
             ├─1780 "postgres: logger "
             ├─1781 "postgres: checkpointer "
             ├─1782 "postgres: background writer "
             ├─1793 "postgres: walwriter "
             ├─1794 "postgres: autovacuum launcher "
             ├─1795 "postgres: archiver last was 00000002.history"
             └─1796 "postgres: logical replication launcher "

May 27 17:17:32 pgmel34 systemd[1]: Starting PostgreSQL 16 database server...
May 27 17:17:32 pgmel34 postgres[1779]: 2024-05-27 17:17:32.223 EDT [1779] LOG:  redirecting log output to logging collector process
May 27 17:17:32 pgmel34 postgres[1779]: 2024-05-27 17:17:32.223 EDT [1779] HINT:  Future log output will appear in directory "log".
May 27 17:17:33 pgmel34 systemd[1]: Started PostgreSQL 16 database server.
```

## Restore on a Different Host

In this scenario, we will test the backup by restoring it to the spare server. My spare server’s pgBackRest conf has the information about the repository host, repository path, repository host user, and required PostgreSQL version installed and access to the repository.

pgBackRest can be used entirely by command line parameters but having a configuration file has more convenience. Below is my spare server pgBackRest configuration file.

**pg03: ⇒**
```sh
# update
sudo dnf update -y

# timezone
sudo rm -rf /etc/localtime
sudo ln -s /usr/share/zoneinfo/America/New_York /etc/localtime

# chrony
sudo dnf install -y chrony
sudo systemctl enable --now chronyd

# Install the repository RPM:
sudo dnf install -y https://download.postgresql.org/pub/repos/yum/reporpms/EL-9-x86_64/pgdg-redhat-repo-latest.noarch.rpm

# Disable the built-in PostgreSQL module:
sudo dnf -qy module disable postgresql

# Install PostgreSQL:
sudo dnf install -y postgresql16-server postgresql16-contrib

# Install pgBackRest
sudo dnf install pgbackrest -y
```

**Create pgBackRest configuration file and directories**

```bash
sudo mkdir -p -m 770 /var/log/pgbackrest
sudo chown postgres:postgres /var/log/pgbackrest
sudo mkdir -p /etc/pgbackrest/conf.d
sudo touch /etc/pgbackrest/pgbackrest.conf
sudo chmod 640 /etc/pgbackrest/pgbackrest.conf
sudo chown -R postgres:postgres /etc/pgbackrest/
```

**pgBackRest Configuration**

```sh
cat << EOF | tee "/etc/pgbackrest/pgbackrest.conf"
[global]
repo1-host=pgbackupmel01
repo1-block=y
repo1-bundle=y

log-level-console=info
log-level-file=detail
process-max=2
compress-type=gz
start-fast=y
delta=y

[global:archive-push]  
compress-level=3
EOF
```

**Add below line to repository pgbackrest.conf and restart the pgBackRest service**

**repository:/etc/pgbackrest/pgbackrest.conf ⇒**
```
[global]
...
tls-server-auth=pgmel38=pgmel34
```

**repository:
```sh
sudo systemctl restart pgbackrest
```

**pgmel38:/etc/pgbackrest/pgbackrest.conf ⇒**
```bash
[global]
...
repo1-host-ca-file=/etc/pgbackrest/cert/ca.crt
repo1-host-cert-file=/etc/pgbackrest/cert/pg03.crt
repo1-host-key-file=/etc/pgbackrest/cert/pg03.key
repo1-host-type=tls
tls-server-address=*
tls-server-ca-file=/etc/pgbackrest/cert/ca.crt
tls-server-cert-file=/etc/pgbackrest/cert/pg03.crt
tls-server-key-file=/etc/pgbackrest/cert/pg03.key
#tls-server-auth=pgbackrestservername=stanzaname
tls-server-auth=pgbackup01=pg01
```

**pgmel38:/etc/pgbackrest/conf.d/pgmel34.conf ⇒**
```sh
cat << EOF | tee "/etc/pgbackrest/conf.d/pg03.conf"
[pg01]
pg1-path=/var/lib/pgsql/16/data
EOF
chown -R postgres:postgres /etc/pgbackrest/conf.d/
```

**Create a service file**

**pg03:**
```sh
cat << EOF | tee "/etc/systemd/system/pgbackrest.service"
[Unit]
Description=pgBackRest Server
Documentation=https://pgbackrest.org/configuration.html
After=network.target
StartLimitIntervalSec=0

[Service]
Type=simple

User=postgres
Group=postgres

Restart=always
RestartSec=1

ExecStart=/usr/bin/pgbackrest server
ExecReload=kill -HUP $MAINPID

[Install]
WantedBy=multi-user.target
EOF
```

**Start pgBackRest service on all database and repository servers**

```bash
sudo systemctl daemon-reload
sudo systemctl enable --now pgbackrest
sudo systemctl status pgbackrest --no-pager

sudo -u postgres pgbackrest server-ping
```

**Restore**

**pg03:**
```
sudo -u postgres pgbackrest --stanza=pg01 restore
```

```
WARN: --delta or --force specified but unable to find 'PG_VERSION' or 'backup.manifest' in '/var/lib/pgsql/16/data' to confirm that this is a valid $PGDATA directory. --delta and --force have been disabled and if any files exist in the destination directories the restore will be aborted.
2024-05-27 17:37:11.682 P00   INFO: repo1: restore backup set 20240527-171245F, recovery will start at 2024-05-27 17:12:45
2024-05-27 17:37:13.158 P00   INFO: write updated /var/lib/pgsql/16/data/postgresql.auto.conf
2024-05-27 17:37:13.163 P00   INFO: restore global/pg_control (performed last to ensure aborted restores cannot be started)
2024-05-27 17:37:13.164 P00   INFO: restore size = 22.1MB, file total = 969
2024-05-27 17:37:13.164 P00   INFO: restore command end: completed successfully (1497ms)
```

Edit

```
sudo -u postgres vi /var/lib/pgsql/16/data/postgresql.auto.conf

#archive_command = 'pgbackrest --stanza=pgmel34 archive-push %p'
archive_command = ''
```

**Start PostgreSQL service**

**pgmel38:**
```sh
sudo systemctl start postgresql-16

sudo -u postgres psql -c "select 1"

 ?column?
----------
        1
```

## Restore Point-in-Time Recovery

**pg01 ⇒ Create a table with very important data**
```sh
sudo -u postgres psql -Atc "select current_timestamp"

sleep 10

sudo -u postgres psql -c "begin; \
       create table important_table (message text); \
       insert into important_table values ('Important Data'); \
       commit; \
       select * from important_table;"

sleep 10

sudo -u postgres psql -Atc "select current_timestamp"
```

```
2024-05-28 13:41:54.341001-04

BEGIN
CREATE TABLE
INSERT 0 1
COMMIT
    message
----------------
 Important Data

2024-05-28 13:42:14.392062-04
```

It is important to represent the time as reckoned by PostgreSQL and to include timezone offsets. This reduces the possibility of unintended timezone conversions and an unexpected recovery result.

Now that the time has been recorded the table is dropped. In practice finding the exact time that the table was dropped is a lot harder than in this example. It may not be possible to find the exact time, but some forensic work should be able to get you close.

**pg-primary ⇒ Drop the important table**
```sh
sudo -u postgres psql -c "begin; \
       drop table important_table; \
       commit; \
       select * from important_table;"

sudo -u postgres psql -Atc "select current_timestamp"

2024-05-28 13:43:06.406683-04
```

If the wrong backup is selected for restore then recovery to the required time target will fail. To demonstrate this a new incremental backup is performed where important_table does not exist.

**pg-primary ⇒ Restore the demo cluster to 2024-05-28 13:42:14.392062-04**
```sh
sudo systemctl stop postgresql-16

sudo -u postgres pgbackrest --stanza=pg01 --delta \
       --type=time "--target=2024-05-28 13:42:14.392062-04" \
       --target-action=promote restore
```

**pg-primary ⇒ Start PostgreSQL and check that the important table exists**
```sh
sudo systemctl start postgresql-16
sudo systemctl status pgbackrest --no-pager

sleep 30

sudo -u postgres psql -c "select * from important_table"
```

```
    message
----------------
 Important Data
```

## Schedule a Backup

```bash
#m h   dom mon dow   command
30 06  *   *   0     pgbackrest --type=full --stanza=pg01 backup
30 06  *   *   1-6   pgbackrest --type=diff --stanza=pg01 backup
```

## References:

- [pgBackRest File Bundling and Block Incremental... | Crunchy Data Blog](https://www.crunchydata.com/blog/pgbackrest-file-bundling-and-block-incremental-backup)
- [EDB Docs - Use Case 1: Running pgBackRest Locally on the Database Host (enterprisedb.com)](https://www.enterprisedb.com/docs/supported-open-source/pgbackrest/06-use_case_1/)
- [pgBackRest User Guide - Setup Passwordless SSH](https://pgbackrest.org/user-guide.html#repo-host/setup-ssh)
- [EDB Docs - Use Case 2: Running pgBackRest from a Dedicated Repository Host (enterprisedb.com)](https://www.enterprisedb.com/docs/supported-open-source/pgbackrest/07-use_case_2/)
- [Decoupling Backup and Expiry Operations in PostgreSQL With pgBackRest (percona.com)](https://www.percona.com/blog/decoupling-backup-and-expiry-operations-in-postgresql-with-pgbackrest/)
