#!/usr/bin/env bash
set -euo pipefail

image=${1:?usage: bash test-netstack-peer.sh IMAGE}
container=$(docker run --detach -p 127.0.0.1::47123/udp --cap-add NET_ADMIN --device /dev/net/tun \
    --sysctl net.ipv6.conf.all.disable_ipv6=0 --sysctl net.ipv6.conf.default.accept_dad=0 \
    "$image" -listen 0.0.0.0:47123)
cleanup() {
    if [[ $? != 0 ]]; then
        docker logs "$container" >&2 || true
    fi
    docker rm -f "$container" >/dev/null
}
trap cleanup EXIT

for attempt in {1..20}; do
    if docker logs "$container" 2>/dev/null | grep '^LISTEN ' >/dev/null; then
        break
    fi
    if [[ "$attempt" == 20 ]]; then
        exit 1
    fi
    sleep 1
done
[[ "$(docker port "$container" 47123/udp)" =~ ^127\.0\.0\.1:[0-9]+$ ]]
addresses=$(docker exec "$container" ip -o addr show dev kns0)
grep -q 'inet 100\.64\.0\.2/32 ' <<< "$addresses"
grep -q 'inet6 fd7a:115c:a1e0::2/128 ' <<< "$addresses"
