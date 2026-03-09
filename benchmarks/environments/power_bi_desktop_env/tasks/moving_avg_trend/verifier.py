#!/usr/bin/env python3
"""
Verifier for moving_avg_trend task.

Scoring (100 points total):
- File saved (10 pts): Moving_Average_Report.pbix exists
- Page naming (10 pts): Page named "Trend Analysis"
- Measures exist (55 pts total):
  - Monthly_Sales (15 pts)
  - Moving_Avg_3M (25 pts)
  - Trend_Variance (15 pts)
- Visuals present (20 pts total):
  - Line Chart (10 pts)
  - Card (5 pts)
  - Slicer (5 pts)
- Time Intelligence Used (5 pts): Keyword check in DataModel

Pass threshold: 70 points
"""

import json
import os
import tempfile
import logging

logger = logging.getLogger(__name__)

def verify_moving_avg_trend(traj, env_info, task_info):
    """
    Verify the Moving Average Trend Analysis task.
    """
    # 1. Setup Environment Access
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env not available"}

    # 2. Retrieve Result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    temp_file.close()
    
    try:
        copy_from_env("C:/Users/Docker/Desktop/moving_avg_result.json", temp_file.name)
    except Exception as e:
        logger.error(f"Copy failed: {e}")
        return {"passed": False, "score": 0, "feedback": "Could not retrieve task result file. Did the agent save the report?"}

    try:
        with open(temp_file.name, 'r', encoding='utf-8-sig', errors='replace') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to parse result data: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 3. Score Calculation
    score = 0
    feedback_parts = []
    
    # Check 1: File Existence (10 pts)
    if result.get('file_exists', False):
        if result.get('file_created_after_start', False):
            score += 10
            feedback_parts.append("File saved successfully")
        else:
            score += 5
            feedback_parts.append("File exists but timestamp is old (reused file?)")
    else:
        return {"passed": False, "score": 0, "feedback": "Moving_Average_Report.pbix not found on Desktop"}

    # Check 2: Page Naming (10 pts)
    page_names = result.get('page_names', [])
    if any("trend analysis" in str(p).lower() for p in page_names):
        score += 10
        feedback_parts.append("Page 'Trend Analysis' found")
    else:
        feedback_parts.append(f"Page name incorrect (Found: {page_names})")

    # Check 3: Measures (55 pts)
    measures = result.get('measure_names_found', [])
    if "Monthly_Sales" in measures:
        score += 15
        feedback_parts.append("Measure 'Monthly_Sales' found")
    else:
        feedback_parts.append("Measure 'Monthly_Sales' missing")

    if "Moving_Avg_3M" in measures:
        score += 25
        feedback_parts.append("Measure 'Moving_Avg_3M' found")
    else:
        feedback_parts.append("Measure 'Moving_Avg_3M' missing")

    if "Trend_Variance" in measures:
        score += 15
        feedback_parts.append("Measure 'Trend_Variance' found")
    else:
        feedback_parts.append("Measure 'Trend_Variance' missing")

    # Check 4: Visuals (20 pts)
    visuals = [v.lower() for v in result.get('visual_types', [])]
    
    if "linechart" in visuals:
        score += 10
        feedback_parts.append("Line chart present")
    else:
        feedback_parts.append("Line chart missing")

    if "card" in visuals:
        score += 5
        feedback_parts.append("Card visual present")
    else:
        feedback_parts.append("Card visual missing")

    if "slicer" in visuals:
        score += 5
        feedback_parts.append("Slicer present")
    else:
        feedback_parts.append("Slicer missing")

    # Check 5: Time Intelligence (5 pts)
    if result.get('time_intelligence_found', False):
        score += 5
        feedback_parts.append("Time intelligence DAX function detected")
    elif "Moving_Avg_3M" in measures:
        # Give benefit of doubt if measure name exists but keyword missed (binary search is tricky)
        # But score slightly less or rely on visual verification in a VLM extension
        pass 

    # 4. Final Verdict
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": "; ".join(feedback_parts)
    }