FROM debian:bookworm-slim

LABEL maintainer="Juri Malinovski <coil93@gmail.com>"

ARG ETCD_VERSION=v3.5.17
ARG MINIO_URL=https://dl.min.io/client/mc/release/linux-amd64/mc
ARG MINIO_BIN=/usr/local/bin/mc

# download etcd
ADD https://storage.googleapis.com/etcd/${ETCD_VERSION}/etcd-${ETCD_VERSION}-linux-amd64.tar.gz etcd.tar.gz

RUN set -e && \
  apt -qq update && \
  groupadd -g 5001 etcdbackup && \
  useradd -u 5001 -g 5001 -s /bin/bash -d /opt/backup/data -m etcdbackup && \
  DEBIAN_FRONTEND=noninteractive apt -qqy install bash file curl openssl bzip2 && \
  curl -Ls -o "${MINIO_BIN}" "$MINIO_URL" && chmod +x "$MINIO_BIN" && \
  tar xzf etcd.tar.gz --directory /usr/local/bin --strip-components 1 && rm etcd.tar.gz && \
  rm -rf /var/lib/apt/lists/* /usr/share/doc /usr/share/man /usr/share/info

COPY --chmod=0755 entrypoint.sh /
COPY --chmod=0755 --chown=etcdbackup etcd-backup.sh /
WORKDIR /opt/backup/data
ENTRYPOINT [ "/entrypoint.sh" ]
