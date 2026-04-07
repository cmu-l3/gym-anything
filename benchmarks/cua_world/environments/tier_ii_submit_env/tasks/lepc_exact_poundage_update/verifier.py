#!/usr/bin/env python3
"""
Verifier for lepc_exact_poundage_update task.

Scoring System (100 points total, Pass Threshold: 70):
- 10 pts: Output file created/exported successfully.
- 15 pts: Sulfuric Acid Exact Max = 8450
- 15 pts: Sulfuric Acid Exact Avg = 6200
- 15 pts: Hydrofluoric Acid Exact Max = 1250
- 15 pts: Hydrofluoric Acid Exact Avg = 800
- 30 pts: Range Code Logic correct (Hydrofluoric Max updated to 04, others remain correct)
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_lepc_exact_poundage_update(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available."}

    metadata = task_info.get('metadata', {})
    result_file = metadata.get('result_file', "C:\\Users\\Docker\\Desktop\\lepc_exact_poundage_result.json")
    pass_threshold = metadata.get('pass_threshold', 70)

    # Copy the JSON result file from the container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env(result_file, temp_file.name)
        with open(temp_file.name, 'r', encoding='utf-8') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read exported results: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 1. Base Checks (File exists and was modified)
    if not result.get("file_exists", False):
        return {"passed": False, "score": 0, "feedback": "Output .t2s file not found. Task not completed."}
    
    if not result.get("file_modified_during_task", False):
        return {"passed": False, "score": 0, "feedback": "Output .t2s file exists but was not modified during the task session. (Anti-gaming check failed)"}

    score = 10
    feedback_parts = ["File successfully exported (+10)"]

    sa = result.get("sulfuric_acid", {})
    hfa = result.get("hydrofluoric_acid", {})

    # 2. Sulfuric Acid Checks
    sa_exact_max = sa.get("exact_max")
    if sa_exact_max == 8450:
        score += 15
        feedback_parts.append("Sulfuric Exact Max correct (+15)")
    else:
        feedback_parts.append(f"Sulfuric Exact Max incorrect (got {sa_exact_max}, expected 8450)")

    sa_exact_avg = sa.get("exact_avg")
    if sa_exact_avg == 6200:
        score += 15
        feedback_parts.append("Sulfuric Exact Avg correct (+15)")
    else:
        feedback_parts.append(f"Sulfuric Exact Avg incorrect (got {sa_exact_avg}, expected 6200)")

    # 3. Hydrofluoric Acid Checks
    hfa_exact_max = hfa.get("exact_max")
    if hfa_exact_max == 1250:
        score += 15
        feedback_parts.append("Hydrofluoric Exact Max correct (+15)")
    else:
        feedback_parts.append(f"Hydrofluoric Exact Max incorrect (got {hfa_exact_max}, expected 1250)")

    hfa_exact_avg = hfa.get("exact_avg")
    if hfa_exact_avg == 800:
        score += 15
        feedback_parts.append("Hydrofluoric Exact Avg correct (+15)")
    else:
        feedback_parts.append(f"Hydrofluoric Exact Avg incorrect (got {hfa_exact_avg}, expected 800)")

    # 4. Range Code Logic
    # Agent should only change HFA max range from 03 to 04. Others stay the same.
    hfa_rm = str(hfa.get("range_max", "")).zfill(2)
    hfa_ra = str(hfa.get("range_avg", "")).zfill(2)
    sa_rm = str(sa.get("range_max", "")).zfill(2)
    sa_ra = str(sa.get("range_avg", "")).zfill(2)

    logic_correct = True
    if hfa_rm != "04":
        logic_correct = False
        feedback_parts.append(f"HFA Max Range Code not updated correctly (got {hfa_rm}, expected 04)")
    if hfa_ra != "03":
        logic_correct = False
        feedback_parts.append(f"HFA Avg Range Code incorrectly changed (got {hfa_ra}, expected 03)")
    if sa_rm != "05" or sa_ra != "05":
        logic_correct = False
        feedback_parts.append("Sulfuric Acid Range Codes incorrectly changed")

    if logic_correct:
        score += 30
        feedback_parts.append("Range Code logic successfully applied (+30)")

    passed = score >= pass_threshold

    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback_parts)
    }