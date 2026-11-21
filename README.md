# klethron-images

Images used for testing.

## Rex

`Dockerfile.rex` pins the Rex version and image revision. On container start,
Rex runs as the `rex` user and accepts connections on `/run/rex/server.sock`
and via HTTP/WebSocket on TCP port 8080. The TCP listener allows anonymous
test clients. Publish it on host loopback with a Docker-assigned port.

```sh
image=ghcr.io/klethron-app/klethron-images/rex:0.1.0-snapshot.2506-r3
container=$(docker run --detach --rm --publish 127.0.0.1::8080 "$image")
docker port "$container" 8080/tcp
```

Use `http://` followed by the printed address as the Rex endpoint. Run
`docker stop "$container"` when the test finishes.

When a push to `main` changes `Dockerfile.rex`, GitHub Actions publishes
`ghcr.io/klethron-app/klethron-images/rex:<REX_VERSION>-r<IMAGE_REVISION>`.
Bump the revision when changing the image for the same Rex version. The job
fails if the tag already exists.

The workflow authenticates to GHCR with the repository’s built-in
`GITHUB_TOKEN` and the `packages: write` permission.
