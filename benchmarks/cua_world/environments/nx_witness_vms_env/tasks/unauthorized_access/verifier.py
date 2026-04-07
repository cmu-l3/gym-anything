#!/usr/bin/env python3
"""
Verifier for unauthorized_access task (UCSD Ped2 Dataset).

Uses UCSD Ped2 anomaly detection ground truth. The agent watches a
pedestrian-only walkway and must detect non-pedestrian objects
(bicycles, carts, skateboards) that violate the zone policy.

Scores based on:
1. Bookmark created (15 pts)
2. Bookmark timing overlaps with anomaly (25 pts)
3. Report exists (10 pts)
4. Report identifies the non-pedestrian object type (25 pts)
5. Report quality and detail (25 pts)
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_unauthorized_access(traj, env_info, task_info):
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
    gt_intervals = gt.get('anomaly_intervals', [])
    video_duration = gt.get('duration', 60.0)
    anomaly_objects = gt.get('anomaly_objects', ['bicycle', 'cart', 'skateboard'])

    # --- Criterion 1: Bookmark exists (15 pts) ---
    target_bm = None
    for b in bookmarks:
        name = b.get('name', '').lower()
        if any(w in name for w in ['violation', 'unauthorized', 'access', 'zone', 'incident', 'bike', 'vehicle']):
            target_bm = b
            break
    if not target_bm and bookmarks:
        target_bm = bookmarks[-1]

    if target_bm:
        score += 15
        feedback.append("Bookmark created.")
    else:
        feedback.append("No bookmark found.")

    # --- Criterion 2: Bookmark timing (25 pts) ---
    if target_bm and gt_intervals:
        bm_start_ms = float(target_bm.get('startTimeMs', 0))
        bm_start_s = (bm_start_ms / 1000.0) % video_duration

        # Check proximity to any GT interval
        min_distance = float('inf')
        best_overlap = 0

        for gt_start, gt_end in gt_intervals:
            dist = min(abs(bm_start_s - gt_start), abs(bm_start_s - gt_end))
            min_distance = min(min_distance, dist)

            # Check overlap
            bm_end_s = bm_start_s + 10  # Assume ~10s bookmark
            overlap = max(0, min(bm_end_s, gt_end) - max(bm_start_s, gt_start))
            gt_len = max(gt_end - gt_start, 0.1)
            best_overlap = max(best_overlap, overlap / gt_len)

        if best_overlap > 0.3 or min_distance < 3:
            score += 25
            feedback.append("Bookmark timing accurate.")
        elif min_distance < 8:
            score += 18
            feedback.append("Bookmark timing close.")
        elif min_distance < 15:
            score += 10
            feedback.append("Bookmark timing approximate.")
        else:
            feedback.append(f"Bookmark timing off (closest: {min_distance:.0f}s).")
    elif not gt_intervals and target_bm:
        score += 12
        feedback.append("Bookmark exists, no GT intervals.")

    # --- Criterion 3: Report exists (10 pts) ---
    if report_exists and report_content and len(report_content) > 20:
        score += 10
        feedback.append("Report created.")
    else:
        feedback.append("No report or too short.")

    # --- Criterion 4: Identifies non-pedestrian object (25 pts) ---
    if report_content and len(report_content) > 20:
        content_lower = report_content.lower()

        object_categories = {
            'bicycle': ['bike', 'bicycle', 'cyclist', 'cycling', 'rider'],
            'cart': ['cart', 'vehicle', 'trolley', 'wagon'],
            'skateboard': ['skateboard', 'skater', 'skating', 'board'],
            'wheelchair': ['wheelchair', 'wheel chair'],
            'generic_vehicle': ['non-pedestrian', 'unauthorized', 'violation', 'object', 'not allowed'],
        }

        objects_found = 0
        for category, words in object_categories.items():
            if any(w in content_lower for w in words):
                objects_found += 1

        if objects_found >= 2:
            score += 25
            feedback.append("Correctly identifies non-pedestrian object type.")
        elif objects_found >= 1:
            score += 15
            feedback.append("Identifies some non-pedestrian presence.")
        else:
            # Check if they at least noticed something unusual
            if any(w in content_lower for w in ['unusual', 'abnormal', 'suspicious', 'different']):
                score += 8
                feedback.append("Notes unusual activity but doesn't identify object.")
            else:
                feedback.append("Did not identify non-pedestrian object.")

    # --- Criterion 5: Report quality (25 pts) ---
    if report_content and len(report_content) > 20:
        content_lower = report_content.lower()

        quality_checks = [
            (any(w in content_lower for w in ['walkway', 'path', 'pedestrian', 'zone', 'area']),
             "References pedestrian zone"),
            (any(w in content_lower for w in ['policy', 'rule', 'regulation', 'restrict', 'prohibit', 'not allowed']),
             "References zone policy"),
            (any(w in content_lower for w in ['time', 'moment', 'second', 'frame', 'point', 'when', 'approximately']),
             "Provides temporal reference"),
            (any(w in content_lower for w in ['enter', 'cross', 'move', 'travel', 'pass', 'appear']),
             "Describes object movement"),
            (len(report_content) > 200, "Detailed report"),
        ]

        quality_score = 0
        for check, desc in quality_checks:
            if check:
                quality_score += 5
                feedback.append(f"Report: {desc}.")

        score += min(25, quality_score)

    return {
        "passed": score >= 50,
        "score": min(100, score),
        "feedback": " ".join(feedback)
    }
