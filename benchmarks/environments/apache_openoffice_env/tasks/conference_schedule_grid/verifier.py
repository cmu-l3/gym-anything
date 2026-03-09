#!/usr/bin/env python3
"""
Verifier for conference_schedule_grid task.

Scoring Breakdown (100 pts total):
1. File Validity (10 pts): File exists and is a valid ODT.
2. Anti-Gaming (10 pts): File created/modified during task window.
3. Page Layout (15 pts): Orientation is Landscape.
4. Table Structure (15 pts): Document contains a table.
5. Merged Cells (25 pts): Plenary sessions span columns (colspan detected).
6. Content Accuracy (25 pts): Specific session titles found in text.

Pass Threshold: 70 pts
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_conference_schedule_grid(traj, env_info, task_info):
    """Verify the conference schedule grid creation."""
    
    # 1. Setup and Load Data
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Infrastructure error: copy_from_env missing"}

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

    # 2. Scoring Logic
    score = 0
    feedback = []

    # Criterion 1: File Existence (10 pts)
    if result.get("file_exists", False):
        score += 10
        feedback.append("File 'Summit_Schedule_2025.odt' created.")
    else:
        return {"passed": False, "score": 0, "feedback": "Output file not found."}

    # Criterion 2: Created During Task (10 pts)
    if result.get("created_during_task", False):
        score += 10
    else:
        feedback.append("Warning: File timestamp suggests it wasn't modified during the task.")

    # Criterion 3: Landscape Orientation (15 pts)
    if result.get("is_landscape", False):
        score += 15
        feedback.append("Page orientation is Landscape.")
    else:
        feedback.append("Page orientation is NOT Landscape (expected for wide grid).")

    # Criterion 4: Table Existence (15 pts)
    if result.get("has_table", False):
        score += 15
        feedback.append("Table structure detected.")
    else:
        feedback.append("No table found in document.")

    # Criterion 5: Merged Cells / Spans (25 pts)
    # We look for table:number-columns-spanned attribute count.
    # There are 4 plenary sessions in the JSON (Registration, Keynote, Lunch, Closing).
    # We expect at least 3 merges (some might be missed or done differently).
    merges = result.get("merged_rows_count", 0)
    if merges >= 3:
        score += 25
        feedback.append(f"Merged cells detected for plenary sessions ({merges} spans found).")
    elif merges >= 1:
        score += 10
        feedback.append(f"Partial credit: Some merged cells found ({merges}), but fewer than expected.")
    else:
        feedback.append("No merged cells detected. Plenary sessions should span columns.")

    # Criterion 6: Content Check (25 pts)
    content_score = 0
    checks = result.get("content_check", {})
    total_checks = len(checks)
    
    # Weight per item
    if total_checks > 0:
        passed_checks = sum(1 for v in checks.values() if v)
        content_score = int((passed_checks / total_checks) * 25)
        score += content_score
        feedback.append(f"Content accuracy: {passed_checks}/{total_checks} key phrases found.")

    # 3. Final Result
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback),
        "details": result
    }