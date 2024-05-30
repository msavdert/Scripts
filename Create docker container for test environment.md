---
database: PostgreSQL
title: Backup and Recovery
class: pgBackRest
created: 03/26/2024 12:33 GMT-04:00
---
## Minio

### Install Minio

- [[Create docker container for test environment#MySelf#Minio]]
- [MinIO Object Storage for Linux — MinIO Object Storage for Linux](https://min.io/docs/minio/linux/index.html#quickstart-minio-for-linux)

```sh
dnf install -y sudo

# update
sudo dnf update -y

# timezone
sudo rm -rf /etc/localtime
sudo ln -s /usr/share/zoneinfo/America/New_York /etc/localtime

# chrony
sudo dnf install -y chrony
sudo systemctl enable --now chronyd

sudo dnf -y install https://dl.min.io/server/minio/release/linux-amd64/minio.rpm

minio -v
```

```
minio version RELEASE.2024-05-28T17-19-04Z (commit-id=f79a4ef4d0dc3e6562cad0d1d1db674bc8c75531)
Runtime: go1.22.3 linux/amd64
License: GNU AGPLv3 - https://www.gnu.org/licenses/agpl-3.0.html
Copyright: 2015-2024 MinIO, Inc.
```

```sh
groupadd -r minio-user
useradd -M -r -g minio-user minio-user

mkdir /minio-data
chown minio-user:minio-user /minio-data/
```

**Https**

```bash
sudo mkdir -p /opt/minio/certs
```

```bash
sudo openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
-keyout /opt/minio/certs/private.key \
-out /opt/minio/certs/public.crt \
-subj "/C=BE/ST=Country/L=City/O=Organization/CN=minio1"

sudo chown -R minio-user:minio-user /opt/minio

sudo vi /usr/lib/systemd/system/minio.service
```

```
ExecStart=/usr/local/bin/minio server $MINIO_OPTS $MINIO_VOLUMES
To
ExecStart=/usr/local/bin/minio server --certs-dir /opt/minio/certs $MINIO_OPTS $MINIO_VOLUMES
```

```sh
vi /etc/default/minio
```

```
MINIO_OPTS="--console-address :9001"
MINIO_ROOT_USER=minioadmin
MINIO_ROOT_PASSWORD=minioadmin
MINIO_VOLUMES="/minio-data/"
MINIO_ACCESS_KEY="/opt/minio/certs/public.crt"
MINIO_SECRET_KEY="/opt/minio/certs/private.key"
```

```sh
systemctl daemon-reload
systemctl enable --now minio
systemctl status minio --no-pager
```

### Install Minio client mc

[MinIO Client — MinIO Object Storage for Linux](https://min.io/docs/minio/linux/reference/minio-mc.html#install-mc)

```sh
curl https://dl.min.io/client/mc/release/linux-amd64/mc \
  --create-dirs \
  -o $HOME/minio-binaries/mc

chmod +x $HOME/minio-binaries/mc
export PATH=$PATH:$HOME/minio-binaries/

mc -v
```

```
mc version RELEASE.2024-05-24T09-08-49Z (commit-id=a8fdcbe7cb2f85ce98d60e904717aa00016a7d37)
Runtime: go1.22.3 linux/amd64
Copyright (c) 2015-2024 MinIO, Inc.
License GNU AGPLv3 <https://www.gnu.org/licenses/agpl-3.0.html>
```

**Create an Alias for the S3-Compatible Service**

Minio Server

```sh
bash +o history
mc alias set ALIAS HOSTNAME ACCESS_KEY SECRET_KEY
mc --insecure alias set myminio https://minio01:9000 minioadmin minioadmin
bash -o history
```

**Test the Connection**

```sh
mc --insecure admin info myminio
```

```
●  minio01:9000
   Uptime: 4 minutes
   Version: 2024-05-28T17:19:04Z
   Network: 1/1 OK
   Drives: 1/1 OK
   Pool: 1

┌──────┬────────────────────────┬─────────────────────┬──────────────┐
│ Pool │ Drives Usage           │ Erasure stripe size │ Erasure sets │
│ 1st  │ 34.1% (total: 300 GiB) │ 1                   │ 1            │
└──────┴────────────────────────┴─────────────────────┴──────────────┘

1 drive online, 0 drives offline, EC:0
```

Create Access Key

```sh
mc --insecure admin user add myminio oracle o8si58uHgMyJsDEUFYQhEH3JYgJVnrgiIc6W6zQ5

mc --insecure admin user svcacct add myminio oracle \
   --access-key "1SQXwhMuV6xBhsVbWqWX" \
   --secret-key "o8si58uHgMyJsDEUFYQhEH3JYgJVnrgiIc6W6zQ5"



mc --insecure admin user add myminio 1SQXwhMuV6xBhsVbWqWX o8si58uHgMyJsDEUFYQhEH3JYgJVnrgiIc6W6zQ5
```

Create bucket

```sh
mc --insecure mb myminio/oracle --region us-east-1
mc --insecure ls myminio
```

## Create access key

Left Menu -> User -> Access Keys -> Create access key

![[Pasted image 20240327084758.png]]

![[Pasted image 20240327084835.png]]

Access Key: OK4csiRFTinOcaOxQZ90
Secret Key: YdNuPFknihjKu2hKgl8BtnBO5Wc8yFZdoaBTv9wR

## Set region

Left Menu -> Configuration -> Region

![[Pasted image 20240327085241.png]]

## Restart Service

```bash
sudo systemctl restart minio
```

## Create Bucket

Left Menu -> Administrator -> Buckets -> Create Bucket

![[Pasted image 20240327085813.png]]

![[Pasted image 20240327090221.png]]

## pgBackRest Configuration

[[pgBackRest 2.5x Backup on Same Host and on Dedicated Repository Host]]

```bash
sudo -u postgres vi /etc/pgbackrest/pgbackrest.conf
```

```bash
[demo]
# PostgreSQL cluster data directory
pg1-path=/var/lib/pgsql/16/data

[global]
repo1-block=y
repo1-bundle=y
# pgBackRest repository encryption
repo1-cipher-pass=6QX2MWzybOtpHatVxaMUCRXUMa7oQYoLX0lZfPGLdRP+zFQmWyu5jjoRVhxtXgNZ
repo1-cipher-type=aes-256-cbc
# pgBackRest repository
repo1-path=/var/lib/pgbackrest
# Configure retention to 2 full backups
repo1-retention-full=2
# log level
log-level-console=info
log-level-file=detail
# Configure backup fast start
start-fast=y

# S3-Compatible Object Store - Minio
repo2-type=s3
repo2-path=/demo-repo
repo2-retention-full=3
repo2-s3-bucket=pgbackrest-pg01
repo2-s3-endpoint=minio:9000
repo2-s3-key=ytpOQ9MQkJAkwdNyH4jY
repo2-s3-key-secret=Ebpyc3hWU9oU2wByO3xnobrLqLkeOxqxD6SfMWy2
repo2-s3-region=us-east-1
# minio path fix
repo2-s3-uri-style=path
# it is seflsigned certifacte
repo2-storage-verify-tls=n

# File compression level for archive-push
[global:archive-push]
compress-level=3
```

## Create stanza

```bash
sudo -u postgres pgbackrest --stanza=demo stanza-create
```

```sh
2024-03-27 15:52:48.163 P00   INFO: stanza-create command begin 2.50: --exec-id=38735-89a06e62 --log-level-console=info --log-level-file=detail --pg1-path=/var/lib/pgsql/16/data --repo1-cipher-pass=<redacted> --repo1-cipher-type=aes-256-cbc --repo1-path=/var/lib/pgbackrest --repo2-path=/demo-repo --repo2-s3-bucket=pgbackrest-pg01 --repo2-s3-endpoint=minio:9000 --repo2-s3-key=<redacted> --repo2-s3-key-secret=<redacted> --repo2-s3-region=us-east-1 --repo2-s3-uri-style=path --no-repo2-storage-verify-tls --repo2-type=s3 --stanza=demo
2024-03-27 15:52:48.767 P00   INFO: stanza-create for stanza 'demo' on repo1
2024-03-27 15:52:48.768 P00   INFO: stanza 'demo' already exists on repo1 and is valid
2024-03-27 15:52:48.768 P00   INFO: stanza-create for stanza 'demo' on repo2
2024-03-27 15:52:48.787 P00   INFO: stanza-create command end: completed successfully (626ms)
```

![[Pasted image 20240327115436.png]]

## Backup

```bash
sudo -u postgres pgbackrest --stanza=demo --repo=2 backup
```

```sh
2024-03-27 16:06:01.406 P00   INFO: backup command begin 2.50: --exec-id=39093-b5d0177b --log-level-console=info --log-level-file=detail --pg1-path=/var/lib/pgsql/16/data --repo=2 --repo1-block --repo1-bundle --repo1-cipher-pass=<redacted> --repo1-cipher-type=aes-256-cbc --repo1-path=/var/lib/pgbackrest --repo2-path=/demo-repo --repo1-retention-full=2 --repo2-retention-full=3 --repo2-s3-bucket=pgbackrest-pg01 --repo2-s3-endpoint=minio:9000 --repo2-s3-key=<redacted> --repo2-s3-key-secret=<redacted> --repo2-s3-region=us-east-1 --repo2-s3-uri-style=path --no-repo2-storage-verify-tls --repo2-type=s3 --stanza=demo --start-fast
WARN: no prior backup exists, incr backup has been changed to full
2024-03-27 16:06:02.118 P00   INFO: execute non-exclusive backup start: backup begins after the requested immediate checkpoint completes
2024-03-27 16:06:02.619 P00   INFO: backup start archive = 00000004000000000000003A, lsn = 0/3A000028
2024-03-27 16:06:02.619 P00   INFO: check archive for prior segment 000000040000000000000039
2024-03-27 16:06:20.557 P00   INFO: execute non-exclusive backup stop and wait for all WAL segments to archive
2024-03-27 16:06:20.757 P00   INFO: backup stop archive = 00000004000000000000003A, lsn = 0/3A000138
2024-03-27 16:06:20.760 P00   INFO: check archive for segment(s) 00000004000000000000003A:00000004000000000000003A
2024-03-27 16:06:20.773 P00   INFO: new backup label = 20240327-160602F
2024-03-27 16:06:20.815 P00   INFO: full backup size = 359.1MB, file total = 1292
2024-03-27 16:06:20.815 P00   INFO: backup command end: completed successfully (19411ms)
2024-03-27 16:06:20.816 P00   INFO: expire command begin 2.50: --exec-id=39093-b5d0177b --log-level-console=info --log-level-file=detail --repo=2 --repo1-cipher-pass=<redacted> --repo1-cipher-type=aes-256-cbc --repo1-path=/var/lib/pgbackrest --repo2-path=/demo-repo --repo1-retention-full=2 --repo2-retention-full=3 --repo2-s3-bucket=pgbackrest-pg01 --repo2-s3-endpoint=minio:9000 --repo2-s3-key=<redacted> --repo2-s3-key-secret=<redacted> --repo2-s3-region=us-east-1 --repo2-s3-uri-style=path --no-repo2-storage-verify-tls --repo2-type=s3 --stanza=demo
2024-03-27 16:06:20.823 P00   INFO: expire command end: completed successfully (8ms)
```


```bash
sudo -u postgres pgbackrest --stanza=demo --repo=2 backup

2024-03-27 16:09:17.096 P00   INFO: backup command begin 2.50: --exec-id=39186-0c4bf9e7 --log-level-console=info --log-level-file=detail --pg1-path=/var/lib/pgsql/16/data --repo=2 --repo1-block --repo1-bundle --repo1-cipher-pass=<redacted> --repo1-cipher-type=aes-256-cbc --repo1-path=/var/lib/pgbackrest --repo2-path=/demo-repo --repo1-retention-full=2 --repo2-retention-full=3 --repo2-s3-bucket=pgbackrest-pg01 --repo2-s3-endpoint=minio:9000 --repo2-s3-key=<redacted> --repo2-s3-key-secret=<redacted> --repo2-s3-region=us-east-1 --repo2-s3-uri-style=path --no-repo2-storage-verify-tls --repo2-type=s3 --stanza=demo --start-fast
2024-03-27 16:09:17.815 P00   INFO: last backup label = 20240327-160602F, version = 2.50
2024-03-27 16:09:17.815 P00   INFO: execute non-exclusive backup start: backup begins after the requested immediate checkpoint completes
2024-03-27 16:09:18.316 P00   INFO: backup start archive = 00000004000000000000003C, lsn = 0/3C000028
2024-03-27 16:09:18.316 P00   INFO: check archive for prior segment 00000004000000000000003B
2024-03-27 16:09:19.539 P00   INFO: execute non-exclusive backup stop and wait for all WAL segments to archive
2024-03-27 16:09:19.739 P00   INFO: backup stop archive = 00000004000000000000003C, lsn = 0/3C000100
2024-03-27 16:09:19.742 P00   INFO: check archive for segment(s) 00000004000000000000003C:00000004000000000000003C
2024-03-27 16:09:19.756 P00   INFO: new backup label = 20240327-160602F_20240327-160917I
2024-03-27 16:09:19.799 P00   INFO: incr backup size = 2.7MB, file total = 1292
2024-03-27 16:09:19.799 P00   INFO: backup command end: completed successfully (2705ms)
2024-03-27 16:09:19.800 P00   INFO: expire command begin 2.50: --exec-id=39186-0c4bf9e7 --log-level-console=info --log-level-file=detail --repo=2 --repo1-cipher-pass=<redacted> --repo1-cipher-type=aes-256-cbc --repo1-path=/var/lib/pgbackrest --repo2-path=/demo-repo --repo1-retention-full=2 --repo2-retention-full=3 --repo2-s3-bucket=pgbackrest-pg01 --repo2-s3-endpoint=minio:9000 --repo2-s3-key=<redacted> --repo2-s3-key-secret=<redacted> --repo2-s3-region=us-east-1 --repo2-s3-uri-style=path --no-repo2-storage-verify-tls --repo2-type=s3 --stanza=demo
2024-03-27 16:09:19.807 P00   INFO: expire command end: completed successfully (8ms)
```

```bash
sudo -u postgres pgbackrest --stanza=demo --repo=2 info

stanza: demo
    status: ok
    cipher: none

    db (current)
        wal archive min/max (16): 000000040000000000000037/00000004000000000000003C

        full backup: 20240327-160602F
            timestamp start/stop: 2024-03-27 16:06:02+00 / 2024-03-27 16:06:20+00
            wal start/stop: 00000004000000000000003A / 00000004000000000000003A
            database size: 359.1MB, database backup size: 359.1MB
            repo2: backup set size: 77.9MB, backup size: 77.9MB

        incr backup: 20240327-160602F_20240327-160917I
            timestamp start/stop: 2024-03-27 16:09:17+00 / 2024-03-27 16:09:19+00
            wal start/stop: 00000004000000000000003C / 00000004000000000000003C
            database size: 359.1MB, database backup size: 2.7MB
            repo2: backup set size: 77.9MB, backup size: 160.4KB
            backup reference list: 20240327-160602F
```

## Restore

### on same PostgreSQL server

asd

### on different PostgreSQL server

[[PostgreSQL 16 Installation on Red Hat Family 9]]





## References:

1. [pgBackRest User Guide - RHEL - S3-Compatible Object Store Support](https://pgbackrest.org/user-guide-rhel.html#s3-support)
2. [Pgackrest and Minio, the perfect match (linkedin.com)](https://www.linkedin.com/pulse/pgackrest-minio-perfect-match-st%C3%A9phane-maurizio)
3. [Using pgBackRest to backup your PostgreSQL instances to a s3 compatible storage - dbi Blog](https://www.dbi-services.com/blog/using-pgbackrest-to-backup-your-postgresql-instances-to-a-s3-compatible-storage/)
4. [pgBackRest S3 configuration | pgstef’s blog](https://pgstef.github.io/2019/07/19/pgbackrest_s3_configuration.html)
5. 
