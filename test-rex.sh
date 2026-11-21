#!/usr/bin/env bash
set -euo pipefail

image=${1:?usage: bash test-rex.sh IMAGE}
work=$(mktemp -d)
container=$(docker run --detach -p 127.0.0.1::22 -p 127.0.0.1::8080 "$image")
cleanup() {
    docker rm -f "$container" >/dev/null
    rm -rf "$work"
}
trap cleanup EXIT

http=$(docker port "$container" 8080/tcp)
ssh_endpoint=$(docker port "$container" 22/tcp)
[[ "$http" =~ ^127\.0\.0\.1:[0-9]+$ && "$ssh_endpoint" =~ ^127\.0\.0\.1:[0-9]+$ ]]
for attempt in {1..20}; do
    if docker run --rm --network host "$image" rex --autostart=false --server "http://$http" server status --json >"$work/http.json"; then
        break
    fi
    if [[ "$attempt" == 20 ]]; then
        docker logs "$container"
        exit 1
    fi
    sleep 1
done
instance=$(jq -er '.instance_id | select(length > 0)' "$work/http.json")

port=${ssh_endpoint##*:}
host_key=$(docker exec "$container" cat /etc/ssh/ssh_host_ed25519_key.pub)
printf '[127.0.0.1]:%s %s\n' "$port" "$host_key" >"$work/known_hosts"
printf '#!/bin/sh\necho test-password\n' >"$work/askpass"
chmod 700 "$work/askpass"
export SSH_ASKPASS="$work/askpass" SSH_ASKPASS_REQUIRE=force
ssh=(ssh -F /dev/null -p "$port" -o "UserKnownHostsFile=$work/known_hosts" -o StrictHostKeyChecking=yes
    -o PreferredAuthentications=password -o NumberOfPasswordPrompts=1 -o ConnectTimeout=5)
"${ssh[@]}" rex@127.0.0.1 'rex server start --json' |
    jq -e 'any(.listeners[]; .primary and .endpoint == "unix:///run/rex/server.sock")' >/dev/null
"${ssh[@]}" -fNT -o ExitOnForwardFailure=yes -L "$work/forward.sock:/run/rex/server.sock" rex@127.0.0.1
docker run --rm --user "$(id -u):$(id -g)" --volume "$work:/probe:ro" "$image" \
    rex --autostart=false --server unix:///probe/forward.sock server status --json |
    jq -e --arg instance "$instance" '.instance_id == $instance' >/dev/null
