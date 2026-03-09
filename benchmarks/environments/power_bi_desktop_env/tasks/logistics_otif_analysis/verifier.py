#!/usr/bin/env python3
"""
Verifier for logistics_otif_analysis task.

Scoring (100 points total):
- File saved (15 pts): OTIF_Report.pbix exists
- File created during task (10 pts): Anti-gaming check
- Measure 'OTIF Rate' created (25 pts): Found in DataModel
- Logic Indicators (15 pts): Key columns used in model (ActualDate, PromisedDate, etc.)
- Visuals present (25 pts): Clustered Bar Chart (15) + Card (10)
- Field usage (10 pts): 'Carrier' field used in report

Pass threshold: 70 points
"""

import json
import os
import tempfile
import logging

logger = logging.getLogger(__name__)

def verify_logistics_otif_analysis(traj, env_info, task_info):
    """Verify OTIF report creation and structure."""

    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    # Copy result JSON from VM
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    temp_file.close()
    
    # Path inside the VM (Windows path mapped to expected location)
    remote_path = "C:/Users/Docker/Desktop/otif_result.json"
    
    try:
        copy_from_env(remote_path, temp_file.name)
    except Exception as e:
        logger.warning(f"Failed to copy result JSON: {e}")
        return {"passed": False, "score": 0, "feedback": f"Could not retrieve result file: {e}"}

    try:
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to parse result JSON: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # 1. File saved (15 pts)
    if result.get('file_exists'):
        score += 15
        feedback_parts.append("Report file saved.")
    else:
        feedback_parts.append("Report file NOT found.")
        return {"passed": False, "score": 0, "feedback": "Report file not found"}

    # 2. Anti-gaming (10 pts)
    if result.get('file_created_after_start'):
        score += 10
    else:
        feedback_parts.append("File appears to be older than task start.")

    # 3. Measure check (25 pts)
    if result.get('measure_found'):
        score += 25
        feedback_parts.append("'OTIF Rate' measure found.")
    else:
        feedback_parts.append("'OTIF Rate' measure missing.")

    # 4. Logic indicators (15 pts)
    if result.get('otif_logic_keywords'):
        score += 15
        feedback_parts.append("OTIF logic columns found in model.")
    else:
        feedback_parts.append("Logic columns (Dates/Qtys) not clearly used in model.")

    # 5. Visuals (25 pts)
    visuals_score = 0
    if result.get('clustered_bar_found'):
        visuals_score += 15
        feedback_parts.append("Clustered Bar Chart found.")
    else:
        feedback_parts.append("Clustered Bar Chart missing.")
        
    if result.get('card_found'):
        visuals_score += 10
        feedback_parts.append("Card visual found.")
    else:
        feedback_parts.append("Card visual missing.")
    score += visuals_score

    # 6. Field usage (10 pts)
    if result.get('carrier_field_used'):
        score += 10
        feedback_parts.append("Carrier field used in visuals.")
    else:
        feedback_parts.append("Carrier field usage not detected.")

    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback_parts)
    }