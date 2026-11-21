# syntax=docker/dockerfile:1
FROM ubuntu:26.04

ARG REX_VERSION=0.1.0-snapshot.2506
ARG IMAGE_REVISION=3
LABEL org.opencontainers.image.source="https://github.com/klethron-app/klethron-images" \
      org.opencontainers.image.version="${REX_VERSION}-r${IMAGE_REVISION}"

ADD --chmod=0644 --checksum=sha256:07a92e758ac2fc189efa17c24bf3df70d75e4216f6c262283a5c812377deb83e \
    https://pkgs.superlogical.com/rex/keys/rex-archive-keyring.gpg /etc/apt/keyrings/rex.gpg

# The snapshot channel uses ~alpha.N for Debian package versions.
RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates \
    && echo 'deb [signed-by=/etc/apt/keyrings/rex.gpg] https://pkgs.superlogical.com/rex/apt snapshot main' > /etc/apt/sources.list.d/rex.list \
    && apt-get update \
    && apt-get install -y --no-install-recommends "rex=$(echo "$REX_VERSION" | sed 's/-snapshot\./~alpha./')" \
    && apt-mark hold rex \
    && rm -rf /var/lib/apt/lists/* \
    && usermod --shell /bin/bash rex \
    && install -d -o rex -g rex -m 0750 /run/rex

USER rex
WORKDIR /var/lib/rex
ENV REX_RUNTIME_DIR=/run/rex
EXPOSE 8080/tcp
CMD ["rex", "server", "run", "--listen", "/run/rex/server.sock", "--extra-listen", "http://0.0.0.0:8080", "--allow-anonymous", "--state-dir", "/var/lib/rex", "--socket-mode", "0660", "--log-format", "text"]
