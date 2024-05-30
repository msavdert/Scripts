---
database: PostgreSQL
title: High Availability
class: patroni
created: 05/12/2024 16:10 GMT-04:00
---
[[Create docker container for test environment#MySelf#EtcD]]
[[Create docker container for test environment#MySelf#PostgreSQL]]
[[Create docker container for test environment#MySelf#HaProxy]]

![[Pasted image 20240514113157.png]]

## Environment

| **Hostname** | **IP Address** | **Applications**              |
| ------------ | -------------- | ----------------------------- |
| pg01         | 172.28.5.11    | postgresql 16 / patroni 3.3.0 |
| pg02         | 172.28.5.12    | postgresql 16 / patroni 3.3.0 |
| pg03         | 172.28.5.13    | postgresql 16 / patroni 3.3.0 |
| etcd01       | 172.28.5.16    | etcd 3.5                      |
| etcd02       | 172.28.5.17    | etcd 3.5                      |
| etcd03       | 172.28.5.18    | etcd 3.5                      |
| haproxy01    | 172.28.5.19    | HAProxy 2.4                   |
## EtcD

**Prepare**

```sh
# update
sudo dnf update -y

# timezone
sudo rm -rf /etc/localtime
sudo ln -s /usr/share/zoneinfo/America/New_York /etc/localtime

# chrony
sudo dnf install -y chrony
sudo systemctl enable --now chronyd

# extras
sudo dnf install -y bind-utils hostname iproute procps
```

**Installation**

PostgreSQL 16 repository on Red Hat Family 9 : https://www.postgresql.org/download/linux/redhat/

```sh
sudo dnf install -y https://download.postgresql.org/pub/repos/yum/reporpms/EL-9-x86_64/pgdg-redhat-repo-latest.noarch.rpm
sudo dnf --enablerepo=pgdg-rhel9-extras install -y etcd
```

**Check**

```sh
etcd version
etcdctl version
```

To fetch it dynamically, you can use this simple shell script, where etcdmel01 etcdmel02 etcdmel03 are the three etcd hosts:

```sh
# Fetch the IP addresses of all etcd hosts
etcd_nodes=( etcd01 etcd02 etcd03 )
i=0
for node in "${etcd_nodes[@]}"
do
  i=$i+1
  target_ip=$(dig +short $node)
  target_array[$i]="$node=http://$target_ip:2380"
done
ETCD_CLUSTER_URL=$(printf ",%s" "${target_array[@]}")
export ETCD_CLUSTER_URL=${ETCD_CLUSTER_URL:1}
echo "ETCD_CLUSTER_URL=\"$ETCD_CLUSTER_URL\""
```

Then, set up the local etcd configuration and start the service:

>[!note]
>execute all nodes same time

```sh
MY_IP=$(hostname -I | awk ' {print $1}')
MY_NAME=$(hostname --short)
cat <<EOF | sudo tee /etc/etcd/etcd.conf
#[Member]
ETCD_LISTEN_PEER_URLS="http://$MY_IP:2380"
ETCD_LISTEN_CLIENT_URLS="http://127.0.0.1:2379,http://$MY_IP:2379"
ETCD_NAME="$MY_NAME"
#[Clustering]
ETCD_INITIAL_ADVERTISE_PEER_URLS="http://$MY_IP:2380"
ETCD_INITIAL_CLUSTER="$ETCD_CLUSTER_URL"
ETCD_ADVERTISE_CLIENT_URLS="http://$MY_IP:2379"
ETCD_INITIAL_CLUSTER_TOKEN="etcd-cluster-1"
ETCD_INITIAL_CLUSTER_STATE="new"
#[Tune]
ETCD_ELECTION_TIMEOUT="5000"
ETCD_HEARTBEAT_INTERVAL="1000"
ETCD_INITIAL_ELECTION_TICK_ADVANCE="false"
ETCD_AUTO_COMPACTION_RETENTION="1"
#[Data]
#ETCD_DATA_DIR="{{ etcd_data_dir }}"
EOF
sudo systemctl enable --now etcd.service
sudo systemctl status etcd.service --no-pager
```

**Check**

```sh
journalctl -u etcd -f
```

```sh
etcd_nodes=( etcd01 etcd02 etcd03 )
i=0
for node in "${etcd_nodes[@]}"
do
  i=$i+1
  target_ip=$(dig +short $node)
  target_array[$i]="$target_ip:2379"
done
ETCD_CLUSTER_URL=$(printf ",%s" "${target_array[@]}")
export ENDPOINTS=${ETCD_CLUSTER_URL:1}

etcdctl member list --write-out=table --endpoints=$ENDPOINTS

etcdctl endpoint status --write-out=table --endpoints=$ENDPOINTS

etcdctl endpoint health --write-out=table --endpoints=$ENDPOINTS
```

```
+------------------+---------+-----------+-------------------------+-------------------------+------------+
|        ID        | STATUS  |   NAME    |       PEER ADDRS        |      CLIENT ADDRS       | IS LEARNER |
+------------------+---------+-----------+-------------------------+-------------------------+------------+
|  3a925a774311aaf | started | etcdmta01 | http://172.28.5.16:2380 | http://172.28.5.16:2379 |      false |
| 3b54c768268e90bf | started | etcdmta03 | http://172.28.5.18:2380 | http://172.28.5.18:2379 |      false |
| 9bbf1d1a71c1f6f1 | started | etcdmta02 | http://172.28.5.17:2380 | http://172.28.5.17:2379 |      false |
+------------------+---------+-----------+-------------------------+-------------------------+------------+
+------------------+------------------+---------+---------+-----------+------------+-----------+------------+--------------------+--------+
|     ENDPOINT     |        ID        | VERSION | DB SIZE | IS LEADER | IS LEARNER | RAFT TERM | RAFT INDEX | RAFT APPLIED INDEX | ERRORS |
+------------------+------------------+---------+---------+-----------+------------+-----------+------------+--------------------+--------+
| 172.28.5.16:2379 |  3a925a774311aaf |  3.5.13 |   20 kB |     false |      false |         3 |         17 |                 17 |        |
| 172.28.5.17:2379 | 9bbf1d1a71c1f6f1 |  3.5.13 |   20 kB |      true |      false |         3 |         17 |                 17 |        |
| 172.28.5.18:2379 | 3b54c768268e90bf |  3.5.13 |   20 kB |     false |      false |         3 |         17 |                 17 |        |
+------------------+------------------+---------+---------+-----------+------------+-----------+------------+--------------------+--------+
+------------------+--------+------------+-------+
|     ENDPOINT     | HEALTH |    TOOK    | ERROR |
+------------------+--------+------------+-------+
| 172.28.5.17:2379 |   true | 1.713569ms |       |
| 172.28.5.16:2379 |   true |  1.76719ms |       |
| 172.28.5.18:2379 |   true | 3.104073ms |       |
+------------------+--------+------------+-------+
```

## PostgreSQL + Patroni

### Prepare

```sh
# update
sudo dnf update -y

# timezone
sudo rm -rf /etc/localtime
sudo ln -s /usr/share/zoneinfo/America/New_York /etc/localtime

# chrony
sudo dnf install -y chrony
sudo systemctl enable --now chronyd

# extras
sudo dnf install -y bind-utils hostname iproute procps procps
```

### Install PostgreSQL

[[PostgreSQL 16 Installation on Red Hat Family 9]]

```sh
sudo dnf install -y https://download.postgresql.org/pub/repos/yum/reporpms/EL-9-x86_64/pgdg-redhat-repo-latest.noarch.rpm
sudo dnf -qy module disable postgresql
sudo dnf install -y postgresql16-server postgresql16-contrib
```

### Install Patroni

```sh
sudo dnf install epel-release -y
sudo dnf -y install patroni patroni-etcd

chown -R postgres:postgres /var/log/patroni
```

**Check**

```sh
patroni --version
patronictl version

----

patroni 3.3.0
patronictl version 3.3.0
```

```sh
export PGPORT=5432
export PGUSER=postgres
export PGGROUP=postgres
export PGDATA="/var/lib/pgsql/16/data"
export PGBIN="/usr/pgsql-16/bin"
export PGBINNAME="postgres"
export PGSOCKET="/var/run/postgresql"
export ETCD1=etcd01:2379
export ETCD2=etcd02:2379
export ETCD3=etcd03:2379

CLUSTER_NAME="demo-cluster-1"
MY_NAME=$(hostname --short)
MY_IP=$(hostname -I | awk ' {print $1}')

cat <<EOF | sudo tee /etc/patroni/patroni.yml
scope: $CLUSTER_NAME
namespace: /db/
name: $MY_NAME

log:
  type: plain
  level: INFO
  traceback_level: ERROR
  format: "%(asctime)s %(levelname)s: %(message)s"
  dateformat: ""
  max_queue_size: 1000
  dir: /var/log/patroni
  file_num: 4
  file_size: 25000000  # bytes
  loggers:
    patroni.postmaster: WARNING
    urllib3: WARNING

restapi:
  listen: "0.0.0.0:8008"
  connect_address: "$MY_IP:8008"
  authentication:
    username: patroni
    password: mySupeSecretPassword

etcd3:
    hosts:
    - ${ETCD1}
    - ${ETCD2}
    - ${ETCD3}

bootstrap:
  dcs:
    ttl: 30
    loop_wait: 10
    retry_timeout: 10
    maximum_lag_on_failover: 1048576
    master_start_timeout: 300
    postgresql:
      use_pg_rewind: true
      use_slots: true
      parameters:
        archive_mode: "on"
        archive_command: "/bin/true"

  initdb:
  - encoding: UTF8
  - data-checksums
  - auth-local: peer
  - auth-host: scram-sha-256

  pg_hba:
  - host replication replicator 0.0.0.0/0 scram-sha-256
  - host all all 0.0.0.0/0 scram-sha-256

  # Some additional users which needs to be created after initializing new cluster
  users:
    admin:
      password: admin%
      options:
        - createrole
        - createdb

postgresql:
  listen: "0.0.0.0:$PGPORT"
  connect_address: "$MY_IP:$PGPORT"
  data_dir: $PGDATA
  bin_dir: $PGBIN
  bin_name:
    postgres: $PGBINNAME
  pgpass: /tmp/pgpass0
  authentication:
    replication:
      username: replicator
      password: confidential
    superuser:
      username: $PGUSER
      password: my-super-password
    rewind:
      username: rewind_user
      password: rewind_password
  parameters:
    unix_socket_directories: "$PGSOCKET,/tmp"

#watchdog:
#  mode: required
#  device: /dev/watchdog
#  safety_margin: 5

tags:
  nofailover: false
  noloadbalance: false
  clonefrom: false
  nosync: false
EOF
chown -R postgres:postgres /etc/patroni
```

Validate Patroni configuration

```sh
patroni --validate-config /etc/patroni/patroni.yml
```

```sh
systemctl enable --now patroni

sleep 5

patronictl -c /etc/patroni/patroni.yml list
```

```
+ Cluster: demo-cluster-1 (7369029293996131125) ---+-----------+
| Member  | Host        | Role    | State     | TL | Lag in MB |
+---------+-------------+---------+-----------+----+-----------+
| pgmel01 | 172.28.5.11 | Leader  | running   |  1 |           |
| pgmel02 | 172.28.5.12 | Replica | streaming |  1 |         0 |
| pgmel03 | 172.28.5.13 | Replica | streaming |  1 |         0 |
+---------+-------------+---------+-----------+----+-----------+
```

>[!note]
>Once Patroni has initialized the cluster for the first time and settings have been stored in the DCS, all future changes to the `bootstrap.dcs` section of the YAML configuration will not take any effect! If you want to change them please use either [patronictl edit-config](https://patroni.readthedocs.io/en/latest/patronictl.html#patronictl-edit-config) or the Patroni [REST API](https://patroni.readthedocs.io/en/latest/rest_api.html#rest-api).

## HAProxy

**Prepare**

```sh
# update
sudo dnf update -y

# timezone
sudo rm -rf /etc/localtime
sudo ln -s /usr/share/zoneinfo/America/New_York /etc/localtime

# chrony
sudo dnf install -y chrony
sudo systemctl enable --now chronyd

# extras
sudo dnf install -y bind-utils hostname iproute
```

**Install**

```sh
sudo dnf install -y haproxy
sudo cp /etc/haproxy/haproxy.cfg /etc/haproxy/haproxy.cfg.bck
```

```sh
export PGPORT=5432
export PGNODE1=pg01
export PGNODE2=pg02
export PGNODE3=pg03

cat <<EOF | sudo tee /etc/haproxy/haproxy.cfg
global
    maxconn 100
    log /dev/log    local0
    log /dev/log    local1 notice
    chroot /var/lib/haproxy
    stats socket /var/lib/haproxy/stats mode 660 level admin expose-fd listeners
    stats timeout 30s
    user haproxy
    group haproxy
    daemon

defaults
    mode               tcp
    log                global
    retries            2
    timeout queue      5s
    timeout connect    5s
    timeout client     30m
    timeout server     30m
    timeout check      15s

listen stats
    mode http
    bind *:7000
    stats enable
    stats uri /

listen read-write
    bind *:5000
    option httpchk OPTIONS /read-write
    http-check expect status 200
    default-server inter 3s fastinter 1s fall 3 rise 4 on-marked-down shutdown-sessions
    server $PGNODE1 $PGNODE1:$PGPORT maxconn 100 check port 8008
    server $PGNODE2 $PGNODE2:$PGPORT maxconn 100 check port 8008
    server $PGNODE3 $PGNODE3:$PGPORT maxconn 100 check port 8008

listen read-only
    balance roundrobin
    bind *:5001
    option httpchk OPTIONS /replica
    http-check expect status 200
    default-server inter 3s fastinter 1s fall 3 rise 4 on-marked-down shutdown-sessions
    server $PGNODE1 $PGNODE1:$PGPORT maxconn 100 check port 8008
    server $PGNODE2 $PGNODE2:$PGPORT maxconn 100 check port 8008
    server $PGNODE3 $PGNODE3:$PGPORT maxconn 100 check port 8008
EOF
sudo systemctl enable --now haproxy
sudo systemctl status haproxy --no-pager
```

```sh
curl -s http://pg01:8008
```

```
{
  "state": "running",
  "postmaster_start_time": "2024-05-29 11:28:11.914207-04:00",
  "role": "master",
  "server_version": 160003,
  "xlog": {
    "location": 84205792
  },
  "timeline": 1,
  "replication": [
    {
      "usename": "replicator",
      "application_name": "pg02",
      "client_addr": "172.28.5.12",
      "state": "streaming",
      "sync_state": "async",
      "sync_priority": 0
    },
    {
      "usename": "replicator",
      "application_name": "pg03",
      "client_addr": "172.28.5.13",
      "state": "streaming",
      "sync_state": "async",
      "sync_priority": 0
    }
  ],
  "dcs_last_seen": 1716996792,
  "database_system_identifier": "7374443775163790452",
  "patroni": {
    "version": "3.3.0",
    "scope": "demo-cluster-1",
    "name": "pg01"
  }
}
```

```sh
curl -s http://pg02:8008
```

```
{
  "state": "running",
  "postmaster_start_time": "2024-05-29 11:28:26.794000-04:00",
  "role": "replica",
  "server_version": 160003,
  "xlog": {
    "received_location": 84205792,
    "replayed_location": 84205792,
    "replayed_timestamp": "2024-05-29 11:29:42.060016-04:00",
    "paused": false
  },
  "timeline": 1,
  "replication_state": "streaming",
  "dcs_last_seen": 1716996822,
  "database_system_identifier": "7374443775163790452",
  "patroni": {
    "version": "3.3.0",
    "scope": "demo-cluster-1",
    "name": "pg02"
  }
}
```

http://haproxy01:7000

![[Pasted image 20240514212518.png]]

**Test**

```
psql -U postgres -d postgres -h haproxy01 -p 5000 -c "SELECT pg_is_in_recovery();"

 pg_is_in_recovery
-------------------
 f
```

```
psql -U postgres -d postgres -h haproxy01 -p 5001 -c "SELECT pg_is_in_recovery();"

 pg_is_in_recovery
-------------------
 t
```

## References:

- [EDB Docs - Installing and configuring etcd](https://www.enterprisedb.com/docs/supported-open-source/patroni/installing_etcd/)
- [VMware Postgres High Availability with Patroni](https://docs.vmware.com/en/VMware-Postgres/16.2/vmware-postgres/bp-patroni-setup.html)
- [EDB Docs - Quick start on RHEL 8 (enterprisedb.com)](https://www.enterprisedb.com/docs/supported-open-source/patroni/rhel8_quick_start/)
- [Deploy a highly available Postgres cluster on Oracle Cloud Infrastructure](https://docs.oracle.com/en/learn/deploy-ha-postgres-oci/index.html#task-2-install-and-configure-the-software)
- [High availability - Percona Distribution for PostgreSQL](https://docs.percona.com/postgresql/16/solutions/high-availability.html)
- 
