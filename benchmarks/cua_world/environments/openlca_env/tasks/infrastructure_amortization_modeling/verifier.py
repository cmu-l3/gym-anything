#!/usr/bin/env python3
import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_infrastructure_amortization(traj, env_info, task_info):
    """
    Verify the infrastructure amortization modeling task.
    
    Scoring Criteria:
    1. Output CSV exists and created during task (10 pts)
    2. 'Wind Turbine Construction' process created in DB (25 pts)
    3. 'Wind Electricity Generation' process created in DB (25 pts)
    4. Amortization factor (~1.25e-8) found in DB exchanges (40 pts)
    
    Total: 100 pts. Pass threshold: 60 pts.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Retrieve metadata
    metadata = task_info.get('metadata', {})
    
    # Copy result file
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []

    # Criterion 1: Output File (10 pts)
    if result.get("output_exists") and result.get("file_created_during_task"):
        score += 10
        feedback_parts.append("Output CSV exported successfully.")
    elif result.get("output_exists"):
        score += 5
        feedback_parts.append("Output CSV exists but timestamp check failed.")
    else:
        feedback_parts.append("Output CSV not found.")

    # Criterion 2: Construction Process (25 pts)
    if result.get("process_construction_found"):
        score += 25
        feedback_parts.append("Construction process found in database.")
    else:
        feedback_parts.append("Construction process NOT found.")

    # Criterion 3: Generation Process (25 pts)
    if result.get("process_generation_found"):
        score += 25
        feedback_parts.append("Generation process found in database.")
    else:
        feedback_parts.append("Generation process NOT found.")

    # Criterion 4: Amortization Factor (40 pts)
    # This is the math check: 1 / (20 * 4,000,000) = 1.25e-8
    if result.get("amortization_factor_found"):
        score += 40
        feedback_parts.append("Correct amortization factor (1.25e-8) found in database link.")
    else:
        feedback_parts.append("Correct amortization factor NOT found in database.")

    # Final Verification
    passed = score >= 60
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }