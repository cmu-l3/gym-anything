#!/usr/bin/env python3
"""
Verifier for Presidential Ages Statistics task.

Scoring Criteria (100 points total):
1. Anti-gaming: File created/modified during task (15 pts)
2. Data Entry: List exists with ~46 items including specific unique values (25 pts)
3. Histogram: Histogram command used (20 pts)
4. BoxPlot: BoxPlot command used (20 pts)
5. Analysis: Text annotation showing Median (55) (20 pts)

Pass Threshold: 60 points (must have file + data + at least one plot)
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)

PASS_THRESHOLD = 60

def verify_presidential_ages_boxplot_histogram(traj, env_info, task_info):
    """Verify the presidential ages statistics task."""
    
    # 1. Setup copy_from_env
    copy_from_env = env_info.get('copy_from_env') or env_info.get('exec_capture')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Host environment error: copy_from_env unavailable"}

    # 2. Retrieve result JSON
    try:
        tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        tmp.close()
        try:
            copy_from_env("/tmp/task_result.json", tmp.name)
            with open(tmp.name, 'r', encoding='utf-8') as f:
                result = json.load(f)
        finally:
            if os.path.exists(tmp.name):
                os.unlink(tmp.name)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve verification results: {str(e)}"}

    score = 0
    feedback_parts = []
    
    # 3. Criterion 1: File Existence & Anti-Gaming (15 pts)
    if result.get("file_found", False) and result.get("file_created_during_task", False):
        score += 15
        feedback_parts.append("File created successfully (+15)")
    elif result.get("file_found", False):
        feedback_parts.append("File exists but was created before task start (0/15)")
    else:
        feedback_parts.append("Target file 'presidential_ages_stats.ggb' not found (0/15)")
        # Critical failure if no file
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}

    # 4. Criterion 2: Data Entry Integrity (25 pts)
    # We check for list length (>40) and specific values to ensure real data usage
    list_count = result.get("list_item_count", 0)
    has_valid_list = result.get("has_valid_list", False)
    sentinels = result.get("found_sentinel_values", False)
    
    if has_valid_list and sentinels:
        score += 25
        feedback_parts.append(f"Data entered correctly ({list_count} items with correct values) (+25)")
    elif has_valid_list:
        score += 15
        feedback_parts.append(f"List found ({list_count} items) but missing specific key values (15/25)")
    elif list_count > 10:
        score += 5
        feedback_parts.append(f"Partial data entered ({list_count} items), expected 46 (5/25)")
    else:
        feedback_parts.append("Valid data list not found (0/25)")

    # 5. Criterion 3: Histogram (20 pts)
    if result.get("has_histogram", False):
        score += 20
        feedback_parts.append("Histogram created (+20)")
    else:
        feedback_parts.append("Histogram command not found (0/20)")

    # 6. Criterion 4: BoxPlot (20 pts)
    if result.get("has_boxplot", False):
        score += 20
        feedback_parts.append("BoxPlot created (+20)")
    else:
        feedback_parts.append("BoxPlot command not found (0/20)")

    # 7. Criterion 5: Text Annotation (Median=55) (20 pts)
    if result.get("has_median_text", False):
        score += 20
        feedback_parts.append("Median annotation found (+20)")
    else:
        feedback_parts.append("Median annotation (55) not found (0/20)")

    # 8. Final Assessment
    passed = score >= PASS_THRESHOLD
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }