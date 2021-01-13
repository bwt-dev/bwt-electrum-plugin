#!/bin/bash
set -xeo pipefail
shopt -s expand_aliases

gh_repo=bwt-dev/bwt-electrum-plugin

git diff-index --quiet HEAD || (echo >&2 git working directory is dirty && exit 1)

[ -n "$BWT_BASE" ] || (echo >&2 BWT_BASE is required && exit 1)
[ -n "$BWT_COMMIT" ] || (echo >&2 BWT_COMMIT is required && exit 1)

export TARGETS=${TARGETS:-x86_64-linux,x86_64-osx,x86_64-windows,arm32v7-linux,arm64v8-linux}

(cd bwt && git fetch local && git reset --hard $BWT_COMMIT)

version=$(grep -E '^version =' bwt/Cargo.toml | cut -d'"' -f2)

echo -e "Releasing bwt-electrum-plugin v$version\n"

# Prepare unreleased changelog
changelog=$(sed -nr '/^## (Unreleased|'$version' )/{n;:a;n;/^## /q;p;ba}' CHANGELOG.md)
changelog="- Update to [bwt v$version](https://github.com/bwt-dev/bwt/releases/tag/v$version)"$'\n'$changelog
grep '## Unreleased' CHANGELOG.md > /dev/null \
  && sed -i "s/^## Unreleased/## $version - $(date +%Y-%m-%d)/" CHANGELOG.md

# Update version number in README
sed -i -r "s~bwt-electrum-plugin-[0-9a-z.-]+-x86_64-linux\.~bwt-electrum-plugin-$version-x86_64-linux.~g; s~/(download|tag)/v[0-9a-z.-]+~/\1/v$version~;" README.md

# Build
if [ -z "$SKIP_BUILD" ]; then
  echo Building...
  rm -rf dist/*

  BWT_BIN_DIST=$BWT_BASE/bwt/dist \
  ./scripts/build.sh

  rm -rf dist/*/ # remove subdirectories, keep files only
fi

# Sign
(cd dist && sha256sum *) | sort | gpg --clearsign --digest-algo sha256 > SHA256SUMS.asc

# Git tag and push
if [ -z "$SKIP_GIT" ]; then
  git add {CHANGELOG,README}.md SHA256SUMS.asc bwt
  git commit -S -m v$version
  git tag --sign -m "$changelog" v$version
  git branch -f latest HEAD
  git push gh master latest
  git push gh --tags
fi

# Upload distribution files to GitHub releases
if [[ -z "$SKIP_UPLOAD" && -n "$GH_TOKEN" ]]; then
  echo Uploading to github...
  gh_auth="Authorization: token $GH_TOKEN"
  gh_base=https://api.github.com/repos/$gh_repo

  sleep 3 # allow some time for the job to show up on travis
  travis_job=$(curl -s "https://api.travis-ci.org/v3/repo/${gh_repo/\//%2F}/branch/v$version" | jq -r '.last_build.id // ""')

  release_text="### Changelog"$'\n'$'\n'$changelog$'\n'$'\n'$(sed "s/VERSION/$version/g; s/TRAVIS_JOB/$travis_job/g;" scripts/release-footer.md)
  release_opt=$(jq -n --arg version v$version --arg text "$release_text" \
    '{ tag_name: $version, name: $version, body: $text, draft:true }')
  gh_release=$(curl -sf -H "$gh_auth" $gh_base/releases/tags/v$version \
           || curl -sf -H "$gh_auth" -d "$release_opt" $gh_base/releases)
  gh_upload=$(echo "$gh_release" | jq -r .upload_url | sed -e 's/{?name,label}//')

  for file in SHA256SUMS.asc dist/*; do
    echo ">> Uploading $file"

    curl -f --progress-bar -H "$gh_auth" -H "Content-Type: application/octet-stream" \
         --data-binary @"$file" "$gh_upload?name=$(basename "$file")" | (grep -v browser_download_url || true)
  done

  # mark release as public once everything is ready
  curl -sf -H "$gh_auth" -X PATCH "$gh_base/releases/$(echo "$gh_release" | jq -r .id)" \
    -d '{"draft":false}' > /dev/null
fi
