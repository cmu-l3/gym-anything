#!/usr/bin/env python3
"""
Verifier for crowd_dispersal task (UMN Crowd Dataset).

Uses UMN crowd panic dataset ground truth. The agent watches an indoor
crowd scene and must detect when normal behavior transitions to panic/dispersal.

Scores based on:
1. Bookmark created (15 pts)
2. Bookmark timing near panic onset (25 pts)
3. Report exists (10 pts)
4. Report identifies crowd dispersal/panic (25 pts)
5. Report describes before/after behavior (25 pts)
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_crowd_dispersal(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    bookmarks = result.get('bookmarks', [])
    gt = result.get('ground_truth', {})
    report_content = result.get('report_content', '')
    report_exists = result.get('report_exists', False)

    if not isinstance(bookmarks, list):
        bookmarks = []

    score = 0
    feedback = []

    # Ground truth
    panic_onset = gt.get('panic_onset_seconds', 60.0)
    video_duration = gt.get('duration', 84.0)
    gt_intervals = gt.get('anomaly_intervals', [[panic_onset, video_duration]])

    # --- Criterion 1: Bookmark exists (15 pts) ---
    target_bm = None
    for b in bookmarks:
        name = b.get('name', '').lower()
        if any(w in name for w in ['crowd', 'panic', 'dispersal', 'incident', 'safety', 'emergency']):
            target_bm = b
            break
    if not target_bm and bookmarks:
        target_bm = bookmarks[-1]

    if target_bm:
        score += 15
        feedback.append("Bookmark created.")
    else:
        feedback.append("No bookmark found.")

    # --- Criterion 2: Bookmark timing near panic onset (25 pts) ---
    if target_bm:
        bm_start_ms = float(target_bm.get('startTimeMs', 0))
        bm_start_s = (bm_start_ms / 1000.0) % video_duration

        distance = abs(bm_start_s - panic_onset)

        if distance < 5:
            score += 25
            feedback.append("Bookmark timing very accurate.")
        elif distance < 10:
            score += 20
            feedback.append("Bookmark timing close to panic onset.")
        elif distance < 20:
            score += 12
            feedback.append("Bookmark timing approximately correct.")
        elif distance < 30:
            score += 5
            feedback.append("Bookmark timing in right region.")
        else:
            feedback.append(f"Bookmark at {bm_start_s:.0f}s, panic at {panic_onset:.0f}s.")

    # --- Criterion 3: Report exists (10 pts) ---
    if report_exists and report_content and len(report_content) > 20:
        score += 10
        feedback.append("Report created.")
    else:
        feedback.append("No report or too short.")
        return {"passed": False, "score": score, "feedback": " ".join(feedback)}

    content_lower = report_content.lower()

    # --- Criterion 4: Identifies crowd dispersal (25 pts) ---
    dispersal_checks = {
        'panic': ['panic', 'panick', 'scared', 'fear', 'alarm', 'fright'],
        'dispersal': ['dispers', 'scatter', 'flee', 'evacuate', 'rush', 'stampede'],
        'running': ['run', 'sprint', 'dash', 'hurry', 'fast', 'rapid'],
        'crowd': ['crowd', 'group', 'people', 'gather', 'mass', 'everyone'],
        'sudden': ['sudden', 'abrupt', 'unexpected', 'quick', 'immediate'],
    }

    categories_found = 0
    for category, words in dispersal_checks.items():
        if any(w in content_lower for w in words):
            categories_found += 1

    if categories_found >= 4:
        score += 25
        feedback.append("Excellent identification of crowd dispersal.")
    elif categories_found >= 3:
        score += 20
        feedback.append("Good identification of crowd event.")
    elif categories_found >= 2:
        score += 12
        feedback.append("Partial identification of crowd behavior change.")
    elif categories_found >= 1:
        score += 5
        feedback.append("Minimal crowd behavior observation.")
    else:
        feedback.append("Did not identify crowd dispersal.")

    # --- Criterion 5: Describes before/after behavior (25 pts) ---
    before_after_checks = [
        (any(w in content_lower for w in ['normal', 'calm', 'peaceful', 'regular', 'ordinary', 'usual']),
         "Describes normal pre-event behavior"),
        (any(w in content_lower for w in ['change', 'transition', 'shift', 'transform', 'suddenly', 'then']),
         "Describes behavioral transition"),
        (any(w in content_lower for w in ['after', 'during', 'result', 'chaos', 'disorder', 'empty', 'cleared']),
         "Describes post-event state"),
        (any(w in content_lower for w in ['walking', 'standing', 'sitting', 'milling', 'conversat', 'interact']),
         "Describes specific normal activities"),
        (len(report_content) > 200, "Detailed report"),
    ]

    before_after_score = 0
    for check, desc in before_after_checks:
        if check:
            before_after_score += 5
            feedback.append(f"Report: {desc}.")

    score += min(25, before_after_score)

    return {
        "passed": score >= 50,
        "score": min(100, score),
        "feedback": " ".join(feedback)
    }
