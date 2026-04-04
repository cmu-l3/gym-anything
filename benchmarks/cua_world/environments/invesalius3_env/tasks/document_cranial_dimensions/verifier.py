#!/usr/bin/env python3
"""
Verifier for document_cranial_dimensions task.

Scoring System (100 points total):
1. Text Report (55 pts):
   - Exists and created during task: 10 pts
   - Contains at least 2 numeric values: 15 pts
   - Contains a valid "Length" value (150-210 mm): 15 pts
   - Contains a valid "Breadth" value (120-175 mm): 15 pts

2. Project File (45 pts):
   - Exists and valid .inv3 format: 15 pts
   - Contains at least 2 measurements: 20 pts
   - Created during task (anti-gaming): 10 pts

Pass Threshold: 60 points
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_document_cranial_dimensions(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load metadata
    metadata = task_info.get('metadata', {})
    min_len = metadata.get('min_length_mm', 150.0)
    max_len = metadata.get('max_length_mm', 210.0)
    min_breadth = metadata.get('min_breadth_mm', 120.0)
    max_breadth = metadata.get('max_breadth_mm', 175.0)

    # Fetch result
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

    score = 0
    feedback_parts = []
    
    # --- Check 1: Text Report ---
    values = result.get("extracted_values", [])
    
    if result.get("report_exists") and result.get("report_created_during_task"):
        score += 10
        feedback_parts.append("Report file created")
        
        # Check for values
        if len(values) >= 2:
            score += 15
            feedback_parts.append(f"Found {len(values)} numeric values")
            
            # Check for anatomically plausible values
            # We don't know which is length vs breadth, so we check if ANY pair satisfies the criteria
            has_length = any(min_len <= v <= max_len for v in values)
            has_breadth = any(min_breadth <= v <= max_breadth for v in values)
            
            # Anti-gaming: Ensure length and breadth are not the exact same number (unless skull is perfectly spherical, unlikely)
            distinct_values = len(set(values)) >= 2
            
            if has_length:
                score += 15
                feedback_parts.append("Valid cranial length found")
            else:
                feedback_parts.append(f"No value in length range ({min_len}-{max_len}mm)")
                
            if has_breadth:
                score += 15
                feedback_parts.append("Valid cranial breadth found")
            else:
                feedback_parts.append(f"No value in breadth range ({min_breadth}-{max_breadth}mm)")
                
            if not distinct_values:
                score -= 10
                feedback_parts.append("WARN: Recorded values are identical (improbable)")
                
        else:
            feedback_parts.append("Report does not contain enough numeric data")
    else:
        feedback_parts.append("Report file missing or not created during task")

    # --- Check 2: Project File ---
    if result.get("project_exists") and result.get("project_created_during_task"):
        score += 10 # Timestamp check
        
        if result.get("project_valid_inv3"):
            score += 15
            feedback_parts.append("Valid project file saved")
            
            meas_count = result.get("measurement_count", 0)
            if meas_count >= 2:
                score += 20
                feedback_parts.append(f"Project contains {meas_count} measurements")
            else:
                feedback_parts.append(f"Project has too few measurements ({meas_count}/2)")
        else:
            feedback_parts.append("Project file is corrupt or invalid format")
    else:
        feedback_parts.append("Project file missing or not saved during task")

    return {
        "passed": score >= 60,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }