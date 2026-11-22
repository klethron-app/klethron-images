#!/usr/bin/env bash
set -euo pipefail

image=${1:?usage: bash test-openssh.sh IMAGE}
docker run --rm -i "$image" sh -eu <<'CONTAINER'
command -v llvm-symbolizer
for client in ssh scp sftp; do
    binary=/opt/openssh/bin/$client
    test "$(command -v "$client")" = "$binary"
    readelf -SW "$binary" | grep -wq .debug_info
    # Check calls emitted in the client's own code. Both sanitizer runtimes
    # can be present in an executable whose source was never instrumented.
    objdump -d --disassemble=main "$binary" > /tmp/main.asm
    grep -Eq 'call.*<__asan_report_' /tmp/main.asm
    grep -Eq 'call.*<__ubsan_handle_[^>]*_abort>' /tmp/main.asm
done

ssh -V
ssh -G -F /dev/null localhost | grep -qx 'hostname localhost'
for client in scp sftp; do
    status=0
    "$client" 2>/tmp/usage || status=$?
    test "$status" = 1
    grep -q "^usage: $client " /tmp/usage
done
CONTAINER
