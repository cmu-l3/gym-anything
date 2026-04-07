#!/usr/bin/env python3
"""
Verifier for suspicious_activity task (CUHK Avenue Dataset).

Uses frame-level anomaly labels from Avenue Dataset testing videos.
The agent watches a campus walkway and must identify abnormal behavior
(throwing objects, running, loitering).

Scores based on:
1. Bookmark created (20 pts)
2. Bookmark timing overlaps with ground truth anomaly window (30 pts)
3. Report exists (10 pts)
4. Report identifies abnormal activity type (20 pts)
5. Report quality and detail (20 pts)
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_suspicious_activity(traj, env_info, task_info):
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

    # Ground truth anomaly intervals (seconds)
    gt_intervals = gt.get('anomaly_intervals', [])
    video_duration = gt.get('duration', 120)

    # --- Criterion 1: Bookmark exists (20 pts) ---
    target_bm = None
    for b in bookmarks:
        name = b.get('name', '').lower()
        if any(w in name for w in ['suspicious', 'anomal', 'abnormal', 'incident', 'alert', 'activity']):
            target_bm = b
            break
    if not target_bm and bookmarks:
        target_bm = bookmarks[-1]

    if target_bm:
        score += 20
        feedback.append("Bookmark created.")
    else:
        feedback.append("No bookmark found.")

    # --- Criterion 2: Bookmark timing (30 pts) ---
    if target_bm and gt_intervals:
        bm_start_ms = float(target_bm.get('startTimeMs', 0))
        bm_end_ms = float(target_bm.get('endTimeMs', bm_start_ms + 5000))

        # Convert to position in looping video
        bm_start_s = (bm_start_ms / 1000.0) % video_duration
        bm_end_s = (bm_end_ms / 1000.0) % video_duration
        if bm_end_s < bm_start_s:
            bm_end_s = video_duration

        # Check overlap with any GT interval
        best_overlap = 0
        for gt_start, gt_end in gt_intervals:
            overlap_start = max(bm_start_s, gt_start)
            overlap_end = min(bm_end_s, gt_end)
            overlap = max(0, overlap_end - overlap_start)
            gt_len = gt_end - gt_start
            if gt_len > 0:
                overlap_ratio = overlap / gt_len
                best_overlap = max(best_overlap, overlap_ratio)

        # Also check if bookmark start is near any anomaly
        min_distance = float('inf')
        for gt_start, gt_end in gt_intervals:
            dist = min(abs(bm_start_s - gt_start), abs(bm_start_s - gt_end))
            min_distance = min(min_distance, dist)

        if best_overlap > 0.3:
            score += 30
            feedback.append("Bookmark timing accurately covers anomaly.")
        elif best_overlap > 0:
            score += 20
            feedback.append("Bookmark partially overlaps anomaly.")
        elif min_distance < 10:
            score += 15
            feedback.append("Bookmark near anomaly window.")
        elif min_distance < 20:
            score += 8
            feedback.append("Bookmark approximately near anomaly.")
        else:
            feedback.append(f"Bookmark timing off (closest: {min_distance:.0f}s from anomaly).")
    elif not gt_intervals and target_bm:
        score += 15
        feedback.append("Bookmark exists, no timing GT available.")

    # --- Criterion 3: Report exists (10 pts) ---
    if report_exists and report_content and len(report_content) > 20:
        score += 10
        feedback.append("Report created.")
    else:
        feedback.append("No report or too short.")

    # --- Criterion 4: Identifies activity type (20 pts) ---
    if report_content and len(report_content) > 20:
        content_lower = report_content.lower()

        activity_words = {
            'throwing': ['throw', 'toss', 'hurl', 'fling', 'bag', 'object', 'drop'],
            'running': ['run', 'sprint', 'dash', 'fast', 'speed', 'rush', 'jog'],
            'wrong_direction': ['wrong direction', 'opposite', 'against flow', 'backward'],
            'loitering': ['loiter', 'linger', 'stand', 'wait', 'idle', 'stationary'],
            'abnormal': ['abnormal', 'unusual', 'suspicious', 'strange', 'odd', 'anomal'],
        }

        types_found = 0
        for category, words in activity_words.items():
            if any(w in content_lower for w in words):
                types_found += 1

        if types_found >= 2:
            score += 20
            feedback.append("Report identifies specific abnormal activity.")
        elif types_found >= 1:
            score += 12
            feedback.append("Report mentions abnormal behavior.")
        else:
            feedback.append("Report doesn't identify specific activity type.")

    # --- Criterion 5: Report quality (20 pts) ---
    if report_content and len(report_content) > 20:
        content_lower = report_content.lower()
        quality_checks = [
            (any(w in content_lower for w in ['person', 'individual', 'man', 'woman', 'pedestrian', 'someone']),
             "Describes person involved"),
            (any(w in content_lower for w in ['walkway', 'path', 'corridor', 'area', 'campus', 'entrance']),
             "References location"),
            (any(w in content_lower for w in ['time', 'moment', 'point', 'second', 'minute', 'approximately', 'around']),
             "Provides temporal reference"),
            (len(report_content) > 200, "Sufficient detail"),
        ]

        quality_score = 0
        for check, desc in quality_checks:
            if check:
                quality_score += 5
                feedback.append(f"Report: {desc}.")

        score += min(20, quality_score)

    return {
        "passed": score >= 50,
        "score": min(100, score),
        "feedback": " ".join(feedback)
    }
