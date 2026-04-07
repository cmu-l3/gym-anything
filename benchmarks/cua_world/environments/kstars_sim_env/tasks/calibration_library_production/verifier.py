#!/usr/bin/env python3
"""
Verifier for calibration_library_production task.

Occupation: Observatory Director / CCD Operations Manager
Context: Building a complete CCD calibration library (bias, darks, flats) before a science run.
         Contains error injection: 3 stale pre-task bias files that must NOT be counted.

Criteria (100 pts total, pass >= 60):
1. Bias frames (≥10 NEW frames created during task, excl. stale ones) - 15 pts
2. Dark 300s frames (≥10 in darks/300s/)                               - 15 pts
3. Dark 600s frames (≥10 in darks/600s/)                               - 15 pts
4. V-band flat frames (≥5 in flats/V/)                                 - 12 pts
5. R-band flat frames (≥5 in flats/R/)                                 - 12 pts
6. B-band flat frames (≥5 in flats/B/)                                 - 12 pts
7. Directory structure correct (all 6 dirs exist)                       - 9 pts
8. Summary report with correct counts                                   - 10 pts

Anti-gaming: stale bias files have mtime from 2024 — they predate task start.
             Only files with mtime > task_start count toward required totals.

Do-nothing score: ~0 pts (3 stale bias files exist but have mtime < task_start)
Passed: False in do-nothing state (well below 60 pt threshold).
"""

import json
import base64
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

STALE_BIAS_NAMES = {'old_bias_001.fits', 'old_bias_002.fits', 'old_bias_003.fits'}


def verify_calibration_library_production(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env unavailable"}

    metadata = task_info.get('metadata', {})
    req_bias = metadata.get('required_bias', 10)
    req_dark_300 = metadata.get('required_dark_300s', 10)
    req_dark_600 = metadata.get('required_dark_600s', 10)
    req_flat_v = metadata.get('required_flat_V', 5)
    req_flat_r = metadata.get('required_flat_R', 5)
    req_flat_b = metadata.get('required_flat_B', 5)

    tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", tmp.name)
        with open(tmp.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Could not read task result: {e}"}
    finally:
        if os.path.exists(tmp.name):
            os.unlink(tmp.name)

    score = 0
    feedback = []
    task_start = result.get('task_start', 0)

    fits_files = result.get('fits_files', [])

    def count_category(cat, min_size=100):
        """Count valid FITS in a category, created AFTER task start, excluding stale files."""
        count = 0
        for f in fits_files:
            if (f.get('category') == cat and
                    f.get('mtime', 0) > task_start and
                    f.get('size', 0) > min_size and
                    f.get('name', '') not in STALE_BIAS_NAMES):
                count += 1
        return count

    bias_count = count_category('bias', min_size=0)  # bias can be tiny in simulator
    dark300_count = count_category('dark_300s')
    dark600_count = count_category('dark_600s')
    flat_v_count = count_category('flat_V')
    flat_r_count = count_category('flat_R')
    flat_b_count = count_category('flat_B')

    # ── Criterion 1: Bias frames (15 pts) ─────────────────────────────
    if bias_count >= req_bias:
        score += 15
        feedback.append(f"bias: {bias_count} frames (stale files excluded)")
    elif bias_count >= 5:
        score += 8
        feedback.append(f"bias: {bias_count}/{req_bias} frames")
    elif bias_count >= 1:
        score += 4
        feedback.append(f"bias: only {bias_count} valid frame(s)")
    else:
        feedback.append("bias: no new frames created during task")

    # ── Criterion 2: Dark 300s (15 pts) ───────────────────────────────
    if dark300_count >= req_dark_300:
        score += 15
        feedback.append(f"dark 300s: {dark300_count} frames")
    elif dark300_count >= 5:
        score += 8
        feedback.append(f"dark 300s: {dark300_count}/{req_dark_300} frames")
    elif dark300_count >= 1:
        score += 4
        feedback.append(f"dark 300s: only {dark300_count} frame(s)")
    else:
        feedback.append("dark 300s: no frames in darks/300s/")

    # ── Criterion 3: Dark 600s (15 pts) ───────────────────────────────
    if dark600_count >= req_dark_600:
        score += 15
        feedback.append(f"dark 600s: {dark600_count} frames")
    elif dark600_count >= 5:
        score += 8
        feedback.append(f"dark 600s: {dark600_count}/{req_dark_600} frames")
    elif dark600_count >= 1:
        score += 4
        feedback.append(f"dark 600s: only {dark600_count} frame(s)")
    else:
        feedback.append("dark 600s: no frames in darks/600s/")

    # ── Criterion 4: V flats (12 pts) ─────────────────────────────────
    if flat_v_count >= req_flat_v:
        score += 12
        feedback.append(f"flat V: {flat_v_count} frames")
    elif flat_v_count >= 2:
        score += 6
        feedback.append(f"flat V: {flat_v_count}/{req_flat_v} frames")
    elif flat_v_count >= 1:
        score += 3
        feedback.append(f"flat V: only {flat_v_count} frame")
    else:
        feedback.append("flat V: no frames in flats/V/")

    # ── Criterion 5: R flats (12 pts) ─────────────────────────────────
    if flat_r_count >= req_flat_r:
        score += 12
        feedback.append(f"flat R: {flat_r_count} frames")
    elif flat_r_count >= 2:
        score += 6
        feedback.append(f"flat R: {flat_r_count}/{req_flat_r} frames")
    elif flat_r_count >= 1:
        score += 3
        feedback.append(f"flat R: only {flat_r_count} frame")
    else:
        feedback.append("flat R: no frames in flats/R/")

    # ── Criterion 6: B flats (12 pts) ─────────────────────────────────
    if flat_b_count >= req_flat_b:
        score += 12
        feedback.append(f"flat B: {flat_b_count} frames")
    elif flat_b_count >= 2:
        score += 6
        feedback.append(f"flat B: {flat_b_count}/{req_flat_b} frames")
    elif flat_b_count >= 1:
        score += 3
        feedback.append(f"flat B: only {flat_b_count} frame")
    else:
        feedback.append("flat B: no frames in flats/B/")

    # ── Criterion 7: Directory structure (9 pts) ──────────────────────
    dirs = result.get('dirs', {})
    dir_count = sum(1 for v in dirs.values() if v)
    if dir_count >= 6:
        score += 9
        feedback.append("all 6 calibration directories present")
    elif dir_count >= 4:
        score += 5
        feedback.append(f"{dir_count}/6 calibration directories present")
    elif dir_count >= 2:
        score += 2
        feedback.append(f"{dir_count}/6 directories present")
    else:
        feedback.append("directory structure missing")

    # ── Criterion 8: Summary report (10 pts) ──────────────────────────
    summary_exists = result.get('summary_exists', False)
    summary_mtime = result.get('summary_mtime', 0)
    summary_b64 = result.get('summary_b64', '')

    if summary_exists and summary_mtime > task_start:
        if summary_b64:
            try:
                summary_text = base64.b64decode(summary_b64).decode('utf-8', errors='ignore')
                summary_text = summary_text.replace('\\n', '\n').replace('\\t', '\t')
                upper = summary_text.upper()
                has_bias = 'BIAS' in upper
                has_dark = 'DARK' in upper
                has_flat = 'FLAT' in upper
                has_numbers = any(c.isdigit() for c in summary_text)
                has_complete = 'COMPLETE' in upper or 'STATUS' in upper

                content_score = sum([has_bias, has_dark, has_flat, has_numbers, has_complete])
                if content_score >= 4:
                    score += 10
                    feedback.append("summary report complete and valid")
                elif content_score >= 3:
                    score += 7
                    feedback.append("summary report mostly valid")
                elif content_score >= 2:
                    score += 4
                    feedback.append("summary report partially valid")
                else:
                    score += 2
                    feedback.append("summary report exists but content incomplete")
            except Exception as e:
                score += 2
                feedback.append(f"summary report unreadable: {e}")
        else:
            score += 2
            feedback.append("summary report file empty")
    elif summary_exists:
        feedback.append("summary file exists but has pre-task timestamp")
    else:
        feedback.append("summary report not found at /home/ga/Calibration/calibration_summary.txt")

    # ── Final verdict ─────────────────────────────────────────────────
    # Require ALL core frames (bias+both darks) AND all 3 flat series — prevents
    # Anti-Pattern 4 where bias(15)+darks(30)+2flats(24)+dirs(9)+summary(7)=85 passes
    # without completing the B-flat series.
    core_complete = (bias_count >= req_bias and
                     dark300_count >= req_dark_300 and
                     dark600_count >= req_dark_600)
    flats_complete = (flat_v_count >= req_flat_v and
                      flat_r_count >= req_flat_r and
                      flat_b_count >= req_flat_b)
    passed = (score >= 60) and core_complete and flats_complete

    return {
        "passed": passed,
        "score": score,
        "feedback": "; ".join(feedback)
    }
