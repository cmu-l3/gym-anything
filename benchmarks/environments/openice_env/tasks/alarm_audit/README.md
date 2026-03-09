# Task: alarm_audit

**Difficulty:** very_hard
**Domain:** Patient Safety / Clinical Quality Improvement
**Environment:** openice_env

---

## Overview

This task places the agent in the role of a patient safety officer at a hospital conducting a formal ICU alarm fatigue investigation. Nursing staff have filed a complaint that the OpenICE monitoring system generates excessive false alarms, causing staff to habituate to them — a well-documented patient safety hazard known as alarm fatigue. The agent must conduct a full audit autonomously, with no guidance on which device to create, which app to use, or what steps to take.

---

## Clinical Context

Alarm fatigue occurs when clinical staff become desensitized to alarm sounds due to a high proportion of false or clinically insignificant alarms. Studies have shown that ICUs experience hundreds of alarms per patient per day, with false alarm rates exceeding 85% in some units. This contributes to delayed response to genuine emergencies and adverse patient outcomes. The Joint Commission has identified alarm safety as a National Patient Safety Goal.

This task simulates a structured alarm audit, a standard quality improvement activity in ICU settings. The agent must:

1. Set up live monitoring conditions by creating an appropriate simulated device adapter in OpenICE
2. Investigate the clinical application suite to identify tools relevant to alarm monitoring and configuration
3. Examine alarm states, enabled parameters, and threshold values for vital signs
4. Assess whether current thresholds are clinically appropriate for an ICU population
5. Produce a written clinical alarm audit report with actionable recommendations

---

## Goal Statement

The agent is given only the high-level clinical goal. It must independently:

- Determine which type of simulated device adapter is appropriate for vital sign monitoring (e.g., a multiparameter patient monitor)
- Discover which OpenICE clinical applications are available and identify those relevant to alarm investigation
- Navigate the UI to observe alarm configurations, active alarms, and current simulated vital sign values
- Assess values against standard ICU normal ranges:
  - Heart Rate (HR): 60-100 bpm
  - SpO2 (oxygen saturation): >= 92%
  - Respiratory Rate (RR): 12-20 breaths/min
- Write a structured clinical report to `/home/ga/Desktop/alarm_audit.txt`

No specific app names, device types, or navigation steps are provided. The agent must discover these on its own.

---

## Required Deliverable

A plain-text clinical alarm audit report saved to:

```
/home/ga/Desktop/alarm_audit.txt
```

The report must include:

1. Specific vital sign parameters examined (HR, SpO2, RR) with any threshold values identified in the system
2. Whether the simulated vital sign values fall within or outside ICU normal ranges
3. Assessment of which alarms appear active versus suppressed
4. Evidence-based recommendations for threshold adjustments with specific numeric values to reduce alarm fatigue while maintaining patient safety

---

## Verification Strategy

Verification is performed by `verifier.py::verify_alarm_audit` using a result JSON exported by `export_result.sh` after task completion.

### New Log Lines Only

Device creation and app launch detection use only log lines generated after task start. The initial log file byte offset is captured at setup time; the verifier reads only bytes written after that offset. This prevents credit for pre-existing activity.

### File Timestamp Check

The report file is validated using `int(mtime) > task_start` (integer comparison of Unix timestamps). The report must have been written or modified after the task started.

### Content Analysis

The report content is analyzed using case-insensitive pattern matching for:
- Vital sign parameter names (HR/heart rate, SpO2/oxygen saturation, RR/respiratory rate)
- Alarm terminology (alarm, threshold, alert, limit, trigger, false alarm, fatigue)
- Numeric values (two-digit or larger numbers representing thresholds)
- Recommendation language (recommend, suggest, should set, adjust to, change to, propose)

---

## Scoring Rubric (100 points)

| Criterion | Points | Detection Method |
|---|---|---|
| Device adapter created | 20 | New log lines match device/adapter creation patterns; +20 if multiparameter monitor detected, +12 if any device |
| Clinical app launched | 15 | New log lines match clinical app launch patterns; +15 if alarm-specific app, +10 if any clinical app |
| Report exists with alarm terminology | 20 | File exists, mtime > task_start, size >= 200 bytes, contains alarm terms |
| Specific vital sign parameters mentioned | 20 | 7 pts for HR, 7 pts for SpO2, 6 pts for RR mentioned by name |
| Numeric threshold values present | 10 | Report contains two-digit or larger numeric values |
| Evidence-based recommendations | 15 | Report contains recommendation language |

**Pass threshold: 60 points**

### GATE Condition

If the report file does not exist at `/home/ga/Desktop/alarm_audit.txt` and the computed score would otherwise reach or exceed 60, the score is capped at 59. The alarm audit report is a required deliverable — the task cannot be considered passed without it, regardless of other activity.

---

## Files

| File | Purpose |
|---|---|
| `README.md` | This documentation |
| `task.json` | Task configuration, description, hooks, and metadata |
| `setup_task.sh` | Pre-task setup: timestamps, log offset capture, window state |
| `export_result.sh` | Post-task export: log analysis, report analysis, result JSON generation |
| `verifier.py` | Scoring logic called by the evaluation framework |

---

## Design Notes

- **Very hard difficulty:** The agent receives no hints about which device type to create, which app to open, or which UI elements to interact with. The clinical scenario itself provides implicit guidance (ICU alarm audit -> vital sign monitor), but the agent must reason about this independently.
- **New log lines approach:** Using initial byte offset rather than timestamps avoids false positives from log rotation or pre-existing entries.
- **Avoid `grep -c ... || echo "0"`:** All binary detection uses `grep -q` to set integer flags (0/1), which is then written into the JSON. This is more portable and avoids shell arithmetic errors.
- **Partial credit:** Most criteria award partial credit to distinguish genuine partial completion from total failure.
