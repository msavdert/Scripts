---
database: PostgreSQL
title: Backup and Recovery
class: pgBackRest
created: 05/24/2024 21:55
---
## Environment

| Hostname   | IP Address  | OS            | Role                     | Verison |
| ---------- | ----------- | ------------- | ------------------------ | ------- |
| pg01       | 172.28.5.11 | Rocky Linux 9 | PostgreSQL Database      | 16.3    |
| pg02       | 172.28.5.12 | Rocky Linux 9 | PostgreSQL Database      | 16.3    |
| pg03       | 172.28.5.13 | Rocky Linux 9 | PostgreSQL Database      | 16.3    |
| pgbackup01 | 172.28.5.15 | Rocky Linux 9 | pgBackRest Backup Server | 2.51    |

```
patronictl -c /etc/patroni/patroni.yml list

+ Cluster: demo-cluster-1 (7374443775163790452) --+-----------+
| Member | Host        | Role    | State     | TL | Lag in MB |
+--------+-------------+---------+-----------+----+-----------+
| pg01   | 172.28.5.11 | Leader  | running   |  1 |           |
| pg02   | 172.28.5.12 | Replica | streaming |  1 |         0 |
| pg03   | 172.28.5.13 | Replica | streaming |  1 |         0 |
+--------+-------------+---------+-----------+----+-----------+
```

![[Pasted image 20240527120220.png]]

## pgBackRest Installation

>[!note]
>Install pgBackRest on all database and repository servers

[[pgBackRest 2.5x Installation]]

## pgBackRest Configuration
### Repository Server Configuration

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
backup-standby=y
EOF
```

### PostgreSQL Server Configuration

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
------------------+-------------------
 archive_command  | /bin/true
 archive_mode     | on
 listen_addresses | 0.0.0.0
 log_filename     | postgresql-%a.log
 max_wal_senders  | 10
 wal_level        | replica
```

>[!note]
>Change "--stanza=demo-cluster-1"

Let’s adjust the `archive_command` in Patroni configuration:

```sh
sudo -iu postgres patronictl -c /etc/patroni/patroni.yml edit-config

## adjust the following lines
postgresql:
  parameters:
    archive_command: pgbackrest --stanza=demo-cluster-1 archive-push "%p"
```

```sh
sudo -iu postgres patronictl -c /etc/patroni/patroni.yml reload demo-cluster-1
```

## pgBackRest enable communication between the hosts

### Option 2: Setup TLS

**Create environment variables to simplify the config file creation:**

**repository-pg01-pg02-pg03: ⇒**
```sh
export REPO_SRV_NAME="pgbackup01"
export NODE_NAME=`hostname -f`
export NODE1_NAME="pg01"
export NODE2_NAME="pg02"
export NODE3_NAME="pg03"
CLUSTER_NAME="demo-cluster-1"
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
tls-server-auth=${NODE1_NAME}=${CLUSTER_NAME}
tls-server-auth=${NODE2_NAME}=${CLUSTER_NAME}
tls-server-auth=${NODE3_NAME}=${CLUSTER_NAME}
EOF
```

**repository: ⇒**
```sh
cat << EOF | tee "/etc/pgbackrest/conf.d/${CLUSTER_NAME}.conf"
[${CLUSTER_NAME}]
pg1-host=${NODE1_NAME}
pg1-host-port=8432
pg1-port=5432
pg1-path=/var/lib/pgsql/16/data
pg1-host-type=tls
pg1-host-cert-file=${CA_PATH}/${REPO_SRV_NAME}.crt
pg1-host-key-file=${CA_PATH}/${REPO_SRV_NAME}.key
pg1-host-ca-file=${CA_PATH}/ca.crt

pg2-host=${NODE2_NAME}
pg2-host-port=8432
pg2-port=5432
pg2-path=/var/lib/pgsql/16/data
pg2-host-type=tls
pg2-host-cert-file=${CA_PATH}/${REPO_SRV_NAME}.crt
pg2-host-key-file=${CA_PATH}/${REPO_SRV_NAME}.key
pg2-host-ca-file=${CA_PATH}/ca.crt
pg2-socket-path=/var/run/postgresql 

pg3-host=${NODE3_NAME}
pg3-host-port=8432
pg3-port=5432
pg3-path=/var/lib/pgsql/16/data
pg3-host-type=tls
pg3-host-cert-file=${CA_PATH}/${REPO_SRV_NAME}.crt
pg3-host-key-file=${CA_PATH}/${REPO_SRV_NAME}.key
pg3-host-ca-file=${CA_PATH}/ca.crt
pg3-socket-path=/var/run/postgresql
EOF

chown -R pgbackrest:pgbackrest /etc/pgbackrest/conf.d/
```

**pg01-pg02-pg03 ⇒**
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
tls-server-auth=${REPO_SRV_NAME}=${CLUSTER_NAME}
EOF
```

**pg01-pg02-pg03 ⇒**
```sh
cat << EOF | tee "/etc/pgbackrest/conf.d/${CLUSTER_NAME}.conf"
[${CLUSTER_NAME}]
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

**pg01-pg02-pg03: ⇒**
```bash
mkdir -p ${CA_PATH}
scp pgbackrest@${REPO_SRV_NAME}:${CA_PATH}/{ca.crt,`hostname`.*} ${CA_PATH}/
chown postgres:postgres -R ${CA_PATH}
chmod 0600 ${CA_PATH}/* 
```

```bash
ls ${CA_PATH}/

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

**pg01-pg02-pg03:**
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
sudo -u pgbackrest pgbackrest --stanza=demo-cluster-1 stanza-create
```

```
2024-05-29 12:15:13.990 P00   INFO: stanza-create command begin 2.52: --exec-id=1527-ee48d58d --log-level-console=info --log-level-file=detail --pg1-host=pg01 --pg2-host=pg02 --pg3-host=pg03 --pg1-host-ca-file=/etc/pgbackrest/certs/ca.crt --pg2-host-ca-file=/etc/pgbackrest/certs/ca.crt --pg3-host-ca-file=/etc/pgbackrest/certs/ca.crt --pg1-host-cert-file=/etc/pgbackrest/certs/pgbackup01.crt --pg2-host-cert-file=/etc/pgbackrest/certs/pgbackup01.crt --pg3-host-cert-file=/etc/pgbackrest/certs/pgbackup01.crt --pg1-host-key-file=/etc/pgbackrest/certs/pgbackup01.key --pg2-host-key-file=/etc/pgbackrest/certs/pgbackup01.key --pg3-host-key-file=/etc/pgbackrest/certs/pgbackup01.key --pg1-host-port=8432 --pg2-host-port=8432 --pg3-host-port=8432 --pg1-host-type=tls --pg2-host-type=tls --pg3-host-type=tls --pg1-path=/var/lib/pgsql/16/data --pg2-path=/var/lib/pgsql/16/data --pg3-path=/var/lib/pgsql/16/data --pg1-port=5432 --pg2-port=5432 --pg3-port=5432 --pg2-socket-path=/var/run/postgresql --pg3-socket-path=/var/run/postgresql --repo1-cipher-pass=<redacted> --repo1-cipher-type=aes-256-cbc --repo1-path=/backup/pgbackrest --stanza=demo-cluster-1
2024-05-29 12:15:15.832 P00   INFO: stanza-create for stanza 'demo-cluster-1' on repo1
2024-05-29 12:15:15.839 P00   INFO: stanza-create command end: completed successfully (1851ms)
```

```sh
sudo -u pgbackrest pgbackrest --stanza=demo-cluster-1 check
```

```
2024-05-29 12:20:29.575 P00   INFO: check command begin 2.52: --backup-standby --exec-id=1598-3c150d94 --log-level-console=info --log-level-file=detail --pg1-host=pg01 --pg2-host=pg02 --pg3-host=pg03 --pg1-host-ca-file=/etc/pgbackrest/certs/ca.crt --pg2-host-ca-file=/etc/pgbackrest/certs/ca.crt --pg3-host-ca-file=/etc/pgbackrest/certs/ca.crt --pg1-host-cert-file=/etc/pgbackrest/certs/pgbackup01.crt --pg2-host-cert-file=/etc/pgbackrest/certs/pgbackup01.crt --pg3-host-cert-file=/etc/pgbackrest/certs/pgbackup01.crt --pg1-host-key-file=/etc/pgbackrest/certs/pgbackup01.key --pg2-host-key-file=/etc/pgbackrest/certs/pgbackup01.key --pg3-host-key-file=/etc/pgbackrest/certs/pgbackup01.key --pg1-host-port=8432 --pg2-host-port=8432 --pg3-host-port=8432 --pg1-host-type=tls --pg2-host-type=tls --pg3-host-type=tls --pg1-path=/var/lib/pgsql/16/data --pg2-path=/var/lib/pgsql/16/data --pg3-path=/var/lib/pgsql/16/data --pg1-port=5432 --pg2-port=5432 --pg3-port=5432 --pg2-socket-path=/var/run/postgresql --pg3-socket-path=/var/run/postgresql --repo1-cipher-pass=<redacted> --repo1-cipher-type=aes-256-cbc --repo1-path=/backup/pgbackrest --stanza=demo-cluster-1
2024-05-29 12:20:31.417 P00   INFO: check repo1 (standby)
2024-05-29 12:20:31.417 P00   INFO: switch wal not performed because this is a standby
2024-05-29 12:20:31.417 P00   INFO: check repo1 configuration (primary)
2024-05-29 12:20:31.618 P00   INFO: check repo1 archive for WAL (primary)
2024-05-29 12:20:31.719 P00   INFO: WAL segment 000000010000000000000006 successfully archived to '/backup/pgbackrest/archive/demo-cluster-1/16-1/0000000100000000/000000010000000000000006-5455c0bc644cf022adaa8fa128289df4e40e2661.gz' on repo1
2024-05-29 12:20:31.720 P00   INFO: check command end: completed successfully (2147ms)
```

**Backup**

```sh
sudo -iu pgbackrest pgbackrest --stanza=demo-cluster-1 --type=full backup
```

```
2024-05-29 12:20:55.658 P00   INFO: backup command begin 2.52: --backup-standby --delta --exec-id=1611-8a192318 --log-level-console=info --log-level-file=detail --pg1-host=pg01 --pg2-host=pg02 --pg3-host=pg03 --pg1-host-ca-file=/etc/pgbackrest/certs/ca.crt --pg2-host-ca-file=/etc/pgbackrest/certs/ca.crt --pg3-host-ca-file=/etc/pgbackrest/certs/ca.crt --pg1-host-cert-file=/etc/pgbackrest/certs/pgbackup01.crt --pg2-host-cert-file=/etc/pgbackrest/certs/pgbackup01.crt --pg3-host-cert-file=/etc/pgbackrest/certs/pgbackup01.crt --pg1-host-key-file=/etc/pgbackrest/certs/pgbackup01.key --pg2-host-key-file=/etc/pgbackrest/certs/pgbackup01.key --pg3-host-key-file=/etc/pgbackrest/certs/pgbackup01.key --pg1-host-port=8432 --pg2-host-port=8432 --pg3-host-port=8432 --pg1-host-type=tls --pg2-host-type=tls --pg3-host-type=tls --pg1-path=/var/lib/pgsql/16/data --pg2-path=/var/lib/pgsql/16/data --pg3-path=/var/lib/pgsql/16/data --pg1-port=5432 --pg2-port=5432 --pg3-port=5432 --pg2-socket-path=/var/run/postgresql --pg3-socket-path=/var/run/postgresql --process-max=2 --repo1-block --repo1-bundle --repo1-cipher-pass=<redacted> --repo1-cipher-type=aes-256-cbc --repo1-path=/backup/pgbackrest --repo1-retention-full=2 --stanza=demo-cluster-1 --start-fast --type=full
2024-05-29 12:20:57.601 P00   INFO: execute non-exclusive backup start: backup begins after the requested immediate checkpoint completes
2024-05-29 12:20:58.102 P00   INFO: backup start archive = 000000010000000000000008, lsn = 0/8000028
2024-05-29 12:20:58.102 P00   INFO: wait for replay on the standby to reach 0/8000028
2024-05-29 12:20:58.404 P00   INFO: replay on the standby reached 0/8000028
2024-05-29 12:20:58.404 P00   INFO: check archive for prior segment 000000010000000000000007
2024-05-29 12:21:00.127 P00   INFO: execute non-exclusive backup stop and wait for all WAL segments to archive
2024-05-29 12:21:00.328 P00   INFO: backup stop archive = 000000010000000000000008, lsn = 0/8000138
2024-05-29 12:21:00.335 P00   INFO: check archive for segment(s) 000000010000000000000008:000000010000000000000008
2024-05-29 12:21:00.343 P00   INFO: new backup label = 20240529-122057F
2024-05-29 12:21:00.378 P00   INFO: full backup size = 22.2MB, file total = 974
2024-05-29 12:21:00.379 P00   INFO: backup command end: completed successfully (4723ms)
2024-05-29 12:21:00.379 P00   INFO: expire command begin 2.52: --exec-id=1611-8a192318 --log-level-console=info --log-level-file=detail --repo1-cipher-pass=<redacted> --repo1-cipher-type=aes-256-cbc --repo1-path=/backup/pgbackrest --repo1-retention-full=2 --stanza=demo-cluster-1
2024-05-29 12:21:00.383 P00   INFO: expire command end: completed successfully (4ms)
```

```sh
sudo -iu pgbackrest pgbackrest info
sudo -iu pgbackrest pgbackrest --stanza=demo-cluster-1 info
```

```
stanza: demo-cluster-1
    status: ok
    cipher: aes-256-cbc

    db (current)
        wal archive min/max (16): 000000010000000000000005/000000010000000000000008

        full backup: 20240529-122057F
            timestamp start/stop: 2024-05-29 12:20:57-04 / 2024-05-29 12:21:00-04
            wal start/stop: 000000010000000000000008 / 000000010000000000000008
            database size: 22.2MB, database backup size: 22.2MB
            repo1: backup size: 3.0MB
```

## S3-Compatible Object Store

### OCI Bucket

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

### Minio

[[PgBackRest - S3 and S3-Compatible Object Store Support (Minio, OCI, etc...)]]

**pgBackRest Configuration**

Repository Encryption

```bash
sudo openssl rand -base64 48

6S7bJ8VBfGRbekNUkfIt4wzA8e2oCRdJUpehdPJ1YoOmtDCU5emCiB3/u2ya5FzA
```

**repository: ⇒**
```sh
export URL="minio01:9000"
export BUCKET_NAME="postgresql"
export ACCESS_KEY="OK4csiRFTinOcaOxQZ90"
export SECRET_KEY="YdNuPFknihjKu2hKgl8BtnBO5Wc8yFZdoaBTv9wR"
export REGION="us-east-1"

cat <<EOF >> /etc/pgbackrest/pgbackrest.conf

########## Minio S3-compatible bucket repository ##########
repo2-type=s3
repo2-s3-endpoint=${URL}
repo2-s3-bucket=${BUCKET_NAME}
repo2-s3-key=${ACCESS_KEY}
repo2-s3-key-secret=${SECRET_KEY}
repo2-s3-region=${REGION}
repo2-path=/pgbackrest
repo2-s3-uri-style=path
repo2-storage-verify-tls=n
repo2-retention-full=2
repo2-block=y
repo2-bundle=y
repo2-cipher-pass=6S7bJ8VBfGRbekNUkfIt4wzA8e2oCRdJUpehdPJ1YoOmtDCU5emCiB3/u2ya5FzA
repo2-cipher-type=aes-256-cbc
EOF
```

**pg01-pg02-pg03: ⇒**
```sh
export URL="minio01:9000"
export BUCKET_NAME="postgresql"
export ACCESS_KEY="OK4csiRFTinOcaOxQZ90"
export SECRET_KEY="YdNuPFknihjKu2hKgl8BtnBO5Wc8yFZdoaBTv9wR"
export REGION="us-east-1"

cat <<EOF >> /etc/pgbackrest/pgbackrest.conf

########## OCI S3-compatible bucket repository ##########
repo2-type=s3
repo2-s3-endpoint=${URL}
repo2-s3-bucket=${BUCKET_NAME}
repo2-s3-key=${ACCESS_KEY}
repo2-s3-key-secret=${SECRET_KEY}
repo2-s3-region=${REGION}
repo2-s3-uri-style=path
repo2-storage-verify-tls=n
repo2-path=/pgbackrest
repo2-retention-full=2
repo2-block=y
repo2-bundle=y
repo2-cipher-pass=6S7bJ8VBfGRbekNUkfIt4wzA8e2oCRdJUpehdPJ1YoOmtDCU5emCiB3/u2ya5FzA
repo2-cipher-type=aes-256-cbc
EOF
```

## Backup

**Create and check stanza**

```sh
sudo -u pgbackrest pgbackrest --stanza=demo-cluster-1 stanza-create
```

```
2024-05-29 13:41:46.873 P00   INFO: stanza-create command begin 2.52: --exec-id=2755-27db479a --log-level-console=info --log-level-file=detail --pg1-host=pg01 --pg2-host=pg02 --pg3-host=pg03 --pg1-host-ca-file=/etc/pgbackrest/certs/ca.crt --pg2-host-ca-file=/etc/pgbackrest/certs/ca.crt --pg3-host-ca-file=/etc/pgbackrest/certs/ca.crt --pg1-host-cert-file=/etc/pgbackrest/certs/pgbackup01.crt --pg2-host-cert-file=/etc/pgbackrest/certs/pgbackup01.crt --pg3-host-cert-file=/etc/pgbackrest/certs/pgbackup01.crt --pg1-host-key-file=/etc/pgbackrest/certs/pgbackup01.key --pg2-host-key-file=/etc/pgbackrest/certs/pgbackup01.key --pg3-host-key-file=/etc/pgbackrest/certs/pgbackup01.key --pg1-host-port=8432 --pg2-host-port=8432 --pg3-host-port=8432 --pg1-host-type=tls --pg2-host-type=tls --pg3-host-type=tls --pg1-path=/var/lib/pgsql/16/data --pg2-path=/var/lib/pgsql/16/data --pg3-path=/var/lib/pgsql/16/data --pg1-port=5432 --pg2-port=5432 --pg3-port=5432 --pg2-socket-path=/var/run/postgresql --pg3-socket-path=/var/run/postgresql --repo1-cipher-pass=<redacted> --repo2-cipher-pass=<redacted> --repo1-cipher-type=aes-256-cbc --repo2-cipher-type=aes-256-cbc --repo1-path=/backup/pgbackrest --repo2-path=/pgbackrest --repo2-s3-bucket=postgresql --repo2-s3-endpoint=minio01:9000 --repo2-s3-key=<redacted> --repo2-s3-key-secret=<redacted> --repo2-s3-region=us-east-1 --repo2-s3-uri-style=path --no-repo2-storage-verify-tls --repo2-type=s3 --stanza=demo-cluster-1
2024-05-29 13:41:48.716 P00   INFO: stanza-create for stanza 'demo-cluster-1' on repo1
2024-05-29 13:41:48.716 P00   INFO: stanza 'demo-cluster-1' already exists on repo1 and is valid
2024-05-29 13:41:48.716 P00   INFO: stanza-create for stanza 'demo-cluster-1' on repo2
2024-05-29 13:41:48.735 P00   INFO: stanza-create command end: completed successfully (1864ms)
```

```sh
sudo -u pgbackrest pgbackrest --stanza=demo-cluster-1 check
```

```
2024-05-29 13:42:19.606 P00   INFO: check command begin 2.52: --backup-standby --exec-id=2759-ac69df13 --log-level-console=info --log-level-file=detail --pg1-host=pg01 --pg2-host=pg02 --pg3-host=pg03 --pg1-host-ca-file=/etc/pgbackrest/certs/ca.crt --pg2-host-ca-file=/etc/pgbackrest/certs/ca.crt --pg3-host-ca-file=/etc/pgbackrest/certs/ca.crt --pg1-host-cert-file=/etc/pgbackrest/certs/pgbackup01.crt --pg2-host-cert-file=/etc/pgbackrest/certs/pgbackup01.crt --pg3-host-cert-file=/etc/pgbackrest/certs/pgbackup01.crt --pg1-host-key-file=/etc/pgbackrest/certs/pgbackup01.key --pg2-host-key-file=/etc/pgbackrest/certs/pgbackup01.key --pg3-host-key-file=/etc/pgbackrest/certs/pgbackup01.key --pg1-host-port=8432 --pg2-host-port=8432 --pg3-host-port=8432 --pg1-host-type=tls --pg2-host-type=tls --pg3-host-type=tls --pg1-path=/var/lib/pgsql/16/data --pg2-path=/var/lib/pgsql/16/data --pg3-path=/var/lib/pgsql/16/data --pg1-port=5432 --pg2-port=5432 --pg3-port=5432 --pg2-socket-path=/var/run/postgresql --pg3-socket-path=/var/run/postgresql --repo1-cipher-pass=<redacted> --repo2-cipher-pass=<redacted> --repo1-cipher-type=aes-256-cbc --repo2-cipher-type=aes-256-cbc --repo1-path=/backup/pgbackrest --repo2-path=/pgbackrest --repo2-s3-bucket=postgresql --repo2-s3-endpoint=minio01:9000 --repo2-s3-key=<redacted> --repo2-s3-key-secret=<redacted> --repo2-s3-region=us-east-1 --repo2-s3-uri-style=path --no-repo2-storage-verify-tls --repo2-type=s3 --stanza=demo-cluster-1
2024-05-29 13:42:21.448 P00   INFO: check repo1 (standby)
2024-05-29 13:42:21.448 P00   INFO: check repo2 (standby)
2024-05-29 13:42:21.453 P00   INFO: switch wal not performed because this is a standby
2024-05-29 13:42:21.453 P00   INFO: check repo1 configuration (primary)
2024-05-29 13:42:21.453 P00   INFO: check repo2 configuration (primary)
2024-05-29 13:42:21.656 P00   INFO: check repo1 archive for WAL (primary)
2024-05-29 13:42:21.757 P00   INFO: WAL segment 00000001000000000000002E successfully archived to '/backup/pgbackrest/archive/demo-cluster-1/16-1/0000000100000000/00000001000000000000002E-7c8aea6fe9534e75b3c32c9a581045ea956b3247.gz' on repo1
2024-05-29 13:42:21.757 P00   INFO: check repo2 archive for WAL (primary)
2024-05-29 13:42:21.758 P00   INFO: WAL segment 00000001000000000000002E successfully archived to '/pgbackrest/archive/demo-cluster-1/16-1/0000000100000000/00000001000000000000002E-7c8aea6fe9534e75b3c32c9a581045ea956b3247.gz' on repo2
2024-05-29 13:42:21.758 P00   INFO: check command end: completed successfully (2154ms)
```

**Backup**

```sh
sudo -iu pgbackrest pgbackrest --stanza=demo-cluster-1 --type=full backup
sudo -iu pgbackrest pgbackrest --stanza=demo-cluster-1 --type=full backup --repo=1
sudo -iu pgbackrest pgbackrest --stanza=demo-cluster-1 --type=full backup --repo=2
```

```
2024-05-29 13:42:31.698 P00   INFO: backup command begin 2.52: --backup-standby --delta --exec-id=2762-156ff072 --log-level-console=info --log-level-file=detail --pg1-host=pg01 --pg2-host=pg02 --pg3-host=pg03 --pg1-host-ca-file=/etc/pgbackrest/certs/ca.crt --pg2-host-ca-file=/etc/pgbackrest/certs/ca.crt --pg3-host-ca-file=/etc/pgbackrest/certs/ca.crt --pg1-host-cert-file=/etc/pgbackrest/certs/pgbackup01.crt --pg2-host-cert-file=/etc/pgbackrest/certs/pgbackup01.crt --pg3-host-cert-file=/etc/pgbackrest/certs/pgbackup01.crt --pg1-host-key-file=/etc/pgbackrest/certs/pgbackup01.key --pg2-host-key-file=/etc/pgbackrest/certs/pgbackup01.key --pg3-host-key-file=/etc/pgbackrest/certs/pgbackup01.key --pg1-host-port=8432 --pg2-host-port=8432 --pg3-host-port=8432 --pg1-host-type=tls --pg2-host-type=tls --pg3-host-type=tls --pg1-path=/var/lib/pgsql/16/data --pg2-path=/var/lib/pgsql/16/data --pg3-path=/var/lib/pgsql/16/data --pg1-port=5432 --pg2-port=5432 --pg3-port=5432 --pg2-socket-path=/var/run/postgresql --pg3-socket-path=/var/run/postgresql --process-max=2 --repo1-block --repo2-block --repo1-bundle --repo2-bundle --repo1-cipher-pass=<redacted> --repo2-cipher-pass=<redacted> --repo1-cipher-type=aes-256-cbc --repo2-cipher-type=aes-256-cbc --repo1-path=/backup/pgbackrest --repo2-path=/pgbackrest --repo1-retention-full=2 --repo2-retention-full=2 --repo2-s3-bucket=postgresql --repo2-s3-endpoint=minio01:9000 --repo2-s3-key=<redacted> --repo2-s3-key-secret=<redacted> --repo2-s3-region=us-east-1 --repo2-s3-uri-style=path --no-repo2-storage-verify-tls --repo2-type=s3 --stanza=demo-cluster-1 --start-fast --type=full
2024-05-29 13:42:31.698 P00   INFO: repo option not specified, defaulting to repo1
2024-05-29 13:42:33.639 P00   INFO: execute non-exclusive backup start: backup begins after the requested immediate checkpoint completes
2024-05-29 13:42:34.141 P00   INFO: backup start archive = 000000010000000000000030, lsn = 0/30000028
2024-05-29 13:42:34.141 P00   INFO: wait for replay on the standby to reach 0/30000028
2024-05-29 13:42:34.444 P00   INFO: replay on the standby reached 0/30000028
2024-05-29 13:42:34.444 P00   INFO: check archive for prior segment 00000001000000000000002F
2024-05-29 13:42:43.025 P00   INFO: execute non-exclusive backup stop and wait for all WAL segments to archive
2024-05-29 13:42:43.225 P00   INFO: backup stop archive = 000000010000000000000030, lsn = 0/30000100
2024-05-29 13:42:43.228 P00   INFO: check archive for segment(s) 000000010000000000000030:000000010000000000000030
2024-05-29 13:42:43.237 P00   INFO: new backup label = 20240529-134233F
2024-05-29 13:42:43.274 P00   INFO: full backup size = 355.5MB, file total = 1296
2024-05-29 13:42:43.275 P00   INFO: backup command end: completed successfully (11579ms)
2024-05-29 13:42:43.275 P00   INFO: expire command begin 2.52: --exec-id=2762-156ff072 --log-level-console=info --log-level-file=detail --repo1-cipher-pass=<redacted> --repo2-cipher-pass=<redacted> --repo1-cipher-type=aes-256-cbc --repo2-cipher-type=aes-256-cbc --repo1-path=/backup/pgbackrest --repo2-path=/pgbackrest --repo1-retention-full=2 --repo2-retention-full=2 --repo2-s3-bucket=postgresql --repo2-s3-endpoint=minio01:9000 --repo2-s3-key=<redacted> --repo2-s3-key-secret=<redacted> --repo2-s3-region=us-east-1 --repo2-s3-uri-style=path --no-repo2-storage-verify-tls --repo2-type=s3 --stanza=demo-cluster-1
2024-05-29 13:42:43.276 P00   INFO: repo1: expire full backup 20240529-122057F
2024-05-29 13:42:43.278 P00   INFO: repo1: remove expired backup 20240529-122057F
2024-05-29 13:42:43.279 P00   INFO: repo1: 16-1 remove archive, start = 000000010000000000000008, stop = 000000010000000000000009
2024-05-29 13:42:43.296 P00   INFO: expire command end: completed successfully (21ms)
```

```sh
sudo -iu pgbackrest pgbackrest info
sudo -iu pgbackrest pgbackrest --repo=1 info
sudo -iu pgbackrest pgbackrest --repo=2 info
```

```
stanza: demo-cluster-1
    status: ok
    cipher: aes-256-cbc

    db (current)
        wal archive min/max (16): 00000001000000000000002E/000000010000000000000034

        full backup: 20240529-134233F
            timestamp start/stop: 2024-05-29 13:42:33-04 / 2024-05-29 13:42:43-04
            wal start/stop: 000000010000000000000030 / 000000010000000000000030
            database size: 355.5MB, database backup size: 355.5MB
            repo1: backup size: 78MB

        full backup: 20240529-134307F
            timestamp start/stop: 2024-05-29 13:43:07-04 / 2024-05-29 13:43:16-04
            wal start/stop: 000000010000000000000032 / 000000010000000000000032
            database size: 355.5MB, database backup size: 355.5MB
            repo1: backup size: 78MB

        full backup: 20240529-134320F
            timestamp start/stop: 2024-05-29 13:43:20-04 / 2024-05-29 13:43:30-04
            wal start/stop: 000000010000000000000033 / 000000010000000000000034
            database size: 355.5MB, database backup size: 355.5MB
            repo2: backup size: 78MB
```

## Restore

### Primary

Here is our current situation:

```sh
sudo -iu postgres patronictl -c /etc/patroni/patroni.yml list

+ Cluster: demo-cluster-1 (7374443775163790452) --+-----------+
| Member | Host        | Role    | State     | TL | Lag in MB |
+--------+-------------+---------+-----------+----+-----------+
| pg01   | 172.28.5.11 | Leader  | running   |  1 |           |
| pg02   | 172.28.5.12 | Replica | streaming |  1 |         0 |
| pg03   | 172.28.5.13 | Replica | streaming |  1 |         0 |
+--------+-------------+---------+-----------+----+-----------+
```

Disable auto failover with pause the patroni.

```sh
sudo -iu postgres patronictl -c /etc/patroni/patroni.yml pause
```

Stop patroni service on all nodes

```sh
sudo systemctl stop patroni
```

Remove cluster and information of the cluster from the DCS.

```sh
echo -e 'demo-cluster-1\nYes I am aware' | patronictl remove demo-cluster-1
```

**Restore**

Stop PostgreSQL database

**pg01: ⇒**
```sh
sudo -iu postgres /usr/pgsql-16/bin/pg_ctl status
```

```
pg_ctl: server is running (PID: 1147)
/usr/pgsql-16/bin/postgres "-D" "/var/lib/pgsql/16/data" "--config-file=/var/lib/pgsql/16/data/postgresql.conf" "--listen_addresses=0.0.0.0" "--port=5432" "--cluster_name=demo-cluster-1" "--wal_level=replica" "--hot_standby=on" "--max_connections=100" "--max_wal_senders=10" "--max_prepared_transactions=0" "--max_locks_per_transaction=64" "--track_commit_timestamp=off" "--max_replication_slots=10" "--max_worker_processes=8" "--wal_log_hints=on"
```

```sh
sudo -iu postgres /usr/pgsql-16/bin/pg_ctl stop
```

```
waiting for server to shut down.... done
server stopped
```

```sh
sudo -u postgres pgbackrest --stanza=demo-cluster-1 restore --delta
```

```
2024-05-29 14:04:33.358 P00   INFO: restore command begin 2.52: --delta --exec-id=12581-f8ce186b --log-level-console=info --log-level-file=detail --pg1-path=/var/lib/pgsql/16/data --process-max=2 --repo2-cipher-pass=<redacted> --repo2-cipher-type=aes-256-cbc --repo1-host=pgbackup01 --repo1-host-ca-file=/etc/pgbackrest/certs/ca.crt --repo1-host-cert-file=/etc/pgbackrest/certs/pg01.crt --repo1-host-key-file=/etc/pgbackrest/certs/pg01.key --repo1-host-type=tls --repo1-host-user=postgres --repo2-path=/pgbackrest --repo2-s3-bucket=postgresql --repo2-s3-endpoint=minio01:9000 --repo2-s3-key=<redacted> --repo2-s3-key-secret=<redacted> --repo2-s3-region=us-east-1 --repo2-s3-uri-style=path --no-repo2-storage-verify-tls --repo2-type=s3 --stanza=demo-cluster-1
2024-05-29 14:04:33.374 P00   INFO: repo1: restore backup set 20240529-134307F, recovery will start at 2024-05-29 13:43:07
2024-05-29 14:04:33.375 P00   INFO: remove invalid files/links/paths from '/var/lib/pgsql/16/data'
2024-05-29 14:04:34.624 P00   INFO: write updated /var/lib/pgsql/16/data/postgresql.auto.conf
2024-05-29 14:04:34.629 P00   INFO: restore global/pg_control (performed last to ensure aborted restores cannot be started)
2024-05-29 14:04:34.629 P00   INFO: restore size = 355.5MB, file total = 1296
2024-05-29 14:04:34.629 P00   INFO: restore command end: completed successfully (1273ms)
```

Start PostgreSQL database

```sh
sudo -iu postgres /usr/pgsql-16/bin/pg_ctl start
```

Check data

```bash
sudo -iu postgres psql -d employees -c " \
SELECT d.dept_name, AVG(s.amount) AS average_salary \
FROM employees.salary s \
JOIN employees.department_employee de ON s.employee_id = de.employee_id \
JOIN employees.department d ON de.department_id = d.id \
WHERE s.to_date > CURRENT_DATE AND de.to_date > CURRENT_DATE \
GROUP BY d.dept_name \
ORDER BY average_salary DESC \
LIMIT 5; \
"
```

```
 dept_name  |   average_salary
------------+--------------------
 Sales      | 88852.969470305827
 Marketing  | 80058.848807438351
 Finance    | 78559.936962289941
 Research   | 67913.374975714008
 Production | 67843.301984841663
```

Start patroni service on all nodes

```sh
sudo systemctl start patroni
sleep 5
sudo -u postgres patronictl -c /etc/patroni/patroni.yml list
```

```
+ Cluster: demo-cluster-1 (7374443775163790452) -----------+
| Member | Host        | Role   | State   | TL | Lag in MB |
+--------+-------------+--------+---------+----+-----------+
| pg01   | 172.28.5.11 | Leader | running |  2 |           |
+--------+-------------+--------+---------+----+-----------+
```

After a while

```
+ Cluster: demo-cluster-1 (7374443775163790452) +-----------+
| Member | Host        | Role    | State   | TL | Lag in MB |
+--------+-------------+---------+---------+----+-----------+
| pg01   | 172.28.5.11 | Leader  | running |  2 |           |
| pg02   | 172.28.5.12 | Replica | running |  1 |         0 |
| pg03   | 172.28.5.13 | Replica | running |  1 |         0 |
+--------+-------------+---------+---------+----+-----------+
```

Re-init

```sh
sudo -u postgres patronictl -c /etc/patroni/patroni.yml reinit demo-cluster-1 pg02
sudo -u postgres patronictl -c /etc/patroni/patroni.yml reinit demo-cluster-1 pg03
sleep 5
sudo -u postgres patronictl -c /etc/patroni/patroni.yml list
```

```
+ Cluster: demo-cluster-1 (7374443775163790452) --+-----------+
| Member | Host        | Role    | State     | TL | Lag in MB |
+--------+-------------+---------+-----------+----+-----------+
| pg01   | 172.28.5.11 | Leader  | running   |  2 |           |
| pg02   | 172.28.5.12 | Replica | streaming |  2 |         0 |
| pg03   | 172.28.5.13 | Replica | streaming |  2 |         0 |
+--------+-------------+---------+-----------+----+-----------+
```

>[!caution]
>Do not forget to take a new full backup

### Create a replica using pgBackRest

Let’s edit the bootstrap configuration part:

```sh
sudo -iu postgres patronictl -c /etc/patroni/patroni.yml edit-config

## adjust the following lines
postgresql:
  parameters:
    recovery_target_timeline: latest
    restore_command: pgbackrest --stanza=demo-cluster-1 archive-get %f "%p"

sudo -iu postgres patronictl -c /etc/patroni/patroni.yml reload demo-cluster-1
```

Postgresql 15 and below

```
postgresql:
  recovery_conf:
    recovery_target_timeline: latest
    restore_command: pgbackrest --stanza=demo-cluster-1 archive-get %f "%p"
```

On all your nodes, in `/etc/patroni/patroni.yml`, find the following part:

```sh
sudo -iu postgres vi /etc/patroni/patroni.yml
```

```sh
## adjust the following lines
postgresql:
...
  create_replica_methods:
    - pgbackrest
    - basebackup
  pgbackrest:
    command: pgbackrest --stanza=demo-cluster-1 restore --type=none
    keep_data: True
    no_params: True
  basebackup:
    checkpoint: 'fast'
```

Don’t forget to reload the configuration:

```sh
sudo systemctl reload patroni
```

Here is our current situation:

```sh
sudo -iu postgres patronictl -c /etc/patroni/patroni.yml list

+ Cluster: demo-cluster-1 (7373708270390346493) ---+-----------+
| Member  | Host        | Role    | State     | TL | Lag in MB |
+---------+-------------+---------+-----------+----+-----------+
| pgmel01 | 172.28.5.11 | Leader  | running   |  1 |           |
| pgmel02 | 172.28.5.12 | Replica | streaming |  1 |         0 |
| pgmel03 | 172.28.5.13 | Replica | streaming |  1 |         0 |
+---------+-------------+---------+-----------+----+-----------+
```

We already have 2 running replicas. So we’ll need to stop Patroni on one node and remove its data directory to trigger a new replica creation:

**pg03: ⇒**
```sh
sudo systemctl stop patroni
sudo find /var/lib/pgsql/16/data -mindepth 1 -delete
sudo systemctl start patroni
sudo journalctl -u patroni.service -f -n 100
```

```
May 29 14:38:50 pg03 systemd[1]: Stopping Runners to orchestrate a high-availability PostgreSQL...
May 29 14:38:50 pg03 systemd[1]: patroni.service: Deactivated successfully.
May 29 14:38:50 pg03 systemd[1]: Stopped Runners to orchestrate a high-availability PostgreSQL.
May 29 14:38:50 pg03 systemd[1]: Started Runners to orchestrate a high-availability PostgreSQL.
May 29 14:38:50 pg03 patroni[35591]: 2024-05-29 14:38:50.925 P00   INFO: restore command begin 2.52: --exec-id=35591-d560e758 --log-level-console=info --log-level-file=detail --pg1-path=/var/lib/pgsql/16/data --process-max=2 --repo2
-cipher-pass=<redacted> --repo2-cipher-type=aes-256-cbc --repo1-host=pgbackup01 --repo1-host-ca-file=/etc/pgbackrest/certs/ca.crt --repo1-host-cert-file=/etc/pgbackrest/certs/pg03.crt --repo1-host-key-file=/etc/pgbackrest/certs/pg03
.key --repo1-host-type=tls --repo1-host-user=postgres --repo2-path=/pgbackrest --repo2-s3-bucket=postgresql --repo2-s3-endpoint=minio01:9000 --repo2-s3-key=<redacted> --repo2-s3-key-secret=<redacted> --repo2-s3-region=us-east-1 --re
po2-s3-uri-style=path --no-repo2-storage-verify-tls --repo2-type=s3 --stanza=demo-cluster-1 --type=none
May 29 14:38:50 pg03 patroni[35591]: 2024-05-29 14:38:50.942 P00   INFO: repo1: restore backup set 20240529-143757F_20240529-143829I, recovery will start at 2024-05-29 14:38:29
May 29 14:38:53 pg03 patroni[35591]: 2024-05-29 14:38:53.432 P00   INFO: write updated /var/lib/pgsql/16/data/postgresql.auto.conf
May 29 14:38:53 pg03 patroni[35591]: 2024-05-29 14:38:53.438 P00   INFO: restore global/pg_control (performed last to ensure aborted restores cannot be started)
May 29 14:38:53 pg03 patroni[35591]: 2024-05-29 14:38:53.439 P00   INFO: restore size = 355.5MB, file total = 1296
May 29 14:38:53 pg03 patroni[35591]: 2024-05-29 14:38:53.439 P00   INFO: restore command end: completed successfully (2516ms)
May 29 14:38:53 pg03 patroni[35599]: 2024-05-29 14:38:53.743 EDT [35599] LOG:  redirecting log output to logging collector process
May 29 14:38:53 pg03 patroni[35599]: 2024-05-29 14:38:53.743 EDT [35599] HINT:  Future log output will appear in directory "log".
May 29 14:38:53 pg03 patroni[35604]: localhost:5432 - rejecting connections
May 29 14:38:53 pg03 patroni[35606]: localhost:5432 - rejecting connections
May 29 14:38:54 pg03 patroni[35613]: localhost:5432 - accepting connections
```

As we can see from the logs above, the replica has successfully been created using pgBackRest:

```sh
sudo -iu postgres patronictl -c /etc/patroni/patroni.yml list

+ Cluster: demo-cluster-1 (7373708270390346493) ---+-----------+
| Member  | Host        | Role    | State     | TL | Lag in MB |
+---------+-------------+---------+-----------+----+-----------+
| pgmel01 | 172.28.5.11 | Leader  | running   |  1 |           |
| pgmel02 | 172.28.5.12 | Replica | streaming |  1 |         0 |
| pgmel03 | 172.28.5.13 | Replica | streaming |  1 |         0 |
+---------+-------------+---------+-----------+----+-----------+
```

## References:

- [Patroni and pgBackRest combined | pgstef’s blog](https://pgstef.github.io/2022/07/12/patroni_and_pgbackrest_combined.html)
- [pgBackRest setup - Percona Distribution for PostgreSQL](https://docs.percona.com/postgresql/16/solutions/pgbackrest.html)
