#!/usr/bin/env python3
"""
Verifier for Global Health Explorer Task.
Scores the agent based on PBIX file inspection and timestamp verification.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_global_health_explorer(traj, env_info, task_info):
    """
    Verify the Global Health Explorer Power BI task.
    """
    # 1. Setup access to container files
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env not available"}

    # 2. Retrieve result JSON from VM
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    temp_file.close()
    
    remote_path = r"C:\Users\Docker\Desktop\global_health_result.json"
    
    try:
        copy_from_env(remote_path, temp_file.name)
    except Exception as e:
        logger.error(f"Failed to copy result file: {e}")
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "Verification failed: Could not retrieve result file. Did the task complete successfully?"
        }

    # 3. Parse and Score
    score = 0
    max_score = 100
    feedback_parts = []
    
    try:
        with open(temp_file.name, 'r', encoding='utf-8-sig') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Corrupt result file: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # --- Scoring Criteria ---

    # 1. File saved and legitimate (10 pts)
    if result.get('file_exists') and result.get('file_created_during_task'):
        score += 10
        feedback_parts.append("✅ File saved")
    elif result.get('file_exists'):
        score += 0
        feedback_parts.append("❌ File exists but timestamp indicates it wasn't created during this session")
    else:
        feedback_parts.append("❌ Target file `Global_Health_Explorer.pbix` not found")

    # 2. Page Name (10 pts)
    if result.get('page_name_found'):
        score += 10
        feedback_parts.append("✅ Page renamed to 'Global Health'")
    else:
        feedback_parts.append("❌ Page 'Global Health' not found")

    # 3. Visuals (45 pts total)
    # Filled Map (15)
    if result.get('visual_filled_map'):
        score += 15
        feedback_parts.append("✅ Filled Map present")
    else:
        feedback_parts.append("❌ Filled Map visual missing")

    # Scatter Chart (20)
    if result.get('visual_scatter'):
        score += 20
        feedback_parts.append("✅ Scatter Chart present")
    else:
        feedback_parts.append("❌ Scatter Chart visual missing")
        
    # Table (10)
    if result.get('visual_table'):
        score += 10
        feedback_parts.append("✅ Table visual present")
    else:
        feedback_parts.append("❌ Table visual missing")

    # 4. Data Model Items (35 pts total)
    # Income_Group Calculated Column (20)
    if result.get('model_has_income_group'):
        score += 20
        feedback_parts.append("✅ Calculated column 'Income_Group' found")
    else:
        feedback_parts.append("❌ 'Income_Group' not found in Data Model")

    # Avg_Life_Expectancy Measure (15)
    if result.get('model_has_avg_life_exp'):
        score += 15
        feedback_parts.append("✅ Measure 'Avg_Life_Expectancy' found")
    else:
        feedback_parts.append("❌ 'Avg_Life_Expectancy' not found in Data Model")

    # Final tally
    passed = score >= 60
    
    # 5. Optional: VLM Check on Final Screenshot (Trajectory-based backup)
    # If programmatic check failed suspiciously or for robustness
    if passed:
        feedback_parts.append("(Programmatic verification successful)")

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }