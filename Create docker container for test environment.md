---
tags:
  - docker
created: 03/26/2024 12:30 GMT-04:00
---


**Create bridge network**

```bash
docker network create \
  --driver=bridge \
  --subnet=172.28.0.0/16 \
  --ip-range=172.28.5.0/24 \
  --gateway=172.28.5.254 \
  br0
```

## MySelf

### PostgreSQL

```sh
docker run --privileged --detach --net br0 \
--volume /sys/fs/cgroup:/sys/fs/cgroup:rw \
--cgroupns=host \
--name pg01 -h pg01 \
--ip 172.28.5.11 \
-p 54311:5432 -p 22211:22 \
melihsavdert/docker-rockylinux-systemd:latest

docker run --privileged --detach --net br0 \
--volume /sys/fs/cgroup:/sys/fs/cgroup:rw \
--cgroupns=host \
--name pg02 -h pg02 \
--ip 172.28.5.12 \
-p 54312:5432 -p 22212:22 \
melihsavdert/docker-rockylinux-systemd:latest

docker run --privileged --detach --net br0 \
--volume /sys/fs/cgroup:/sys/fs/cgroup:rw \
--cgroupns=host \
--name pg03 -h pg03 \
--ip 172.28.5.13 \
-p 54313:5432 -p 22213:22 \
melihsavdert/docker-rockylinux-systemd:latest
```

### HaProxy

```sh
docker run --privileged --detach --net br0 \
--volume /sys/fs/cgroup:/sys/fs/cgroup:rw \
--cgroupns=host \
--name haproxy01 -h haproxy01 \
--ip 172.28.5.19 \
-p 50009:5000 -p 50019:5001 \
-p 22219:22 -p 7009:7000 \
melihsavdert/docker-rockylinux-systemd:latest
```

### EtcD

```sh
docker run --privileged --detach --net br0 \
--volume /sys/fs/cgroup:/sys/fs/cgroup:rw \
--cgroupns=host \
--name etcd01 -h etcd01 \
--ip 172.28.5.16 \
-p 22216:22 \
melihsavdert/docker-rockylinux-systemd:latest

docker run --privileged --detach --net br0 \
--volume /sys/fs/cgroup:/sys/fs/cgroup:rw \
--cgroupns=host \
--name etcd02 -h etcd02 \
--ip 172.28.5.17 \
-p 22217:22 \
melihsavdert/docker-rockylinux-systemd:latest

docker run --privileged --detach --net br0 \
--volume /sys/fs/cgroup:/sys/fs/cgroup:rw \
--cgroupns=host \
--name etcd03 -h etcd03 \
--ip 172.28.5.18 \
-p 22218:22 \
melihsavdert/docker-rockylinux-systemd:latest
```

### PostgreSQL Backup

```sh
docker run --privileged --detach --net br0 \
--volume /sys/fs/cgroup:/sys/fs/cgroup:rw \
--cgroupns=host \
--name pgbackup01 -h pgbackup01 \
--ip 172.28.5.15 \
-p 7485:7480 -p 22215:22 \
melihsavdert/docker-rockylinux-systemd:latest
```

### Oracle

```sh
docker run --privileged --detach --net br0 \
--volume /sys/fs/cgroup:/sys/fs/cgroup:rw \
--cgroupns=host \
--name ora01 -h ora01 \
--ip 172.28.5.21 \
-p 15211:1521 -p 22221:22 \
-p 9101:9100 -p 9111:9101 \
-p 9131:9103 -p 9141:9104 \
-p 8441:443 -p 8081:80 \
melihsavdert/docker-oraclelinux-systemd:8

docker run --privileged --detach --net br0 \
--volume /sys/fs/cgroup:/sys/fs/cgroup:rw \
--cgroupns=host \
--name ora02 -h ora02 \
--ip 172.28.5.22 \
-p 15212:1521 -p 22222:22 \
-p 9102:9100 -p 9112:9101 \
-p 9132:9103 -p 9142:9104 \
-p 8442:443 -p 8082:80 \
melihsavdert/docker-oraclelinux-systemd:8
```

### Goldengate

```sh
docker run --privileged --detach --net br0 \
--volume /sys/fs/cgroup:/sys/fs/cgroup:rw \
--cgroupns=host \
--name oraggmel01 -h oraggmel01 \
--ip 172.28.5.26 \
-p 9106:9100 -p 9116:9101 \
-p 9136:9103 -p 9146:9104 \
-p 8446:443 -p 8086:80 \
-p 22226:22 \
melihsavdert/docker-oraclelinux-systemd:latest
```

### SQL Server

```sh
docker run --privileged --detach --net br0 \
--volume /sys/fs/cgroup:/sys/fs/cgroup:rw \
--cgroupns=host \
--name mssqlmel01 -h mssqlmel01 \
--ip 172.28.5.31 \
-p 14331:1433 -p 22231:22 \
melihsavdert/docker-oraclelinux-systemd:latest
```

### Prometheus

```sh
docker run --privileged --detach --net br0 \
--volume /sys/fs/cgroup:/sys/fs/cgroup:rw \
--cgroupns=host \
--name prometheusmel01 -h prometheusmel01 \
--ip 172.28.5.41 \
-p 9041:9090 -p 22241:22 \
melihsavdert/docker-rockylinux-systemd:latest
```

### Grafana

```sh
docker run --privileged --detach --net br0 \
--volume /sys/fs/cgroup:/sys/fs/cgroup:rw \
--cgroupns=host \
--name grafanamel01 -h grafanamel01 \
--ip 172.28.5.51 \
-p 30051:3000 -p 22251:22 \
melihsavdert/docker-rockylinux-systemd:latest
```

### Ansible

```sh
docker run --privileged --detach --net br0 \
--volume /sys/fs/cgroup:/sys/fs/cgroup:rw \
--cgroupns=host \
--name ansiblemel01 -h ansiblemel01 \
--ip 172.28.5.61 \
-p 8441:8443 -p 22261:22 \
melihsavdert/docker-rockylinux-systemd:latest
```

### Minio

```sh
docker run --privileged --detach --net br0 \
--volume /sys/fs/cgroup:/sys/fs/cgroup:rw \
--cgroupns=host \
--name minio01 -h minio01 \
--ip 172.28.5.66 \
-p 9020:9001 -p 9021:9000 \
-p 22266:22 \
melihsavdert/docker-rockylinux-systemd:latest
```

## MTA

### PostgreSQL

```sh
docker run --privileged --detach --net br0 \
--volume /sys/fs/cgroup:/sys/fs/cgroup:rw \
--cgroupns=host \
--name pgmta01 -h pgmta01 \
--ip 172.28.5.11 \
-p 54311:5432 -p 22211:22 \
melihsavdert/docker-rockylinux-systemd:latest

docker run --privileged --detach --net br0 \
--volume /sys/fs/cgroup:/sys/fs/cgroup:rw \
--cgroupns=host \
--name pgmta02 -h pgmta02 \
--ip 172.28.5.12 \
-p 54312:5432 -p 22212:22 \
melihsavdert/docker-rockylinux-systemd:latest

docker run --privileged --detach --net br0 \
--volume /sys/fs/cgroup:/sys/fs/cgroup:rw \
--cgroupns=host \
--name pgmta03 -h pgmta03 \
--ip 172.28.5.13 \
-p 54313:5432 -p 22213:22 \
melihsavdert/docker-rockylinux-systemd:latest
```

### HaProxy

```sh
docker run --privileged --detach --net br0 \
--volume /sys/fs/cgroup:/sys/fs/cgroup:rw \
--cgroupns=host \
--name haproxymta01 -h haproxymta01 \
--ip 172.28.5.19 \
-p 50009:5000 -p 50019:5001 \
-p 22219:22 -p 7009:7000 \
melihsavdert/docker-rockylinux-systemd:latest
```

### EtcD

```sh
docker run --privileged --detach --net br0 \
--volume /sys/fs/cgroup:/sys/fs/cgroup:rw \
--cgroupns=host \
--name etcdmta01 -h etcdmta01 \
--ip 172.28.5.16 \
-p 22216:22 \
melihsavdert/docker-rockylinux-systemd:latest

docker run --privileged --detach --net br0 \
--volume /sys/fs/cgroup:/sys/fs/cgroup:rw \
--cgroupns=host \
--name etcdmta02 -h etcdmta02 \
--ip 172.28.5.17 \
-p 22217:22 \
melihsavdert/docker-rockylinux-systemd:latest

docker run --privileged --detach --net br0 \
--volume /sys/fs/cgroup:/sys/fs/cgroup:rw \
--cgroupns=host \
--name etcdmta03 -h etcdmta03 \
--ip 172.28.5.18 \
-p 22218:22 \
melihsavdert/docker-rockylinux-systemd:latest
```

### PostgreSQL Backup

```sh
docker run --privileged --detach --net br0 \
--volume /sys/fs/cgroup:/sys/fs/cgroup:rw \
--cgroupns=host \
--name pgbackupmta01 -h pgbackupmta01 \
--ip 172.28.5.15 \
-p 7485:7480 -p 22215:22 \
melihsavdert/docker-rockylinux-systemd:latest
```

### Oracle

```sh
docker run --privileged --detach --net br0 \
--volume /sys/fs/cgroup:/sys/fs/cgroup:rw \
--cgroupns=host \
--name oramta01 -h oramta01 \
--ip 172.28.5.21 \
-p 15221:1521 -p 22221:22 \
melihsavdert/docker-oraclelinux-systemd:8

docker run --privileged --detach --net br0 \
--volume /sys/fs/cgroup:/sys/fs/cgroup:rw \
--cgroupns=host \
--name oramta02 -h oramta02 \
--ip 172.28.5.22 \
-p 15222:1521 -p 22222:22 \
melihsavdert/docker-oraclelinux-systemd:8
```

### OEM

```sh
docker run --privileged --detach --net br0 \
--volume /sys/fs/cgroup:/sys/fs/cgroup:rw \
--cgroupns=host \
--name oemmta01 -h oemmta01 \
--ip 172.28.5.26 \
-p 15226:1521 -p 22226:22 \
-p 7786:7788 -p 7806:7803 \
-p 7106:7102 -p 9806:9803 \
melihsavdert/docker-oraclelinux-systemd:8
```

### SQL Server

```sh
docker run --privileged --detach --net br0 \
--volume /sys/fs/cgroup:/sys/fs/cgroup:rw \
--cgroupns=host \
--name mssqlmta01 -h mssqlmta01 \
--ip 172.28.5.31 \
-p 14331:1433 -p 22231:22 \
melihsavdert/docker-oraclelinux-systemd:latest
```

### Prometheus

```sh
docker run --privileged --detach --net br0 \
--volume /sys/fs/cgroup:/sys/fs/cgroup:rw \
--cgroupns=host \
--name prometheusmta01 -h prometheusmta01 \
--ip 172.28.5.41 \
-p 9041:9090 -p 22241:22 \
melihsavdert/docker-rockylinux-systemd:latest
```

### Grafana

```sh
docker run --privileged --detach --net br0 \
--volume /sys/fs/cgroup:/sys/fs/cgroup:rw \
--cgroupns=host \
--name grafanamta01 -h grafanamta01 \
--ip 172.28.5.51 \
-p 30051:3000 -p 22251:22 \
melihsavdert/docker-rockylinux-systemd:latest

docker run --privileged --detach --net br0 \
--volume /sys/fs/cgroup:/sys/fs/cgroup:rw \
--cgroupns=host \
--name pgmtagrafana01 -h pgmtagrafana01 \
--ip 172.28.5.16 \
-p 54313:5432 -p 22213:22 \
melihsavdert/docker-rockylinux-systemd:latest
```

### Ansible

```sh
docker run --privileged --detach --net br0 \
--volume /sys/fs/cgroup:/sys/fs/cgroup:rw \
--cgroupns=host \
--name ansiblemta01 -h ansiblemta01 \
--ip 172.28.5.61 \
-p 8441:8443 -p 22261:22 \
melihsavdert/docker-rockylinux-systemd:latest
```
