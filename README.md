# rancher-mirror

Public mirror of the RKE2 and Rancher container images used by Alfame-managed
downstream clusters, republished under `ghcr.io/alfamecom/mirror/*`.

## Why

Some managed on-premise clusters sit behind firewalls that allow a narrow list of
egress destinations. Container registries make this harder than it looks: the
registry host serves manifests, but blob downloads are handed off to a separate
CDN host, which must be allowed too.

| Registry | Blob host | Blob host addresses |
| --- | --- | --- |
| `docker.io` | `production.cloudfront.docker.com` | AWS CloudFront — large, rotating |
| `registry.rancher.com` | `registry-storage.suse.com` | Akamai — varies by location |
| `ghcr.io` | `pkg-containers.githubusercontent.com` | four static addresses |

Mirroring to `ghcr.io` means those clusters can pull RKE2 and Rancher images
over a path that is already reachable, without new firewall rules.

## Using the mirror

Point a downstream cluster at the mirror through the Rancher cluster spec
(`spec.rkeConfig.registries`), which is written to `registries.yaml` on each node:

```yaml
mirrors:
  docker.io:
    endpoint:
      - "https://ghcr.io"
    rewrite:
      "^rancher/(.*)": "alfamecom/mirror/rancher/$1"
```

Note that `endpoint` redirects **all** `docker.io` pulls to `ghcr.io`; `rewrite`
only renames the ones that match. Any `rancher/*` image not present in
[`images.txt`](images.txt) will fail to pull, so keep the list complete for every
RKE2 version in use.

`system-default-registry` is not an alternative here: it would resolve to
`ghcr.io/rancher/*`, a namespace we do not control.

## Running a mirror pass

Via GitHub Actions — **Actions → Mirror images → Run workflow**. An optional
filter mirrors a single image, which is useful for testing:

```
filter: system-agent-installer-rke2
```

Or locally, with [crane](https://github.com/google/go-containerregistry) and a
token that has `write:packages`:

```sh
gh auth token | crane auth login ghcr.io -u "$USER" --password-stdin
./mirror.sh                     # everything
./mirror.sh hardened-kubernetes # one image
```

Passes are idempotent: images whose digest already matches upstream are skipped.

## Adding a new RKE2 version

```sh
curl -sL "https://github.com/rancher/rke2/releases/download/v1.28.9%2Brke2r1/rke2-images-all.linux-amd64.txt" \
  | sed 's|^docker.io/||' >> images.txt
sort -u -o images.txt images.txt
```

Rancher-side images (`rancher-agent`, `fleet-agent`, `shell`, `rancher-webhook`,
`system-upgrade-controller`, `system-agent`, `kubectl`) are not in the RKE2 release
lists and are maintained by hand. Add them **before** upgrading Rancher: right after
the upgrade, Rancher redeploys its agents in every downstream cluster, and a cluster
that cannot pull the new `rancher-agent` loses its connection to Rancher.

For a Rancher version, the images are in that release's `rancher-images.txt`:

```sh
v=v2.10.3
curl -sL "https://github.com/rancher/rancher/releases/download/$v/rancher-images.txt" \
  | grep -E '^rancher/(rancher-agent|fleet-agent|rancher-webhook|shell|system-agent):'
```

`rancher-images.txt` lists several `shell` and `kubectl` tags. Take the `shell` tag
from `defaultShellVersion` in that release's `build.yaml`. Take the
`system-upgrade-controller` and `kubectl` tags from the `values.yaml` of the
`system-upgrade-controller` chart that Rancher installs
(`CATTLE_SYSTEM_UPGRADE_CONTROLLER_CHART_VERSION` in `package/Dockerfile`).

## Source and integrity

Images are copied from `registry.rancher.com`, which allows anonymous pulls and
imposes no rate limit, unlike anonymous Docker Hub access. `crane copy`
reproduces the manifest as-is, so mirrored images keep the upstream digest and
all platforms. Verify any image with:

```sh
crane digest registry.rancher.com/rancher/hardened-kubernetes:v1.27.16-rke2r2-build20240819
crane digest ghcr.io/alfamecom/mirror/rancher/hardened-kubernetes:v1.27.16-rke2r2-build20240819
```

## Package visibility

Packages must be **created** public — GitHub has no API for changing the
visibility of an existing package, and doing it by hand does not scale to a list
this size. Publishing from this repository's workflow links each package to this
public repository, and with *Inherit access from source repository* enabled at
the organisation level, the package inherits public visibility on creation.

A package that was first published some other way, and ended up private, has to
be deleted and republished through the workflow.

Packages already published from an earlier repository stay linked to it, and this
repository's `GITHUB_TOKEN` cannot write to them: a mirror pass that has to update
one of them fails with `denied`. Grant access per package under *Package settings →
Manage Actions access → Add repository* (role *Write*). Passes that only skip
images that are already mirrored, or that create new packages, are not affected.
