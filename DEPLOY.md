# Deploying a new release of inhibit-charge

Releases are triggered by **pushing a tag** of the form `vX.Y.Z`. CI does the rest: builds the .deb, attaches it to a GitHub Release, and auto-publishes it to the [ra-yavuz apt repository](https://github.com/ra-yavuz/apt). No manual download or commit step.

## Pre-flight checklist

1. **Bump the version**:
   - `debian/changelog` &rarr; new entry `inhibit-charge (X.Y.Z-1) unstable; urgency=low` with notes
2. **Verify lint passes locally**:
   ```bash
   make lint
   ```

## Ship it

```bash
git add -A
git commit -m "vX.Y.Z: <one-line summary>"
git push
git tag -a vX.Y.Z -m "vX.Y.Z: <one-line summary>"
git push origin vX.Y.Z
```

CI takes ~3 minutes:

- **lint** + **build-deb** &rarr; produces `dist/inhibit-charge_X.Y.Z-1_all.deb`
- **release** (tag-only) &rarr; creates the GitHub Release, attaches the .deb, dispatches `package-published` to `ra-yavuz/apt`
- The apt repo's **add-package** workflow downloads, places, evicts older version, commits, pushes
- The push triggers **publish** which rebuilds the apt index

Within ~5 min total, `sudo apt update && sudo apt install inhibit-charge` serves the new version.

## What if the tag run fails?

Watch CI at https://github.com/ra-yavuz/inhibit-charge/actions. Common causes:

- **shellcheck errors**: re-run `make lint` and fix.
- **release upload `403 Resource not accessible`**: the `release` job needs `permissions: contents: write` (already set).
- **apt dispatch silently skipped**: the step requires the `APT_DISPATCH_TOKEN` secret to exist on this repo. Check `Settings &rarr; Secrets and variables &rarr; Actions`.

To retry after a fix: delete and re-push the tag.

```bash
git tag -d vX.Y.Z
git push origin :refs/tags/vX.Y.Z
# fix the issue, commit, push, retag
git tag -a vX.Y.Z -m "vX.Y.Z: ..."
git push origin vX.Y.Z
```

## What gets published

| Surface | URL | Updated by |
|---|---|---|
| GitHub Release | `https://github.com/ra-yavuz/inhibit-charge/releases/tag/vX.Y.Z` | `release` job |
| .deb in apt repo | `https://ra-yavuz.github.io/apt/pool/main/i/inhibit-charge/` | `add-package` &rarr; `publish` |
| Apt index | `https://ra-yavuz.github.io/apt/dists/stable/main/binary-amd64/Packages` | `publish` |
| Project Pages | `https://ra-yavuz.github.io/inhibit-charge/` | redeploys on any push to `main` |

## Same flow lives in herald, hydra-llm, meowtrics

The four packaged repos share the same CI shape (`lint &rarr; build-deb &rarr; release`) and the same dispatch pattern.
