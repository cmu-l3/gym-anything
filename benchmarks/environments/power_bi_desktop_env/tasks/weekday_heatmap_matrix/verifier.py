#!/usr/bin/env python3
"""
Verifier for weekday_heatmap_matrix task.

Scoring (100 points total):
- File saved (15 pts): Weekday_Heatmap.pbix exists
- Page named "Heatmap" (10 pts)
- Calculated columns exists (20 pts): Day_Number and Day_Name found in DataModel
- Total_Sales measure exists (15 pts)
- Matrix visual present (15 pts)
- Card visual present (10 pts)
- Conditional formatting applied (15 pts): Detected in layout

Pass threshold: 70 points
"""

import json
import os
import tempfile
import logging

logger = logging.getLogger(__name__)


def verify_weekday_heatmap(traj, env_info, task_info):
    """Verify the Weekday Heatmap report construction."""

    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    # Copy result JSON from VM
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    temp_file.close()
    
    # Path inside the VM (Windows path mapped)
    vm_path = "C:/Users/Docker/Desktop/weekday_heatmap_result.json"
    
    try:
        copy_from_env(vm_path, temp_file.name)
    except Exception as e:
        logger.warning(f"Failed to copy result JSON: {e}")
        return {"passed": False, "score": 0, "feedback": f"Could not retrieve result file: {e}"}

    try:
        with open(temp_file.name, 'r', encoding='utf-8-sig', errors='replace') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to parse result JSON: {e}"}
    finally:
        try:
            os.unlink(temp_file.name)
        except Exception:
            pass

    score = 0
    feedback_parts = []
    
    # --- Criterion 1: File Saved (15 pts) ---
    if result.get('file_exists', False):
        score += 15
        feedback_parts.append("File saved")
    else:
        feedback_parts.append("File not found")
        return {"passed": False, "score": 0, "feedback": "Weekday_Heatmap.pbix not found on Desktop"}

    # --- Criterion 2: Page Name (10 pts) ---
    # Case insensitive search for "Heatmap"
    page_names = [p.lower() for p in result.get('page_names', [])]
    if "heatmap" in page_names:
        score += 10
        feedback_parts.append("Page named 'Heatmap' found")
    else:
        feedback_parts.append(f"Page 'Heatmap' not found (found: {result.get('page_names')})")

    # --- Criterion 3: Calculated Columns (20 pts) ---
    if result.get('calculated_columns_found', False):
        score += 20
        feedback_parts.append("Calculated columns (Day_Number, Day_Name) found")
    else:
        feedback_parts.append("Calculated columns missing in DataModel")

    # --- Criterion 4: Total_Sales Measure (15 pts) ---
    if result.get('measure_found', False):
        score += 15
        feedback_parts.append("Measure 'Total_Sales' found")
    else:
        feedback_parts.append("Measure 'Total_Sales' missing")

    # --- Criterion 5: Matrix Visual (15 pts) ---
    if result.get('matrix_found', False):
        score += 15
        feedback_parts.append("Matrix visual found")
    else:
        feedback_parts.append("Matrix visual (pivotTable) missing")

    # --- Criterion 6: Card Visual (10 pts) ---
    if result.get('card_found', False):
        score += 10
        feedback_parts.append("Card visual found")
    else:
        feedback_parts.append("Card visual missing")

    # --- Criterion 7: Conditional Formatting (15 pts) ---
    if result.get('conditional_formatting_found', False):
        score += 15
        feedback_parts.append("Conditional formatting detected")
    else:
        feedback_parts.append("No conditional formatting detected on visuals")

    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": "; ".join(feedback_parts)
    }