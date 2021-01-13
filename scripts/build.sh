#!/bin/bash
set -xeo pipefail

# `x86_64-osx` is also available, requires osxcross to be installed (see bwt/builder-osx.Dockerfile)
export TARGETS=${TARGETS:-x86_64-linux,x86_64-win,arm32v7-linux,arm64v8-linux}

[ -f bwt/Cargo.toml ] || (echo >&2 "Missing bwt submodule, run 'git submodule update --init'" && exit 1)

version=$(grep -E '^version =' bwt/Cargo.toml | cut -d'"' -f2)

# Copy the executables from BWT_BIN_DIST if specified,
# or build them if it was not
if [ -z "$BWT_BIN_DIST" ]; then
  (cd bwt && ELECTRUM_ONLY_ONLY=1 ./scripts/build.sh)
  BWT_BIN_DIST=bwt/dist
elif [ ! -d "$BWT_BIN_DIST" ]; then
  echo >&2 BWT_BIN_DIST is configured but missing
  exit 1
fi

build() {
  if [[ $TARGETS != *"$1"* ]]; then return; fi

  local platform=$1
  local name=bwt-electrum-plugin-$version-$platform
  local dest=dist/$name

  mkdir -p $dest
  cp $BWT_BIN_DIST/bwt-$version-electrum_only-$platform/* $dest
  cp src/*.py $dest
  cp LICENSE README.md $dest
  pack $name
}

# pack tar.gz (for linux/mac/arm) or zip (for windows)
pack() {
  name=$1; dir=${2:-$1}
  pushd dist
  touch -t 1711081658 $name $name/*
  if [[ $name == *"-linux" || $name == *"-arm"* ]]; then
	  # use static/removed metadata attrs and deterministic file order for reproducibility
    TZ=UTC tar --mtime='2017-11-08 16:58:00' --owner=0 --sort=name -I 'gzip --no-name' -chf $name.tar.gz $dir
  else
    find -H $dir | sort | xargs zip -X -q $name.zip
  fi
  popd
}

build x86_64-linux
build x86_64-osx
build x86_64-windows
build arm32v7-linux
build arm64v8-linux
