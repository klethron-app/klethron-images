# syntax=docker/dockerfile:1
FROM ubuntu:26.04

ARG REX_VERSION=0.1.0~snapshot.2683
ARG IMAGE_REVISION=1
LABEL org.opencontainers.image.source="https://github.com/klethron-app/klethron-images" \
      org.opencontainers.image.version="${REX_VERSION}-r${IMAGE_REVISION}"

ADD --chmod=0644 --checksum=sha256:07a92e758ac2fc189efa17c24bf3df70d75e4216f6c262283a5c812377deb83e \
    https://pkgs.superlogical.com/rex/keys/rex-archive-keyring.gpg /etc/apt/keyrings/rex.gpg

# The snapshot channel uses ~alpha.N for Debian package versions.
RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates \
    && echo 'deb [signed-by=/etc/apt/keyrings/rex.gpg] https://pkgs.superlogical.com/rex/apt snapshot main' > /etc/apt/sources.list.d/rex.list \
    && apt-get update \
    && apt-get install -y --no-install-recommends openssh-server tini "rex=$(echo "$REX_VERSION" | sed 's/-snapshot\./~alpha./')" \
    && apt-mark hold rex \
    && rm -rf /var/lib/apt/lists/* \
    && rm -f /etc/ssh/ssh_host_*_key* \
    && install -d -m 0755 /run/sshd \
    && usermod --shell /bin/bash rex \
    && echo 'rex:test-password' | chpasswd \
    && install -d -o rex -g rex -m 0750 /run/rex

COPY <<'CONFIG' /etc/ssh/sshd_config
HostKey /etc/ssh/ssh_host_ed25519_key
AllowUsers rex
AuthenticationMethods password
PermitRootLogin no
AllowTcpForwarding local
AllowStreamLocalForwarding local
SetEnv REX_RUNTIME_DIR=/run/rex
Subsystem sftp internal-sftp
CONFIG

COPY --chmod=0755 <<'SCRIPT' /usr/local/bin/rex-entrypoint
#!/bin/bash
set -eu
if (( EUID != 0 )); then
    exec "$@"
fi
as_rex=(setpriv --reuid=rex --regid=rex --init-groups env HOME=/var/lib/rex USER=rex LOGNAME=rex SHELL=/bin/bash)
if [[ ${1:-} != rex || ${2:-} != server || ${3:-} != run ]]; then
    exec "${as_rex[@]}" "$@"
fi
if [[ ! -f /etc/ssh/ssh_host_ed25519_key ]]; then
    ssh-keygen -q -t ed25519 -N '' -f /etc/ssh/ssh_host_ed25519_key
fi
/usr/sbin/sshd -D -e &
sshd_pid=$!
"${as_rex[@]}" "$@" &
rex_pid=$!
stop_servers() {
    kill "$sshd_pid" "$rex_pid" 2>/dev/null || true
    wait
}
trap stop_servers EXIT
trap 'exit 0' TERM INT
wait -n
SCRIPT

WORKDIR /var/lib/rex
ENV REX_RUNTIME_DIR=/run/rex
EXPOSE 22/tcp 8080/tcp
ENTRYPOINT ["/usr/bin/tini", "-g", "--", "/usr/local/bin/rex-entrypoint"]
CMD ["rex", "server", "run", "--listen", "/run/rex/server.sock", "--extra-listen", "http://0.0.0.0:8080", "--allow-anonymous", "--state-dir", "/var/lib/rex", "--socket-mode", "0660", "--log-format", "text"]
