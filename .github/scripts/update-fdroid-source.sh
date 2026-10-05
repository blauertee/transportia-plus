#!/usr/bin/env bash
# Point blauertee/fdroid at this release by rewriting its source file.
# Pushes over SSH with the FDROID_DEPLOY_KEY deploy key: a push made with
# GITHUB_TOKEN would not start fdroid's Publish workflow.
# Usage: update-fdroid-source.sh <tag> <commit> <apk>...
set -euo pipefail

tag=$1
commit=$2
shift 2
source_file=sources/io.github.blauertee.transportia.yml

if [[ -z "${FDROID_DEPLOY_KEY:-}" ]]; then
  echo "::error::secret FDROID_DEPLOY_KEY is not set; the F-Droid repo was not updated" >&2
  exit 1
fi

ssh_dir=$(mktemp -d)
trap 'rm -rf "$ssh_dir"' EXIT
printf '%s\n' "$FDROID_DEPLOY_KEY" > "$ssh_dir/key"
chmod 600 "$ssh_dir/key"
# GitHub's published host key, pinned rather than trusted on first use.
echo "github.com ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOMqqnkVzrm0SdG6UOoqKLsabgH5C9okWi0dh2l9GKJl" \
  > "$ssh_dir/known_hosts"
export GIT_SSH_COMMAND="ssh -i $ssh_dir/key -o IdentitiesOnly=yes -o UserKnownHostsFile=$ssh_dir/known_hosts -o StrictHostKeyChecking=yes"

repo=$ssh_dir/fdroid
git clone --quiet --branch main git@github.com:blauertee/fdroid.git "$repo"

{
  echo "# Written by blauertee/transportia's nightly workflow. Do not edit by hand."
  echo "repo: blauertee/transportia"
  echo "tag: \"$tag\""
  echo "commit: \"$commit\""
  echo "apks:"
  for apk in "$@"; do
    echo "  - name: \"$(basename "$apk")\""
    echo "    sha256: \"$(sha256sum "$apk" | cut -d' ' -f1)\""
  done
} > "$repo/$source_file"

cd "$repo"
git config user.name "transportia nightly"
git config user.email "41898282+github-actions[bot]@users.noreply.github.com"
git add "$source_file"
if git diff --cached --quiet; then
  echo "F-Droid source already points at $tag"
  exit 0
fi
git commit --quiet -m "Transportia+ $tag"
# Another app's source may land on main in between; rebase and retry.
for attempt in 1 2 3; do
  git push --quiet origin HEAD:main && exit 0
  echo "push attempt $attempt failed; rebasing on the latest main" >&2
  git pull --quiet --rebase origin main
done
echo "::error::could not push to blauertee/fdroid" >&2
exit 1
