FROM debian:bookworm-slim

RUN apt-get update && \
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        qemu-utils \
        ntfs-3g \
        parted \
        util-linux \
        samba \
        procps \
    && rm -rf /var/lib/apt/lists/*

COPY mount-disk.sh /usr/local/bin/mount-disk.sh
COPY unmount-disk.sh /usr/local/bin/unmount-disk.sh
RUN chmod +x /usr/local/bin/mount-disk.sh /usr/local/bin/unmount-disk.sh

CMD ["sleep", "infinity"]
