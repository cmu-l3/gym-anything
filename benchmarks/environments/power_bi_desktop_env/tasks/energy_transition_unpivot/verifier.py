#!/usr/bin/env python3
"""
Verifier for energy_transition_unpivot task.

Scoring (100 points total):
- File saved (10 pts)
- ETL: Unpivot successful (25 pts) - "Generation_TWh" column exists
- Measures: Total_Generation (15 pts), Renewable_Share_Pct (20 pts)
- Visuals: Stacked Area Chart (20 pts), Card (10 pts)

Pass threshold: 70 points
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_energy_transition(traj, env_info, task_info):
    """Verify Power BI report for Energy Transition task."""
    
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    # Retrieve result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    temp_file.close()
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # 1. File Existence (10 pts)
    if result.get('file_exists') and result.get('file_size_bytes', 0) > 1000:
        score += 10
        feedback_parts.append("File saved")
    else:
        feedback_parts.append("File not found or empty")
        return {"passed": False, "score": 0, "feedback": "File not found"}

    # 2. ETL Verification (25 pts)
    # If "Generation_TWh" is found in DataModel, they likely renamed/unpivoted
    if result.get('unpivot_success'):
        score += 25
        feedback_parts.append("ETL Unpivot successful")
    else:
        feedback_parts.append("ETL failed: 'Generation_TWh' column not found")

    # 3. Measures (35 pts)
    measures = result.get('measures_found', [])
    if "Total_Generation" in measures:
        score += 15
        feedback_parts.append("Total_Generation measure found")
    else:
        feedback_parts.append("Total_Generation measure missing")
        
    if "Renewable_Share_Pct" in measures:
        score += 20
        feedback_parts.append("Renewable_Share_Pct measure found")
    else:
        feedback_parts.append("Renewable_Share_Pct measure missing")

    # 4. Visuals (30 pts)
    visuals = result.get('visuals_found', [])
    if "AreaChart" in visuals:
        score += 20
        feedback_parts.append("Stacked Area Chart found")
    else:
        feedback_parts.append("Stacked Area Chart missing")
        
    if "Card" in visuals:
        score += 10
        feedback_parts.append("Card visual found")
    else:
        feedback_parts.append("Card visual missing")

    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": ", ".join(feedback_parts)
    }