# Task: infusion_safety_interlock

## Overview

- **Task Name:** infusion_safety_interlock
- **Difficulty:** very_hard
- **Domain:** Clinical/Biomedical Engineering - Infusion Safety
- **Environment:** openice_env@0.1

## Clinical Context

This task simulates a real-world biomedical engineering scenario in a cardiac ICU. The OpenICE (Open-source Integrated Clinical Environment) platform supports closed-loop drug infusion safety by connecting physiological monitoring devices with controllable infusion pumps. When a patient's oxygen saturation (SpO2) drops below a clinically defined threshold, the safety interlock system automatically pauses drug infusion to protect the patient from adverse drug effects during hypoxic episodes.

This type of closed-loop safety system is increasingly relevant in modern ICUs, where automation can respond faster than human observation and reduce medication errors during patient deterioration events.

## Goal

Configure OpenICE's closed-loop drug infusion safety system end-to-end:

1. Identify and create the appropriate simulated device adapter for a **physiological monitoring device** that provides continuous SpO2 readings (the safety trigger signal source).
2. Identify and create the appropriate simulated device adapter for a **controllable infusion pump** (the device that will be automatically paused when SpO2 drops too low).
3. Launch the **Infusion Safety** clinical application within OpenICE and configure the SpO2-based safety interlock threshold — the SpO2 level below which the system should automatically pause drug infusion.
4. Verify that both device adapters are communicating with the Infusion Safety application and that the interlock configuration is active.
5. Write a technical configuration report to `/home/ga/Desktop/infusion_safety_config.txt` documenting:
   - The specific device types created for each role (monitoring device and infusion pump)
   - The SpO2 threshold value configured for the safety interlock
   - A description of the expected system behavior when a patient's SpO2 drops below that threshold

The OpenICE Supervisor application is already running on the desktop at task start.

## Verification Strategy

Verification uses a multi-criterion approach based on the result data exported by `export_result.sh`:

### Log Analysis (New Lines Only)
- The setup script records the byte offset of the OpenICE log file at task start.
- The export script reads only log lines added **after** task start using `tail -c +$((INITIAL_LOG_SIZE + 1))`.
- New log lines are searched for device type names (Multiparameter Monitor, InfusionPump) and app launch events (Infusion Safety).

### Window Title Tracking
- `wmctrl -l` is used at task start and end to count window changes.
- New windows matching device adapter or clinical app names are detected in window titles.

### File Content Checks
- The report file at `/home/ga/Desktop/infusion_safety_config.txt` is checked for existence, size, modification timestamp, and clinical content quality.
- Content checks use `grep -q` (binary match) rather than `grep -c || echo` to avoid incorrect counts.
- Timestamp check uses `int(mtime) > task_start` to correctly compare integer epoch seconds.

## Scoring (100 points total)

| Criterion | Points | Description |
|-----------|--------|-------------|
| Monitoring device created | 25 pts | SpO2-source device adapter (e.g., Multiparameter Monitor) detected in logs or window titles |
| Infusion pump device created | 25 pts | Infusion pump device adapter detected in logs or window titles |
| Infusion Safety app launched | 20 pts | Infusion Safety clinical application opened and interacted with |
| Config report exists with content | 20 pts | `/home/ga/Desktop/infusion_safety_config.txt` exists, >= 100 bytes, written after task start |
| Report clinical quality | 10 pts | Report mentions SpO2 (4 pts), threshold value (3 pts), and behavior description (3 pts) |

**Pass threshold: 60 points**

### Gate Condition
If no device adapter was created AND no report file exists, the verifier returns score=0 immediately without evaluating further criteria.

## Files

| File | Purpose |
|------|---------|
| `task.json` | Task definition, metadata, and success specification |
| `setup_task.sh` | Pre-task hook: records baseline state (log size, window count, timestamp), ensures clean environment |
| `export_result.sh` | Post-task hook: collects all evidence and writes `/tmp/task_result.json` |
| `verifier.py` | Scoring logic: reads result JSON and computes multi-criterion score |
| `README.md` | This file |
