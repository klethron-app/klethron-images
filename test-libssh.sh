#!/usr/bin/env bash
set -euo pipefail

image=${1:?usage: bash test-libssh.sh IMAGE}
docker run --rm -i "$image" sh -eu <<'CONTAINER'
library=$(pkg-config --variable=libdir libssh)/libssh.so
test "$(pkg-config --variable=prefix libssh)" = /opt/libssh
readelf -SW "$library" | grep -wq .debug_info
readelf -dW "$library" | grep -q 'NEEDED.*libasan'
readelf -Ws "$library" | grep -q 'UND __asan_init'

cat >/tmp/check.c <<'C'
#include <libssh/libssh.h>
#include <stdio.h>
int main(void) {
    ssh_session session = ssh_new();
    if (session == NULL) return 1;
    puts(ssh_version(0));
    ssh_free(session);
    return 0;
}
C
libssh-asan-cc -no-pie /tmp/check.c $(pkg-config --cflags --libs libssh) -o /tmp/check
ldd /tmp/check | grep -Fq "libssh.so.4 => /opt/libssh/lib/libssh.so.4"
/tmp/check
CONTAINER
