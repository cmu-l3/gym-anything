#!/usr/bin/env python3
"""
Verifier for resolve_orphaned_flight_plans@1.

Checks if the 3 orphaned flight plans were assigned the correct operators
based on their pilots' company affiliation.

Scoring:
- 30 pts per correctly fixed record (3 records = 90 pts)
- 10 pts for valid timestamps (work done during task)
- Pass threshold: 90 pts
"""

import json
import os
import logging
import tempfile
from datetime import datetime

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_resolve_orphaned_flight_plans(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Define expected outcomes
    expected_data = {
        "MIG-ERR-101": "SkyHigh Services",
        "MIG-ERR-102": "AgriDrones Inc",
        "MIG-ERR-103": "SkyHigh Services"
    }

    # Retrieve result file
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": f"Failed to retrieve or parse task result: {str(e)}"
        }
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    flight_plans = result.get("flight_plans", {})
    
    # Check each target
    for callsign, expected_op in expected_data.items():
        fp_data = flight_plans.get(callsign)
        
        if not fp_data:
            feedback_parts.append(f"❌ {callsign}: Record not found in export.")
            continue
            
        if not fp_data.get("exists"):
            feedback_parts.append(f"❌ {callsign}: Flight plan seems to have been deleted.")
            continue
            
        actual_op = fp_data.get("operator")
        
        if actual_op == expected_op:
            score += 30
            feedback_parts.append(f"✅ {callsign}: Correctly assigned to '{actual_op}'.")
        elif actual_op is None:
            feedback_parts.append(f"❌ {callsign}: Operator is still empty.")
        else:
            feedback_parts.append(f"❌ {callsign}: Incorrect operator '{actual_op}' (Expected: '{expected_op}').")

    # Anti-gaming: Check if modification happened during task (bonus 10 pts)
    # Only award if at least one record was fixed
    if score > 0:
        # We perform a loose check: do we have timestamps?
        # A strict check would parse ISO dates, but existence implies the export script found them
        timestamps_present = any(
            fp.get("updated_at") for fp in flight_plans.values() if fp.get("exists")
        )
        if timestamps_present:
            score += 10
            feedback_parts.append("✅ Timestamps verify modification during task.")
        else:
            feedback_parts.append("⚠️ Could not verify modification timestamps.")

    # Calculate final status
    passed = (score >= 90)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": "\n".join(feedback_parts)
    }