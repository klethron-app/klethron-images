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
image=ghcr.io/klethron-app/klethron-images/rex:0.1.0-snapshot.2531-r1
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

## libssh

`ghcr.io/klethron-app/klethron-images/libssh:latest` contains the upstream
development branch (`master`) built with GCC AddressSanitizer, debug symbols
and frame pointers. Headers, the shared library and pkg-config metadata live
under `/opt/libssh`. Debug symbols refer to sources included in `/usr/src/libssh`.
The published Linux/amd64 image includes Rust 1.100.0 for the ssh-client-tester adapter.

The workflow resolves upstream to an exact commit on pushes affecting the
image and on manual dispatch. It tests a dynamically linked client
before publishing `latest` and `git-<full-libssh-commit>`. The OCI version
label records that commit. Pin the GHCR digest to repeat the exact image build.

To build and check the image locally:

```sh
revision=$(git ls-remote --exit-code https://gitlab.com/libssh/libssh-mirror.git refs/heads/master | cut -f1)
docker build --build-arg "LIBSSH_REVISION=$revision" -t libssh:local - < Dockerfile.libssh
bash test-libssh.sh libssh:local
```

Link native clients with `-fsanitize=address`. For Rust test executables,
`-C linker=libssh-asan-cc` places the ASan runtime first during linking.

## OpenSSH

The OpenSSH image contains a snapshot of OpenSSH Portable's development
branch (`master`). The Linux/amd64 image includes
Rust 1.100.0, Clang's symbolizer, and the unstripped `ssh`, `scp` and
`sftp` clients in `/opt/openssh/bin` on `PATH`. All three use AddressSanitizer
and UndefinedBehaviorSanitizer with fatal findings. Their built-in defaults
disable leak checking and abort on errors even with an empty environment.
The source used for stack traces is in `/usr/src/openssh`.

Pin a tag such as `10.6p2-git.fa4b2a82be7d-r1` to repeat a build. The tag
records the OpenSSH version, the first 12 digits of the upstream commit,
and the image revision from `Dockerfile.openssh`. Bump `IMAGE_REVISION`
when changing the recipe, toolchain or base image for the same snapshot.
The OCI version label records the tag and the revision label records the
full upstream commit.

The workflow checks upstream on image-related pushes to `main` and
on manual dispatch. It skips builds for existing versioned tags. For a new
tag, it verifies instrumentation and runs all three clients before publishing.
The `latest` alias points to the published snapshot.

```sh
docker run --rm ghcr.io/klethron-app/klethron-images/openssh:10.6p2-git.fa4b2a82be7d-r1 ssh -V
```
