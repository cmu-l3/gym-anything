#!/usr/bin/env python3
import json
import os
import tempfile
import logging

# Configure logging
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)

def verify_rep_scorecard(traj, env_info, task_info):
    """
    Verify the Rep Performance Scorecard task.
    
    Success Criteria (100 points):
    1. File saved & valid (10 pts)
    2. Calculated Column: Margin_Per_Unit (15 pts)
    3. Calculated Column: Performance_Tier (15 pts)
    4. Visual: Table present (15 pts)
    5. Visual: Gauge present (15 pts)
    6. Conditional Formatting applied to table (15 pts)
    7. Gauge Target configured (15 pts)
    
    Pass Threshold: 70 points
    """
    
    # 1. Retrieve result JSON from the environment
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Error: copy_from_env function not available in environment."
        }

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    temp_file.close()
    
    try:
        # Path matches where export_result.ps1 saved it
        copy_from_env("C:\\Users\\Docker\\Desktop\\rep_scorecard_result.json", temp_file.name)
        
        with open(temp_file.name, 'r', encoding='utf-8') as f:
            result = json.load(f)
            
    except Exception as e:
        logger.error(f"Failed to retrieve or parse result file: {e}")
        return {
            "passed": False,
            "score": 0,
            "feedback": "Failed to retrieve verification results from the environment."
        }
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 2. Evaluate Score
    score = 0
    feedback_parts = []
    
    # Check 1: File saved and created during task (10 pts)
    if result.get('file_exists') and result.get('file_created_during_task'):
        score += 10
        feedback_parts.append("File 'Rep_Scorecard.pbix' saved correctly.")
    elif result.get('file_exists'):
        score += 5
        feedback_parts.append("File exists but timestamp verification failed (possible pre-existing file).")
    else:
        feedback_parts.append("File 'Rep_Scorecard.pbix' not found.")

    # Check 2 & 3: Calculated Columns (30 pts)
    found_cols = result.get('calculated_columns_found', [])
    if "Margin_Per_Unit" in found_cols:
        score += 15
        feedback_parts.append("Calculated column 'Margin_Per_Unit' found.")
    else:
        feedback_parts.append("Missing column 'Margin_Per_Unit'.")
        
    if "Performance_Tier" in found_cols:
        score += 15
        feedback_parts.append("Calculated column 'Performance_Tier' found.")
    else:
        feedback_parts.append("Missing column 'Performance_Tier'.")

    # Check 4: Table Visual (15 pts)
    visuals = result.get('visual_types', [])
    if "tableEx" in visuals:
        score += 15
        feedback_parts.append("Table visual found.")
    else:
        feedback_parts.append("Table visual missing.")

    # Check 5: Gauge Visual (15 pts)
    if "gauge" in visuals:
        score += 15
        feedback_parts.append("Gauge visual found.")
    else:
        feedback_parts.append("Gauge visual missing.")

    # Check 6: Conditional Formatting (15 pts)
    if result.get('conditional_formatting_found'):
        score += 15
        feedback_parts.append("Conditional formatting detected.")
    else:
        feedback_parts.append("Conditional formatting not detected in table.")

    # Check 7: Gauge Target (15 pts)
    if result.get('gauge_target_found'):
        score += 15
        feedback_parts.append("Gauge target configuration detected.")
    else:
        feedback_parts.append("Gauge target not configured.")

    # 3. Determine Pass/Fail
    # Pass if score >= 70 AND critical components (file + cols + at least one visual) exist
    passed = (score >= 70)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback_parts)
    }