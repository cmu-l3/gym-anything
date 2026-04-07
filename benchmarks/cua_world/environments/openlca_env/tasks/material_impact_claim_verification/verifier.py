#!/usr/bin/env python3
"""
Verifier for Material Impact Claim Verification task.

Scoring Breakdown (100 pts):
1.  **Output File Exists & Created (20 pts)**: `claim_verification.txt` created during task.
2.  **Database & Method Setup (20 pts)**: USLCI DB imported (>15MB) AND Impact Categories > 0.
3.  **Product System Modeling (20 pts)**: At least one product system created (DB check).
4.  **Accurate Calculation (20 pts)**: Reported US average is reasonable (approx 4.0 - 20.0 kg CO2e). 
    *Note: Primary aluminum is high impact (~8-10 kg).*
5.  **Correct Verdict (20 pts)**: File contains "REJECTED" (since ~8.0 is not within 20% of 2.0).
"""

import json
import os
import tempfile
import logging
import re

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_material_impact_claim(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env missing"}

    # Load result
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
    feedback = []

    # Metadata thresholds
    metadata = task_info.get('metadata', {})
    min_val = metadata.get('expected_us_avg_min', 4.0)
    max_val = metadata.get('expected_us_avg_max', 20.0)

    # 1. File Check (20 pts)
    if result.get('file_exists') and result.get('file_created_during_task'):
        score += 20
        feedback.append("Report file created successfully.")
    elif result.get('file_exists'):
        score += 10
        feedback.append("Report file exists but timestamp is old.")
    else:
        feedback.append("Report file not found.")

    # 2. Database & Method Setup (20 pts)
    db_ok = result.get('db_found', False)
    cats_ok = result.get('impact_category_count', 0) > 0
    if db_ok and cats_ok:
        score += 20
        feedback.append("USLCI database and LCIA methods imported.")
    elif db_ok:
        score += 10
        feedback.append("Database imported but no impact methods found.")
    else:
        feedback.append("No valid database found.")

    # 3. Product System Modeling (20 pts)
    ps_count = result.get('product_system_count', 0)
    if ps_count >= 1:
        score += 20
        feedback.append("Product system created.")
    else:
        feedback.append("No product system created.")

    # 4. Calculation Accuracy (20 pts)
    raw_value = result.get('parsed_value', '')
    val_ok = False
    try:
        if raw_value:
            val = float(raw_value)
            if min_val <= val <= max_val:
                score += 20
                val_ok = True
                feedback.append(f"Calculated value {val} is within expected range ({min_val}-{max_val}).")
            else:
                score += 5
                feedback.append(f"Calculated value {val} is outside expected range ({min_val}-{max_val}).")
        else:
            feedback.append("Could not parse a numeric value from the report.")
    except ValueError:
        feedback.append("Invalid number format in report.")

    # 5. Verdict Check (20 pts)
    verdict = result.get('verdict_found', '')
    if verdict == "REJECTED":
        score += 20
        feedback.append("Correct verdict: REJECTED.")
    elif verdict == "CONFIRMED":
        feedback.append("Incorrect verdict: CONFIRMED (US average is significantly higher than 2.0).")
    else:
        feedback.append("No valid verdict found (expected 'VERDICT: REJECTED').")

    passed = score >= 80  # Requires most steps to be correct
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }