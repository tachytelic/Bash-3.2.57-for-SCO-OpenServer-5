# GNU bash 3.2.57 for SCO OpenServer 5

A working build of [GNU bash 3.2.57](https://www.gnu.org/software/bash/)
(June 2014, the final 3.2 patchlevel) for **SCO OpenServer 5.0.7**.

```
$ bash --version
GNU bash, version 3.2.57(3)-release (i686-pc-sco3.2v5.0.7)

$ bash -c 'echo a; echo b'
a
b
```

(The second line matters — see "Why 3.2.57 and not bash 4 or 5" below.)

## Install

> **Fresh SCO box?** Install [curl with TLS](https://github.com/tachytelic/curl-7.88.1-for-SCO-OpenServer-5)
> first — that's the only file that needs to be transferred via `scp`.
> After that, every release on tachytelic/* (including this one) fetches
> over HTTPS from GitHub.

The release tarball is ~550 KB. Fetch and extract on the SCO box:

```sh
# On the SCO box (assumes curl-with-TLS is on PATH — see curl-sco):
curl -LO https://github.com/tachytelic/Bash-3.2.57-for-SCO-OpenServer-5/releases/download/v1.0.0/bash-3.2.57-sco.tar.gz
gtar xzf bash-3.2.57-sco.tar.gz
# or with stock tools: gunzip -c bash-3.2.57-sco.tar.gz | /usr/bin/tar xf -
mv install /usr/local/bash-3.2.57
ln -s /usr/local/bash-3.2.57/bin/bash /usr/local/bin/bash
bash --version
```

If you want this to be the default `/bin/sh` for shell scripts (it isn't
by default — SCO's `/bin/sh` is symlinked to `/bin/ksh`), keep them
separate. Most autoconf-generated `configure` scripts run dramatically
faster under bash than under SCO's ksh — minutes instead of tens of
minutes — so this build is *very* useful even if you never use it as
your interactive shell.

## Why 3.2.57 and not bash 4 or 5?

Bash 4.0+ has structural memory corruption on SCO 5. Verified across
4.0, 4.4, and 5.2 — same symptom on all three: `bash -c 'echo a; echo b'`
prints `a\na\n<30+ KB heap dump>` instead of `a\nb\n`. Same bug on three
major versions over fifteen years means it's not a version-specific
regression — something structural in bash 4+ doesn't get along with
SCO's runtime. Suspected culprits include locale-aware code paths
(SCO's locale is essentially unconfigured) and threading-aware code
SCO can't satisfy. A real fix would need a debugger session inside the
broken binary; nobody's done it.

**3.2.57 is the highest version that demonstrably works.** It's an old
shell — June 2014, 3.2 line started in 2006 — but it has all the
modern bashisms you actually use day to day:

- Arrays (`arr=(a b c); echo ${arr[1]}`)
- Indirect parameter expansion (`${!var}`)
- Process substitution (`<(cmd)`, `>(cmd)`)
- `[[ ... ]]` conditional expressions, `=~` regex matching
- `${var/pattern/replacement}` substitution
- `extglob` (extended globbing)
- ANSI-C quoting (`$'\n'`)
- Functions, local variables, `return`, `set -e`/`-u`/`-o pipefail`

What it *doesn't* have (added in bash 4.0+):

- `mapfile` / `readarray` (4.0)
- Associative arrays — `declare -A` (4.0)
- `&>` and `|&` redirection shortcuts (4.0)
- Negative subscripts on arrays (4.2)
- `${var^^}` / `${var,,}` case conversion (4.0)
- `printf -v` to a variable (4.1)
- `globstar` (`**`) (4.0)
- `coproc` (4.0)

If your scripts need any of those, you can't have them on SCO 5
(structural blocker, not a build failure we can patch around). If they
don't, 3.2.57 is functionally indistinguishable for ~95% of shell
scripts written today.

## What works

End-to-end smoke-tested on a SCO 5.0.7 install:

| Test | Result |
|---|---|
| `echo a; echo b` (the bash 4+ bug) | ✅ correct output |
| Arithmetic: `$((x*y))` | ✅ |
| Functions, parameters, return | ✅ |
| Arrays: `arr=(a b c); ${arr[i]}; ${#arr[@]}` | ✅ |
| Substitution: `${var/pat/repl}` | ✅ |
| `[[ str =~ regex ]]` | ✅ |
| `[ -e file ]` test | ✅ |
| Pipes, redirections, command substitution | ✅ |
| Job control | not tested, but the build enables it |

## Building from source

You probably don't need to do this — the release tarball is what
`build.sh` produces. If you want to rebuild:

This is a **native build** on SCO. The same pattern as the python/curl/lua
builds in this repo's siblings.

### Requirements

- **GCC 3.4 or later** somewhere on PATH (or set `GCC=`/`CC=`). The
  SCO-shipped GCC 2.95.3 may also work; we built with 3.4.6.
- `/usr/gnu/bin/{gmake,gtar}`, `/usr/bin/patch`
- **bash** as the configure shell. Yes, you need bash to build bash —
  SCO ships bash 3.1.x at `/usr/bin/bash`, which is fine. The reason
  isn't a circular bootstrap; it's that SCO's `/bin/sh` (linked to
  `/bin/ksh`) is so slow on autoconf-generated configure scripts that
  it appears to hang for 10+ minutes. bash runs the same configure in
  ~30 seconds.

### Build

```sh
cd bash-sco
./build.sh
```

Or with a non-default GCC:

```sh
GCC=/path/to/gcc-3.4 ./build.sh
```

`build.sh` does the following:

1. Fetches `bash-3.2.tar.gz` from gnu.org if not already present.
2. Extracts and applies the **57 upstream bash-3.2 patches** (bundled
   into `patches/bash-3.2-upstream-001-to-057.patch` — official FSF
   patches, redistributed under bash's GPLv3+) to get to PATCHLEVEL 57.
3. Runs `configure` under bash, with `FORCE_UNSAFE_CONFIGURE=1` (bash's
   configure refuses to run as root by default, which is fine for SCO
   sysadmins).
4. Strips `-b elf` from all generated `Makefile`s. Bash's configure
   detects SCO and adds this to `LOCAL_CFLAGS`; with GCC 2.95 it's an
   SCO-specific flag that works mid-command, but with GCC 3.4+ it has
   to come at the very start of the command line. Since GCC 3.4+
   defaults to ELF on SCO anyway, removing the flag is the cleanest
   fix.
5. Copies the **pre-generated `y.tab.c` / `y.tab.h`** (in `patches/`)
   into the source tree. SCO ships `bison` 1.75, which is too old
   to handle bash 3.2.57's `parse.y` (the m4 templates fail). The
   `y.tab.c` we ship was regenerated from the patched `parse.y` using
   `bison` 3.8.2 on Ubuntu and is byte-equivalent to what an
   appropriately-recent bison would produce on SCO.
6. Builds with `gmake`, installs to `./install/`, strips.

### Why no `bash-3.2.57-sco.patch`?

There aren't any *source* patches for SCO compatibility — the upstream
3.2.57 source builds clean once `-b elf` is out of the Makefile and the
parser is regenerated. The two SCO-specific changes are both
build-system level, applied by `build.sh` rather than by patching
source files. Listing here for clarity:

1. **`-b elf` removal** — sed across generated Makefiles, post-configure.
2. **`y.tab.c` regenerated externally** — copied from `patches/`,
   so the SCO build never invokes the local (too-old) bison.

## Repository layout

```
patches/
  bash-3.2-upstream-001-to-057.patch    Official FSF bash-3.2 patches
                                        001 through 057, concatenated
  y.tab.c                               Pre-generated parser (bison 3.8)
  y.tab.h                               Parser header

build.sh                                Native-build script (run on SCO)
LICENSE                                 MIT (covers build script + patch
                                        bundle's *concatenation*; the
                                        bash patches themselves are GPLv3)
README.md                               This file
```

The prebuilt 550 KB tarball ships via the
**[Releases](../../releases)** page, not via clone bloat.

## License

GNU bash is © Free Software Foundation, distributed under
[GPLv3+](https://www.gnu.org/licenses/gpl-3.0.html). The prebuilt
binary is unmodified upstream bash 3.2.57 (3.2 + the 57 official
upstream patches). The `y.tab.c` shipped here is regenerated from
the patched `parse.y` and inherits bash's GPLv3+.

The build script in this repo is released under the MIT license — see
[LICENSE](LICENSE).

## See also

- [curl-7.88.1 for SCO](https://github.com/tachytelic/curl-7.88.1-for-SCO-OpenServer-5)
  — the natural first install on a fresh SCO box.
- [GNU tar 1.34 for SCO](https://github.com/tachytelic/Tar-1.34-for-SCO-OpenServer-5)
  — `gtar xzf` for one-step extraction of these releases.
- [Python 3.6.15 for SCO](https://github.com/tachytelic/Python-3.6.15-for-SCO-OpenServer-5),
  [Lua 5.4.7 for SCO](https://github.com/tachytelic/Lua-5.4.7-for-SCO-OpenServer-5),
  [rsync 3.2.7 for SCO](https://github.com/tachytelic/rsync-3.2.7-for-SCO-OpenServer-5)
  — sibling builds.
- [More SCO OpenServer 5 binaries](https://tachytelic.net/2017/07/sco-openserver-5-binaries/)
  — the hub.
