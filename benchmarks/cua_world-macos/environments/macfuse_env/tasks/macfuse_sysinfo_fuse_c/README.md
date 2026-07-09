# `macfuse_sysinfo_fuse_c` — Write a Read-Only macFUSE Filesystem in C

Environment: `macfuse_env@0.1` (macOS, use.computer dev fleet)

## Domain context

macFUSE (formerly OSXFUSE) is the FUSE filesystem framework for macOS — the
userspace-kernel bridge that lets a developer expose anything as a filesystem
without writing a kernel extension. The classic developer hobby project on
macFUSE is a *sysinfo filesystem*: a virtual mount where each "file" exposes
one fact about the running machine. `cat /Volumes/SysInfo/cpu.txt` prints the
CPU model; `cat /Volumes/SysInfo/memory.txt` prints physical RAM; and so on.

This is a personal-use FUSE project — a developer who wants a tidy filesystem
view of `sysctl` output, indistinguishable from any other read-only FUSE demo
that ships in the macFUSE wiki examples folder.

The kext on the use.computer Apple Silicon sandbox cannot actually *load*
(SIP + Reduced-Security gate), so the filesystem cannot be mounted live. But
the C source and Makefile can be authored and **compiled** against the live
macFUSE headers and libraries that ship at `/usr/local/include/fuse/fuse.h`
and `/usr/local/lib/libfuse.dylib`. Compilation success is the strongest
signal short of an end-to-end mount that the agent's code is genuinely valid
macFUSE C.

## Goal

Author a complete, compilable macFUSE userspace filesystem in C, plus a
Makefile that drives `clang` with the right preprocessor / link flags, and
attempt to compile it. The filesystem must expose at least four virtual
files — `cpu.txt`, `memory.txt`, `uptime.txt`, `hostname.txt` — populated
from live macOS data via the `sysctl(3)` family.

Project layout the agent must produce:

```
~/Documents/sysinfo_fuse/
├── sysinfo.c        # full FUSE_USE_VERSION=26 userspace filesystem in C
├── Makefile         # CC=clang, pkg-config fuse, FUSE_USE_VERSION=26
└── sysinfo_fuse     # (optional bonus) compiled binary, if `make` succeeded
```

## Why this is very_hard

Difficulty rating: `very_hard`.

The task description states the *goal* (a FUSE filesystem exposing four named
virtual files via sysctl) but does NOT walk through the C API. The agent must
discover, from its training and from the macFUSE headers on disk:

- Which FUSE callbacks are mandatory for a read-only filesystem
  (`getattr`, `readdir`, `open`, `read`), and the v26 signatures of each
- How to dispatch by path inside the callbacks (typical `if (strcmp(...))`
  branches against `"/"`, `"/cpu.txt"`, etc.)
- Which macOS `sysctl` MIBs / sysctlbyname names give CPU model
  (`machdep.cpu.brand_string` or `hw.model`), physical RAM (`hw.memsize`),
  hostname (`kern.hostname`), and boot time (`kern.boottime` → uptime by
  subtracting from `time(NULL)`)
- How to wire `fuse_main(argc, argv, &ops, NULL)` with a properly populated
  `struct fuse_operations`
- The exact compiler invocation: `-D_FILE_OFFSET_BITS=64`,
  `-DFUSE_USE_VERSION=26`, and the `pkg-config --cflags fuse` /
  `pkg-config --libs fuse` flags so the build picks up the macFUSE-shipped
  `fuse.h` and links against `libfuse.dylib`.

None of these are spelled out in the description. The agent has to know FUSE
v26 well enough to write a working filesystem from scratch.

## Scoring (100 pts, pass at 70)

| Criterion | Pts | Notes |
|---|---:|---|
| C1 Project directory `~/Documents/sysinfo_fuse/` exists | 5 | binary |
| C2 `sysinfo.c` exists and is non-empty (> 200 bytes) | 10 | binary |
| C3 `sysinfo.c` defines `FUSE_USE_VERSION` *before* the `fuse.h` include | 15 | binary; ordering matters because the macro gates the API version selected from `fuse_common.h` |
| C4 `sysinfo.c` includes `fuse.h` | 10 | binary; accepts `<fuse.h>` or `"fuse.h"` or `<fuse/fuse.h>` |
| C5 `sysinfo.c` defines all 4 mandatory callbacks (`getattr`, `readdir`, `open`, `read`) as functions | 20 | scored per-callback at 5 pts each — see Anti-Pattern 4 check below |
| C6 `sysinfo.c` calls `sysctl` or `sysctlbyname` at least twice | 15 | binary; ≥2 calls anywhere in the source |
| C7 All 4 required virtual filenames appear as string literals in the source (`cpu.txt`, `memory.txt`, `uptime.txt`, `hostname.txt`) | 10 | scored per-filename at 2.5 pts each, rounded |
| C8 `Makefile` exists with `FUSE_USE_VERSION=26` define and `pkg-config` usage for fuse | 10 | scored 5 + 5 (define present; pkg-config invocation present) |
| C9 Compiled binary `sysinfo_fuse` exists (compilation succeeded) | 5 | bonus — strong signal but only 5 pts so a refused-to-compile-environment is not catastrophic |
| **Total** | **100** | pass at 70 |

### Anti-Pattern 4 (partial credit ceiling) check

Each individual criterion is binary (full or zero) except C5 (4×5 pts) and
C7 (4×2.5 pts) which are split per-element. The maximum "partial without any
single full criterion" is the sum of all per-element fractions when an agent
hits *some* callbacks and *some* filenames but never all of them:

```
C1=5 (exists) + C2=10 (non-empty file) + C5=3×5=15 (3 of 4 callbacks)
+ C7=3×2.5=7.5 (3 of 4 filenames) + C8=5 (one of two Makefile checks)
= 42.5
```

Plus the do-nothing-like trivial wins (C1 + a near-empty placeholder file
that nonetheless passes C2 at 200 bytes of comments): 5 + 10 = 15.

The worst-case "wrote *some* code but missed an entire callback and a
filename and the Makefile checks" agent caps at 42.5 — well below the 70 pass
threshold. ✓

### Strategy enumeration (Anti-Pattern 13)

| Strategy | C1 | C2 | C3 | C4 | C5 | C6 | C7 | C8 | C9 | Score | Pass? |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|:---:|
| Do-nothing (no files at all) | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | **0** | ✗ |
| Empty project dir only | 5 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | **5** | ✗ |
| 200-byte placeholder `sysinfo.c` of comments only | 5 | 10 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | **15** | ✗ |
| Tutorial hello-world FUSE (no sysctl, no cpu/memory etc.) | 5 | 10 | 15 | 10 | 20 | 0 | 0 | 0 | 0 | **60** | ✗ |
| Sysctl example without correct file routing | 5 | 10 | 15 | 10 | 20 | 15 | 0 | 0 | 0 | **75** | ✓ (over threshold) — see note |
| Correct sysinfo filesystem, source-only (no Makefile) | 5 | 10 | 15 | 10 | 20 | 15 | 10 | 0 | 0 | **85** | ✓ |
| Correct sysinfo filesystem + Makefile (no compile) | 5 | 10 | 15 | 10 | 20 | 15 | 10 | 10 | 0 | **95** | ✓ |
| Correct sysinfo filesystem + Makefile + compile | 5 | 10 | 15 | 10 | 20 | 15 | 10 | 10 | 5 | **100** | ✓ |

The "sysctl example without correct file routing" row scores 75 — this is
intentional. An agent that writes a real FUSE C filesystem with `sysctl`
calls *but* names its files differently is still substantially correct macOS
FUSE C code; rewarding it at 75 reflects that. The task's hard contract is
"all four named files appear in the source"; missing that drops C7 entirely
and the agent doesn't cross the 70 line if it also misses anything else.

The first-row gating ("do-nothing returns 0") is the critical anti-gaming
invariant. With nothing on disk, the agent scores 0/100 — passed=False.

## Setup → Export → Verify flow

1. **`setup_task.sh`** (pre_task)
   - Deletes `~/Documents/sysinfo_fuse/` entirely if it exists (clean slate
     — Anti-Pattern 7: any pre-existing source must be wiped so the agent
     gets no credit for old work).
   - Records task-start Unix timestamp at
     `/tmp/macfuse_sysinfo_fuse_c_task_start_timestamp`.
   - Launches Terminal (the natural editing surface for a C project — agent
     will use vim / nano / cat-heredoc to author the files).
   - Takes a start screenshot.
   - Does NOT echo any sysctl names, callback signatures, or compiler flags.

2. **Agent action** (max ~100 steps)
   - Open Terminal, `mkdir ~/Documents/sysinfo_fuse && cd ...`.
   - Author `sysinfo.c` with `FUSE_USE_VERSION 26`, `#include <fuse.h>`, the
     four required callbacks (`getattr`, `readdir`, `open`, `read`), at
     least two `sysctl*` calls, and the four required filenames as string
     literals.
   - Author `Makefile` with `FUSE_USE_VERSION=26` define and `pkg-config`
     fuse flags.
   - Run `make` and observe the compile outcome.

3. **`export_result.sh`** (post_task)
   - Re-checks project dir existence, source file size.
   - Reads `sysinfo.c` content into a Python heredoc and runs regex / string
     searches for every criterion (FUSE_USE_VERSION ordering relative to
     fuse.h include, callback function definitions, sysctl call count,
     filename string literals).
   - Parses the Makefile.
   - Reports whether `sysinfo_fuse` binary exists and is an executable
     Mach-O.
   - Emits `/tmp/macfuse_sysinfo_fuse_c_result.json` with all flags as
     booleans / ints and the agent's source byte count.

4. **`verifier.py`** (program-mode success)
   - `copy_from_env` pulls the JSON.
   - Applies the per-criterion scoring above and returns
     `{score, passed, feedback, subscores}`.

## Notes

- The FUSE_USE_VERSION-before-fuse.h-include check (C3) is the most
  technical check. Defining the macro *after* `fuse.h` is included is a
  classic FUSE mistake: the header has already been preprocessed against
  the default API version, and the macro has no effect. The verifier
  enforces ordering by checking that the `FUSE_USE_VERSION` token appears
  in the source at a smaller byte offset than the first `fuse.h` include.
- Both `<fuse.h>` and `<fuse/fuse.h>` are accepted as the include form (the
  macFUSE pkg-config invocation puts `/usr/local/include/fuse` on the
  search path, so `<fuse.h>` works; some agents may write `<fuse/fuse.h>`
  which also resolves correctly because `/usr/local/include` is on the
  default search path).
- The C9 compile-success criterion is a 5-pt *bonus*. The kext can't load
  on this sandbox, but `clang` itself compiles & links macFUSE userspace
  programs fine. C9 is genuinely additive — an agent that writes pristine
  C but has a typo somewhere can still pass the task at 95/100.
- Per `12_macos_environments.md` convention, `pre_task` launches Terminal
  (the natural CLI/editing surface for a C project).
- No AX-over-SSH for this task: editing is via Terminal in-session, not
  AppleScript `tell System Events`.
