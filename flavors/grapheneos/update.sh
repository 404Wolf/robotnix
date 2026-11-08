#!/usr/bin/env bash

set -e
set -o pipefail

repo-tool get-graphene-devices -c stable -c beta -c alpha devices.json channel_info.json
tags=$(jq -r .git_tags[] channel_info.json | sort -r)

# Number of repos prefetched concurrently (a new Android release changes
# ~1100 of them; one at a time that takes hours).
jobs=${JOBS:-8}

echo "Tags to fetch: $tags"
for tag in $tags; do
  mkdir -p "$tag"
  if [ ! -e "$tag/repo.lock" ]; then
    echo "No lockfile for $tag yet."
    # Seed from the newest lockfile we have, so repos unchanged since then
    # are reused instead of prefetched again. (The latest tag usually has
    # no lockfile yet when it's new.)
    seed=$(find . -mindepth 2 -maxdepth 2 -name repo.lock | sort -r | head -n 1)
    if [ -n "$seed" ]; then
      echo "Copying from $seed."
      cp "$seed" "$tag/repo.lock"
    fi
  fi
  echo "Fetching lockfile for tag $tag."
  repo-tool fetch --tag -j "$jobs" -r "$tag" https://github.com/GrapheneOS/platform_manifest "$tag/repo.lock"
  lockfiles="$lockfiles $tag/repo.lock"
done

echo "Extracting build IDs..."
# shellcheck disable=2086
repo-tool get-build-id build_ids.json $lockfiles

echo "Deleting unused lockfiles..."
for lockfile in */repo.lock; do
  present=0
  for tag in $tags; do
    if [ "$tag/repo.lock" = "$lockfile" ]; then
      present=1
    fi
  done
  if [ $present -eq 0 ]; then
    echo "Deleting $lockfile..."
    rm -r "$(dirname "$lockfile")"
  fi
done

echo "Prefetching yarn deps for vendor/adevtool..."
echo "{" >yarn_hashes.json.part
first=1
for tag in $tags; do
  if [ $first -eq 1 ]; then
    first=0
  else
    echo "," >>yarn_hashes.json.part
  fi
  adevtool_path=$(jq -r '.entries.["vendor/adevtool"].lock.path' "$tag/repo.lock")
  echo "Ensuring that $adevtool_path is present in the Nix store..."
  repo-tool ensure-store-paths "$tag/repo.lock" "vendor/adevtool"
  echo "$tag: Prefetching yarn deps in $adevtool_path/yarn.lock"
  hash=$(prefetch-yarn-deps "$adevtool_path/yarn.lock")
  printf ' "%s": "%s"' "$tag" "$hash" >>yarn_hashes.json.part
done
echo >>yarn_hashes.json.part
echo "}" >>yarn_hashes.json.part
mv yarn_hashes.json.part yarn_hashes.json

for tag in $tags; do
  mkdir -p "$tag/vendor_imgs/"
  nix build --impure --expr "import ./adevtool-show-metadata-json.nix \"$tag\"" --out-link result-adevtool
  devices=$(jq -r ".[]" devices.json)
  orig_dir=$(pwd)
  cd result-adevtool
  for device in $devices; do
    found=0
    for channel in stable beta alpha; do
      if [ "$tag" = "$(jq -r ".device_info.$channel.$device.git_tag" "$orig_dir/channel_info.json")" ]; then
        found=1
        break
      fi
    done
    if [ $found -eq 1 ]; then
      echo "Extracting vendor image metadata for $tag $device..."
      vendor/adevtool/bin/run generate-all -d "$device" >"$orig_dir/$tag/vendor_imgs/$device.json"
    fi
  done
  cd "$orig_dir"
done
