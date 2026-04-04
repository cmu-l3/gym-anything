#!/usr/bin/env python3
"""
Verifier for circuit_diagram_lesson task.

Scoring System (100 points total, Pass >= 70):
| Criterion | Points | Description |
|-----------|--------|-------------|
| File exists + valid | 15 | Valid flipchart at expected path |
| Page count = 3 | 10 | Exactly 3 pages |
| Title/Intro content | 10 | "Circuit" text present |
| Series text | 10 | "Series" text present |
| Parallel text | 10 | "Parallel" text present |
| Component: Battery | 10 | "Battery" label found |
| Component: Bulb/Res | 10 | "Bulb" or "Resistor" label found |
| Component: Switch | 5 | "Switch" label found |
| Series Diagram | 10 | Page 2 has >= 5 shapes |
| Parallel Diagram | 10 | Page 3 has >= 6 shapes |
"""

import json
import os
import tempfile
import logging

logger = logging.getLogger(__name__)

def verify_circuit_diagram_lesson(traj, env_info, task_info):
    """
    Verify the circuit diagram lesson flipchart.
    Checks for structure, required vocabulary, and diagram complexity (via shape counts).
    """
    # 1. Setup: Retrieve result from environment
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {
            "passed": False,
            "score": 0,
            "feedback": "No copy_from_env function available"
        }

    try:
        tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        tmp_path = tmp.name
        tmp.close()
        try:
            copy_from_env('/tmp/task_result.json', tmp_path)
            with open(tmp_path, 'r', encoding='utf-8-sig') as f:
                result = json.load(f)
        finally:
            if os.path.exists(tmp_path):
                os.unlink(tmp_path)
    except Exception as e:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Could not read export result: {e}"
        }

    # 2. Scoring Logic
    score = 0
    feedback_parts = []
    
    # Gate check: File existence
    if not result.get('file_found'):
        return {
            "passed": False,
            "score": 0,
            "feedback": "Target file not found: circuit_diagram_lesson.flipchart was not saved."
        }

    # Criterion 1: File Validity (15 pts)
    if result.get('file_valid', False) and result.get('created_during_task', False):
        score += 15
        feedback_parts.append("Valid file created (15/15)")
    else:
        feedback_parts.append("File invalid or pre-existing (0/15)")

    # Criterion 2: Page Count (10 pts)
    page_count = result.get('page_count', 0)
    if page_count == 3:
        score += 10
        feedback_parts.append("Correct page count (10/10)")
    else:
        feedback_parts.append(f"Incorrect page count: {page_count}, expected 3 (0/10)")

    # Criterion 3: Text Content (55 pts total)
    # Intro/Title
    if result.get('has_title_intro', False):
        score += 10
        feedback_parts.append("Title/Intro present (10/10)")
    else:
        feedback_parts.append("Missing 'Circuit' title (0/10)")

    # Series/Parallel headers
    if result.get('has_series_text', False):
        score += 10
        feedback_parts.append("'Series' text found (10/10)")
    else:
        feedback_parts.append("Missing 'Series' text (0/10)")

    if result.get('has_parallel_text', False):
        score += 10
        feedback_parts.append("'Parallel' text found (10/10)")
    else:
        feedback_parts.append("Missing 'Parallel' text (0/10)")

    # Components
    if result.get('has_battery', False):
        score += 10
        feedback_parts.append("'Battery' label found (10/10)")
    else:
        feedback_parts.append("Missing 'Battery' label (0/10)")

    if result.get('has_bulb_or_resistor', False):
        score += 10
        feedback_parts.append("'Bulb'/'Resistor' label found (10/10)")
    else:
        feedback_parts.append("Missing 'Bulb'/'Resistor' label (0/10)")

    if result.get('has_switch', False):
        score += 5
        feedback_parts.append("'Switch' label found (5/5)")
    else:
        feedback_parts.append("Missing 'Switch' label (0/5)")

    # Criterion 4: Diagram Complexity / Shape Counts (20 pts)
    # Series Page (Page 2)
    shapes_p2 = result.get('shapes_page_2', 0)
    if shapes_p2 >= 5:
        score += 10
        feedback_parts.append(f"Series diagram has sufficient shapes ({shapes_p2}) (10/10)")
    elif shapes_p2 > 0:
        score += 5
        feedback_parts.append(f"Series diagram too simple ({shapes_p2} shapes) (5/10)")
    else:
        feedback_parts.append("No shapes found on Series page (0/10)")

    # Parallel Page (Page 3)
    shapes_p3 = result.get('shapes_page_3', 0)
    if shapes_p3 >= 6:
        score += 10
        feedback_parts.append(f"Parallel diagram has sufficient shapes ({shapes_p3}) (10/10)")
    elif shapes_p3 > 0:
        score += 5
        feedback_parts.append(f"Parallel diagram too simple ({shapes_p3} shapes) (5/10)")
    else:
        feedback_parts.append("No shapes found on Parallel page (0/10)")

    # 3. Final Determination
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": "; ".join(feedback_parts)
    }