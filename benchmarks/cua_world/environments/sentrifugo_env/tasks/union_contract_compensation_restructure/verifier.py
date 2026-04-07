#!/usr/bin/env python3
"""
Verifier for union_contract_compensation_restructure task.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_union_contract_compensation_restructure(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load export data: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    paygrades = result.get("paygrades", [])
    components = result.get("components", [])
    emp013_pg = result.get("emp013_pg", "")
    emp018_pg = result.get("emp018_pg", "")

    tier2_id = None
    if paygrades:
        pg = paygrades[0]
        tier2_id = str(pg.get("id", ""))
        score += 15
        feedback_parts.append("Pay Grade 'Technician - Tier 2' created")
        
        min_sal = float(pg.get("min", 0))
        max_sal = float(pg.get("max", 0))
        if min_sal == 50000 and max_sal == 70000:
            score += 15
            feedback_parts.append("Pay Grade bounds correct ($50k - $70k)")
        else:
            feedback_parts.append(f"Pay Grade bounds incorrect (min: {min_sal}, max: {max_sal})")
    else:
        feedback_parts.append("Pay Grade 'Technician - Tier 2' missing")

    shift_diff = next((c for c in components if c.get("name") == "Shift Differential"), None)
    if shift_diff:
        ctype = str(shift_diff.get("type", "")).lower()
        # Allows robust matching of expected Sentrifugo representations for componenttypes
        if ctype in ['1', 'earning', 'earnings']:
            score += 15
            feedback_parts.append("Earning Component 'Shift Differential' created and typed correctly")
        else:
            score += 7
            feedback_parts.append(f"Component 'Shift Differential' created but type is '{ctype}' (expected Earning)")
    else:
        feedback_parts.append("Component 'Shift Differential' missing")

    union_dues = next((c for c in components if c.get("name") == "Union Dues - Local 104"), None)
    if union_dues:
        ctype = str(union_dues.get("type", "")).lower()
        if ctype in ['2', 'deduction', 'deductions']:
            score += 15
            feedback_parts.append("Deduction Component 'Union Dues - Local 104' created and typed correctly")
        else:
            score += 7
            feedback_parts.append(f"Component 'Union Dues - Local 104' created but type is '{ctype}' (expected Deduction)")
    else:
        feedback_parts.append("Component 'Union Dues - Local 104' missing")

    if tier2_id:
        if str(emp013_pg) == tier2_id:
            score += 20
            feedback_parts.append("EMP013 assigned to new Pay Grade")
        else:
            feedback_parts.append(f"EMP013 NOT assigned to new Pay Grade (actual: {emp013_pg})")
            
        if str(emp018_pg) == tier2_id:
            score += 20
            feedback_parts.append("EMP018 assigned to new Pay Grade")
        else:
            feedback_parts.append(f"EMP018 NOT assigned to new Pay Grade (actual: {emp018_pg})")
    else:
        feedback_parts.append("Employees could not be verified (Pay Grade missing)")

    passed = score >= 70
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }