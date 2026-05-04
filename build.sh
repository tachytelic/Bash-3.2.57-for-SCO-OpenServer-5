#!/bin/sh
# Build GNU bash 3.2.57 natively on SCO OpenServer 5.0.7.
#
# Run this script ON the SCO machine, in a writable directory.
#
# Why 3.2.57 and not bash 4.x or 5.x? Bash 4.0+ has structural memory
# corruption on SCO 5 (verified across 4.0, 4.4, 5.2 — likely related
# to locale-aware code paths or thread-aware idioms in newer bash).
# 3.2.57 — the final 3.2 patchlevel, June 2014 — runs cleanly.
#
# Required:
#   GCC 3.4 or later (the SCO native 2.95.3 may also work, but we built
#       this with 3.4.6). Set CC and put it on PATH, or use GCC env var.
#   /usr/gnu/bin/{gmake,gtar}, /usr/bin/patch, bash (SCO ships an older
#       one — used as the configure shell because /bin/sh is too slow on
#       autoconf-generated configure scripts).
#   wget or curl to fetch the upstream source.
#
# Output: ./install/bin/bash — ~625 KB stripped binary.

set -e

SCRIPT_DIR=`cd \`dirname "$0"\` && pwd`
TARBALL=bash-3.2.tar.gz
SRCDIR=bash-3.2

if [ -n "$GCC" ]; then
    CC="$GCC"
fi
CC="${CC:-gcc}"
export CC

PATH=/usr/gnu/bin:/usr/ccs/bin:/usr/bin:/bin
export PATH

if [ ! -f "$TARBALL" ]; then
    echo "Fetching $TARBALL..."
    if which wget >/dev/null 2>&1; then
        wget --no-check-certificate "https://ftp.gnu.org/gnu/bash/${TARBALL}"
    elif which curl >/dev/null 2>&1; then
        curl -kLO "https://ftp.gnu.org/gnu/bash/${TARBALL}"
    else
        echo "ERROR: no wget or curl. Drop $TARBALL next to this script." >&2
        exit 1
    fi
fi

if [ ! -d "$SRCDIR" ]; then
    echo "Unpacking $TARBALL..."
    /usr/bin/gunzip -c "$TARBALL" | /usr/bin/tar xf -
fi

cd "$SRCDIR"

if [ -f .upstream_patched ]; then
    echo "Upstream patches already applied — skipping."
else
    echo "Applying 57 upstream bash-3.2 patches (gets us from 3.2 -> 3.2.57)..."
    /usr/bin/patch -p0 < "$SCRIPT_DIR/patches/bash-3.2-upstream-001-to-057.patch"
    touch .upstream_patched
fi

# Need bash for the configure script — SCO's /bin/sh (which is /bin/ksh)
# takes >10 minutes on the autoconf-generated configure here, vs ~30s
# under bash. The same "use real bash" trick we used for tar 1.34.
SHELL_BIN=`which bash 2>/dev/null`
if [ -z "$SHELL_BIN" ]; then
    echo "ERROR: bash required as configure shell." >&2
    exit 1
fi

echo "Configuring..."
FORCE_UNSAFE_CONFIGURE=1 CONFIG_SHELL=$SHELL_BIN $SHELL_BIN configure \
    --prefix="$SCRIPT_DIR/install" \
    --without-bash-malloc \
    CC="$CC" \
    CFLAGS="-O2"

# Configure adds `-b elf` to LOCAL_CFLAGS for SCO targets. With GCC 2.95
# that's an SCO-specific binary-format selector and works mid-line; with
# GCC 3.4+ it must come at the start of the command line, so it errors.
# Since modern GCC defaults to ELF on SCO anyway, just strip it.
echo "Removing -b elf from generated Makefiles..."
for f in Makefile builtins/Makefile examples/loadables/Makefile \
         lib/glob/Makefile lib/malloc/Makefile lib/readline/Makefile \
         lib/sh/Makefile lib/tilde/Makefile support/Makefile; do
    if [ -f "$f" ] && grep -q "b elf" "$f"; then
        sed "s/-b elf //g" "$f" > "$f.new" && mv "$f.new" "$f"
    fi
done

# SCO ships /usr/gnu/bin/bison 1.75, which is too old to regenerate
# bash 3.2.57's parse.y (the m4 templates fail). Use the y.tab.c/.h
# we pre-generated with modern bison (3.x). Touching them after
# parse.y prevents make from trying to regenerate.
if [ -f "$SCRIPT_DIR/patches/y.tab.c" ] && [ -f "$SCRIPT_DIR/patches/y.tab.h" ]; then
    echo "Installing pre-generated y.tab.c (bison 1.75 on SCO can't handle bash 3.2's parse.y)..."
    cp "$SCRIPT_DIR/patches/y.tab.c" "$SCRIPT_DIR/patches/y.tab.h" .
    touch parser-built y.tab.c y.tab.h
fi

echo "Compiling..."
gmake

echo "Installing to $SCRIPT_DIR/install/..."
gmake install

echo "Stripping..."
strip "$SCRIPT_DIR/install/bin/bash" 2>/dev/null || true

ls -l "$SCRIPT_DIR/install/bin/bash"
echo
echo "Test it:"
echo "  $SCRIPT_DIR/install/bin/bash --version"
echo "  $SCRIPT_DIR/install/bin/bash -c 'echo a; echo b'   # should print a then b"
echo
echo "To package: gtar czf bash-3.2.57-sco.tar.gz install"
