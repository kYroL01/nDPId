#!/usr/bin/env bash

set -e

GIT_EXEC="$(command -v git || printf '%s' "")"
WGET_EXEC="$(command -v wget || printf '%s' "")"
UNZIP_EXEC="$(command -v unzip || printf '%s' "")"
MAKE_EXEC="$(command -v make || printf '%s' "")"

GITHUB_FALLBACK_URL='https://github.com/ntop/nDPI/archive/refs/heads/dev.zip'

if [ -z "${GIT_EXEC}" -o -z "${WGET_EXEC}" -o -z "${UNZIP_EXEC}" -o -z "${MAKE_EXEC}" ]; then
    printf '%s\n' "Required Executables missing: git, wget, unzip, make" >&2
    exit 1
fi

LOCKFILE="$(realpath "${0}").lock"
touch "${LOCKFILE}"
exec 42< "${LOCKFILE}"
flock -x -n 42 || {
    printf '%s\n' "Could not aquire file lock for ${0}. Already running instance?" >&2;
    exit 1;
}

if [ ! -z "${CC}" ]; then
    HOST_TRIPLET="$(${CC} ${CFLAGS} -dumpmachine)"
fi

cat <<EOF
------ environment variables ------
HOST_TRIPLET=${HOST_TRIPLET}
CC=${CC:-}
CXX=${CXX:-}
AR=${AR:-}
RANLIB=${RANLIB:-}
PKG_CONFIG=${PKG_CONFIG:-}
CFLAGS=${CFLAGS:-}
LDFLAGS=${LDFLAGS:-}
ADDITIONAL_ARGS=${ADDITIONAL_ARGS:-}
MAKE_PROGRAM=${MAKE_PROGRAM:-}
DEST_INSTALL=${DEST_INSTALL:-}
-----------------------------------
EOF

set -x

cd "$(dirname "${0}")/.."

GIT_SUCCESS=0
if [ -d ./.git -o -f ./.git ]; then
    GIT_SUCCESS=1
    LINES_CHANGED="$(git --no-pager diff ./libnDPI 2>/dev/null | wc -l || printf '0')"
    if [ ${LINES_CHANGED} -eq 0 ]; then
        git submodule update --progress --init ./libnDPI || { GIT_SUCCESS=0; true; }
    else
        set +x
        printf '%s\n' '-----------------------------------'
        printf 'WARNING: %s changes in source tree %s, no GIT update will be done!\n' "${LINES_CHANGED}" "$(realpath $(dirname "${0}")/../libnDPI)"
        printf '%s\n' '-----------------------------------'
        set -x
    fi
fi

if [ ${GIT_SUCCESS} -eq 0 ]; then
    set +x
    printf '%s\n' '-----------------------------------'
    printf 'WARNING: %s is supposed to be a GIT repository. But it is not.\n' "$(realpath $(dirname "${0}")/..)"
    printf '%s\n' 'Can not clone libnDPI as GIT submodule.'
    printf '%s\n' 'Falling back to Github direct download.'
    printf 'URL: %s\n' "${GITHUB_FALLBACK_URL}"
    printf '%s\n' '-----------------------------------'
    set -x
    wget "${GITHUB_FALLBACK_URL}" -O ./libnDPI-github-dev.zip
    unzip ./libnDPI-github-dev.zip
    rm -rf ./libnDPI
    mv ./nDPI-dev ./libnDPI
fi

cd ./libnDPI
test ! -r Makefile || { make distclean || true; }
DEST_INSTALL="${DEST_INSTALL:-$(realpath ./install)}"
MAKE_PROGRAM="${MAKE_PROGRAM:-make -j4}"
HOST_ARG="--host=${HOST_TRIPLET}"
./autogen.sh --enable-option-checking=fatal \
    --prefix="/" \
    --with-only-libndpi ${HOST_ARG} ${ADDITIONAL_ARGS}
${MAKE_PROGRAM} install DESTDIR="${DEST_INSTALL}"

rm -f "${LOCKFILE}"
