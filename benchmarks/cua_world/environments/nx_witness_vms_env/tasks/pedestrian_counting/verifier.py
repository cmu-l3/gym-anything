#!/usr/bin/env python3
"""
Verifier for pedestrian_counting task.

Uses Mall Dataset ground truth (~62,000 head annotations across 2000 frames).
The agent watches a video made from those frames and estimates foot traffic.

NOTE: The agent sees a compressed video, not individual frames, so exact counting
is impossible. We verify order-of-magnitude and pattern recognition.

Scores based on:
1. Report exists (15 pts)
2. Provides a numeric count estimate (20 pts)
3. Count is in reasonable range (25 pts)
4. Identifies traffic patterns/busy vs quiet periods (25 pts)
5. Report quality and detail (15 pts)
"""

import json
import os
import re
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def extract_count_from_text(text):
    """Try to extract a numeric people count from the report text."""
    # Look for patterns like "approximately 50 people", "total: 120", "counted 85"
    patterns = [
        r'(?:total|count|counted|estimate|approximately|about|roughly|around)\s*:?\s*(\d+)',
        r'(\d+)\s*(?:people|persons|individuals|pedestrians|visitors)',
        r'(?:observed|saw|noted|recorded)\s+(\d+)',
    ]
    for pattern in patterns:
        match = re.search(pattern, text.lower())
        if match:
            return int(match.group(1))

    # Fallback: find any number that could be a count (between 5 and 10000)
    numbers = re.findall(r'\b(\d+)\b', text)
    plausible = [int(n) for n in numbers if 5 <= int(n) <= 10000]
    if plausible:
        return max(plausible)  # Take the largest plausible number

    return None


def verify_pedestrian_counting(traj, env_info, task_info):
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

    report_content = result.get('report_content', '')
    report_exists = result.get('report_exists', False)
    gt = result.get('ground_truth', {})

    # Ground truth: the Mall Dataset averages ~31 people per frame across 2000 frames.
    # But the agent is counting UNIQUE people who appear, not per-frame density.
    # A reasonable estimate for unique people over ~16 minutes in a mall is ~200-800.
    # We use a wide tolerance since this is genuinely hard from video.
    gt_avg_per_frame = gt.get('avg_count_per_frame', 31)
    gt_total_annotations = gt.get('total_annotated_people', 62325)

    score = 0
    feedback = []

    # --- Criterion 1: Report exists (15 pts) ---
    if report_exists and report_content and len(report_content) > 20:
        score += 15
        feedback.append("Report created.")
    else:
        feedback.append("No report or report too short.")
        return {"passed": False, "score": score, "feedback": " ".join(feedback)}

    content_lower = report_content.lower()

    # --- Criterion 2: Provides numeric count (20 pts) ---
    estimated_count = extract_count_from_text(report_content)
    if estimated_count is not None:
        score += 20
        feedback.append(f"Count estimate provided: {estimated_count}.")
    else:
        feedback.append("No numeric count found in report.")

    # --- Criterion 3: Count reasonableness (25 pts) ---
    # The mall video shows a busy corridor. The per-frame average is ~31 people visible.
    # Over 16 minutes at a mall, unique individuals passing through could be 100-2000.
    # We're generous: any count between 20 and 5000 shows the agent tried.
    if estimated_count is not None:
        if 50 <= estimated_count <= 2000:
            score += 25
            feedback.append("Count is in plausible range.")
        elif 20 <= estimated_count <= 5000:
            score += 15
            feedback.append("Count is in broad acceptable range.")
        elif 10 <= estimated_count <= 10000:
            score += 5
            feedback.append("Count is order-of-magnitude plausible.")
        else:
            feedback.append(f"Count {estimated_count} seems unreasonable for mall footage.")

    # --- Criterion 4: Pattern identification (25 pts) ---
    pattern_words = {
        'busy': ['busy', 'crowded', 'peak', 'high traffic', 'heavy'],
        'quiet': ['quiet', 'slow', 'low traffic', 'empty', 'sparse', 'few'],
        'temporal': ['beginning', 'middle', 'end', 'start', 'early', 'later',
                     'first half', 'second half', 'throughout', 'steady', 'consistent'],
        'variation': ['increase', 'decrease', 'fluctuat', 'varies', 'changes',
                      'burst', 'wave', 'pattern', 'trend'],
    }

    patterns_found = 0
    for category, words in pattern_words.items():
        if any(w in content_lower for w in words):
            patterns_found += 1

    if patterns_found >= 3:
        score += 25
        feedback.append("Good temporal pattern analysis.")
    elif patterns_found >= 2:
        score += 15
        feedback.append("Some pattern analysis.")
    elif patterns_found >= 1:
        score += 8
        feedback.append("Minimal pattern observation.")
    else:
        feedback.append("No traffic pattern analysis.")

    # --- Criterion 5: Report quality (15 pts) ---
    if len(report_content) > 400:
        score += 15
        feedback.append("Detailed report.")
    elif len(report_content) > 200:
        score += 10
        feedback.append("Adequate report length.")
    elif len(report_content) > 100:
        score += 5
        feedback.append("Brief report.")

    return {
        "passed": score >= 50,
        "score": min(100, score),
        "feedback": " ".join(feedback)
    }
