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

## Netstack peer

`Dockerfile.netstack-peer` builds the Go program in `netstack-peer/`, a test
peer for the TCP/IP stack in Klethron's `klethron-tailnet` module, and runs
it on Alpine. The peer serves from the Linux kernel's TCP behind a TUN device,
`kns0`, with the addresses `100.64.0.2/32` and `fd7a:115c:a1e0::2/128` and an
MTU of 1280. It exchanges raw IP packets with the client as UDP datagrams on
its `-listen` address and replies to whichever address sent the last one.
When ready, it prints `LISTEN` and that address.

The container needs `NET_ADMIN`, the TUN device and IPv6. Duplicate address
detection must be off, since nothing answers it on a TUN device. Publish the
UDP port on host loopback:

```sh
image=ghcr.io/klethron-app/klethron-images/netstack-peer:r1
container=$(docker run --detach --rm -p 127.0.0.1::47123/udp \
    --cap-add NET_ADMIN --device /dev/net/tun \
    --sysctl net.ipv6.conf.all.disable_ipv6=0 \
    --sysctl net.ipv6.conf.default.accept_dad=0 \
    "$image" -listen 0.0.0.0:47123)
docker port "$container" 47123/udp
```

Run `docker stop "$container"` when the test finishes.

TCP port 7 on both addresses serves the `KNS1` transfer check. The client
sends `KNS1`, the upload and download sizes as big-endian 64-bit integers and
a big-endian 32-bit seed. It then uploads that many bytes of the stream for
the seed and closes its output. The server sends the download bytes of the
stream for the seed plus one, then a status byte, and closes. Status 0 means
the upload matched and ended there. The stream is xorshift32 started at
`seed * 0x9e3779b9 + 1`, one low byte per step, as in `netstack-peer/main.go`.

Klethron's `OracleInteropTest` is the client and the real check. Under
`./gradlew :klethron-tailnet:integrationTest`, it runs transfers over IPv4
and IPv6 with loss, duplication, reordering and delay. `test-netstack-peer.sh`
only checks that the peer starts and configures `kns0`.

When a push to `main` changes `Dockerfile.netstack-peer` or `netstack-peer/`,
GitHub Actions publishes
`ghcr.io/klethron-app/klethron-images/netstack-peer:r<IMAGE_REVISION>`.
Bump the revision with every such change. The job fails if the tag already
exists. Klethron pins the published tag and digest as `netstackKernelPeerImage`
in `gradle/libs.versions.toml`.

To build and check the image locally:

```sh
docker build -t netstack-peer:local -f Dockerfile.netstack-peer netstack-peer
bash test-netstack-peer.sh netstack-peer:local
```
