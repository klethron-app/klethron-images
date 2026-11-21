# klethron-images

Images used for testing.

## Rex

`Dockerfile.rex` pins the Rex version and image revision. On container start,
Rex runs as the `rex` user and listens on `/run/rex/server.sock`.

When a push to the default branch changes `Dockerfile.rex`, GitLab CI publishes
`ghcr.io/klethron-app/klethron-images/rex:<REX_VERSION>-r<IMAGE_REVISION>`.
Bump the revision when changing the image for the same Rex version. The job
fails if the tag already exists.

To enable publishing, connect this GitHub repository to GitLab CI and use a
runner configured for Docker-in-Docker with TLS and a shared `/certs/client`
volume. Set `GHCR_USERNAME` to the publishing GitHub user and store its classic
personal access token with `write:packages` as the masked `GHCR_TOKEN` CI/CD
variable.
