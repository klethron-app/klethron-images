# klethron-images

Images used for testing.

## Rex

`Dockerfile.rex` pins the Rex version and image revision. On container start,
Rex runs as the `rex` user and listens on `/run/rex/server.sock`.

When a push to `main` changes `Dockerfile.rex`, GitHub Actions publishes
`ghcr.io/klethron-app/klethron-images/rex:<REX_VERSION>-r<IMAGE_REVISION>`.
Bump the revision when changing the image for the same Rex version. The job
fails if the tag already exists.

The workflow authenticates to GHCR with the repository’s built-in
`GITHUB_TOKEN` and the `packages: write` permission.
