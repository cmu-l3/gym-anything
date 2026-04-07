# Service Observing Queue Execution (`service_queue_execution@1`)

## Overview

**Difficulty:** very_hard
**Occupation:** Observatory Operator / Service Observer
**Industry:** Professional Observatory Operations
**Environment:** kstars_sim_env (KStars + INDI Simulators)

A professional observatory operator must execute a pre-planned service observing queue for three principal investigators on a shared telescope. Each PI has requested observations of a different target with specific filter, exposure, and file management requirements. The agent must read the queue document, slew to each target in sequence, configure filters and exposures correctly, manage per-target upload directories, and produce a formal session log summarizing the night's work.

## Rationale

**Why this task is valuable:**
- Tests multi-target observatory management — the most common real professional observing workflow
- Requires sequential INDI device reconfiguration across 3 slews, 6 filter changes, and 24 total exposures
- Exercises file organization discipline (separate directories per target)
- Demands production of a structured session log — a real professional requirement
- Validates the agent can follow a complex document with heterogeneous instructions per target

**Real-world Context:** Service observing is how most professional telescopes operate. Telescope time is shared among multiple investigators, and a trained operator executes each PI's program in priority order, switching targets, filters, and exposure parameters throughout the night. Proper logging is mandatory for data provenance.

## What Makes This Very Hard

1. **No step-by-step instructions** — only the queue document specifying what to observe
2. **Three distinct targets in different parts of the sky** — requires 3 separate slews with coordinate input
3. **Six filter/exposure configurations** — B+V for M44, Ha+OIII for NGC 2392, L+R for M51
4. **Per-target upload directory management** — must change CCD upload path 3 times
5. **24 total exposures across varying durations** (30s, 60s, 120s)
6. **Telescope starts pointed at Polaris** (Dec +89°), far from all targets
7. **Session log must be comprehensive** — covering all targets, filters, and counts

## Task Description (What the Agent Sees)

You are the service observer at a shared observatory tonight. A queue document has been prepared at `~/Documents/observing_queue.txt` containing three PI programs to execute.

**Your tasks:**
1. Read the queue document at `~/Documents/observing_queue.txt`
2. Execute all three queue entries in order, slewing to each target, setting the correct filters, configuring the upload directory, and taking the specified exposures
3. After completing all observations, capture a sky view using `bash ~/capture_sky_view.sh ~/Images/queue/final_sky.png`
4. Write a session log to `/home/ga/Documents/session_log.txt` summarizing each target observed, filters used, and number of exposures completed

All CCD images must be saved as FITS files to the upload directories specified in the queue document. Use INDI command-line tools (`indi_setprop`, `indi_getprop`) to control the telescope, CCD, and filter wheel.

## Queue Document Content

The file `~/Documents/observing_queue.txt` will contain: