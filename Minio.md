---
os: Linux
tool: Minio
created: 05/29/2024 10:52
---
## Installation

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

```sh
vi /etc/default/minio
```

```
MINIO_OPTS="--console-address :9001"
MINIO_ROOT_USER=minioadmin
MINIO_ROOT_PASSWORD=minioadmin
MINIO_VOLUMES="/minio-data/"
```

```sh
systemctl daemon-reload
systemctl enable --now minio
systemctl status minio --no-pager
```

### TLS/HTTPS

[Generate Let’s Encrypt certificate using Certbot for MinIO — MinIO Object Storage for Linux](https://min.io/docs/minio/linux/integrations/generate-lets-encrypt-certificate-using-certbot-for-minio.html)

**Install certbot**

```sh
dnf install -y epel-release
dnf install -y certbot
```

**Generate Let’s Encrypt cert**

```sh
certbot certonly --standalone -d `hostname` --staple-ocsp -m test@yourdomain.io --agree-tos
```

**Verify Certificates**

List your certs saved in `/etc/letsencrypt/live/myminio.com` directory.

```sh
ls -l /etc/letsencrypt/live/myminio.com
```
