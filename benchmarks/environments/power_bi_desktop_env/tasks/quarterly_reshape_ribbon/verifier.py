#!/usr/bin/env python3
"""
Verifier for quarterly_reshape_ribbon task.

Scoring (100 points total):
1. File saved (15 pts): Quarterly_Reshaped.pbix exists on Desktop
2. Append Operation (20 pts): 'Table.Combine' or 'Append' detected in DataMashup
3. Unpivot Operation (25 pts): 'Table.Unpivot' detected in DataMashup
4. Ribbon Chart (20 pts): 'ribbonChart' visual type present
5. Table Visual (20 pts): 'tableEx' visual type present

Pass Threshold: 60 points
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_quarterly_reshape_ribbon(traj, env_info, task_info):
    """
    Verify that the agent appended files, unpivoted columns, and created a ribbon chart.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Retrieve Result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    temp_file.close() # Close so we can write to it
    
    try:
        # Windows path in container -> local temp file
        copy_from_env("C:/Users/Docker/Desktop/reshape_result.json", temp_file.name)
        
        with open(temp_file.name, 'r', encoding='utf-8-sig') as f:
            result = json.load(f)
    except Exception as e:
        logger.error(f"Failed to read result file: {e}")
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "Failed to retrieve verification results from environment."
        }
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []
    
    # 2. Score: File Existence (15 pts)
    if result.get('file_exists') and result.get('file_created_during_task'):
        score += 15
        feedback.append("File 'Quarterly_Reshaped.pbix' saved successfully.")
    elif result.get('file_exists'):
        # Penalize if file existed before task (should not happen due to setup)
        score += 5
        feedback.append("File exists but timestamp check failed.")
    else:
        feedback.append("File 'Quarterly_Reshaped.pbix' not found.")

    # 3. Score: Power Query Transformations (45 pts total)
    mashup_text = result.get('mashup_indicators', '')
    
    # Append Check (20 pts)
    if 'Append_Detected' in mashup_text:
        score += 20
        feedback.append("Power Query: Append operation detected.")
    else:
        feedback.append("Power Query: Append operation NOT detected.")
        
    # Unpivot Check (25 pts)
    if 'Unpivot_Detected' in mashup_text:
        score += 25
        feedback.append("Power Query: Unpivot operation detected.")
    else:
        feedback.append("Power Query: Unpivot operation NOT detected.")

    # 4. Score: Visuals (40 pts total)
    visuals = result.get('visual_types', [])
    
    # Ribbon Chart (20 pts)
    if 'ribbonChart' in visuals:
        score += 20
        feedback.append("Visual: Ribbon Chart created.")
    else:
        feedback.append("Visual: Ribbon Chart NOT found.")
        
    # Table Visual (20 pts)
    if 'tableEx' in visuals or 'pivotTable' in visuals: # Accept Matrix (pivotTable) as close enough substitute for Table (tableEx)
        score += 20
        feedback.append("Visual: Table/Matrix created.")
    else:
        feedback.append("Visual: Table NOT found.")

    # 5. Final Result
    passed = score >= 60
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }