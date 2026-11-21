# klethron-images

Images used for testing.

## Rex

`Dockerfile.rex` pins the Rex version and image revision. On container start,
Rex runs as the `rex` user and accepts connections on `/run/rex/server.sock`
and via HTTP/WebSocket on TCP port 8080. OpenSSH listens on port 22 and
forwards connections to the same Unix socket. The fixture accepts anonymous
HTTP clients and has a fixed SSH login, `rex` / `test-password`. Publish the
test ports on host loopback. Docker assigns an available host port to each.

```sh
image=ghcr.io/klethron-app/klethron-images/rex:0.1.0-snapshot.2506-r4
container=$(docker run --detach --rm -p 127.0.0.1::22 -p 127.0.0.1::8080 "$image")
ssh_endpoint=$(docker port "$container" 22/tcp)
docker port "$container" 8080/tcp
ssh -p "${ssh_endpoint##*:}" rex@127.0.0.1 'rex server status --json'
```

Use `http://` followed by the printed HTTP address as the direct Rex endpoint.
The Android emulator reaches the same host ports at `10.0.2.2`. Each container
generates its own SSH host key. Tests can read the public key with
`docker exec "$container" cat /etc/ssh/ssh_host_ed25519_key.pub`.
Run `docker stop "$container"` when the test finishes.

When a push to `main` changes `Dockerfile.rex`, GitHub Actions publishes
`ghcr.io/klethron-app/klethron-images/rex:<REX_VERSION>-r<IMAGE_REVISION>`.
Bump the revision when changing the image for the same Rex version. The job
fails if the tag already exists.

The workflow authenticates to GHCR with the repository’s built-in
`GITHUB_TOKEN` and the `packages: write` permission.
