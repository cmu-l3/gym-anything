#!/usr/bin/env python3
"""
Verifier for enable_tracking_codes task.

Criteria:
1. Tracking Codes module must be enabled (visible in sidebar/nav).
2. Three specific tracking codes must exist: Sales, Warehouse, Administration.
3. Scoring:
   - Module enabled: 25 pts
   - "Sales" code: 25 pts
   - "Warehouse" code: 25 pts
   - "Administration" code: 25 pts
   
Anti-gaming:
- Checks if the module was already enabled at start (from setup metadata).
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_enable_tracking_codes(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Temp files for results
    res_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    init_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    
    try:
        # Copy task result
        copy_from_env("/tmp/task_result.json", res_file.name)
        with open(res_file.name, 'r') as f:
            result = json.load(f)
            
        # Copy initial state (optional, for anti-gaming)
        initial_state = {}
        try:
            copy_from_env("/tmp/initial_state.json", init_file.name)
            with open(init_file.name, 'r') as f:
                initial_state = json.load(f)
        except Exception:
            logger.warning("Could not read initial state file")

    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result files: {e}"}
    finally:
        if os.path.exists(res_file.name): os.unlink(res_file.name)
        if os.path.exists(init_file.name): os.unlink(init_file.name)

    # Scoring
    score = 0
    feedback = []
    
    # 1. Check Module Enabled
    module_enabled = result.get("module_enabled", False)
    was_enabled_initially = initial_state.get("tracking_enabled", False)
    
    if module_enabled:
        if was_enabled_initially:
            feedback.append("Module was already enabled at start (Anti-gaming penalty)")
            # We don't give points for the module if it was already there, 
            # but we allow points for the codes if they are new (hard to track 'new' without ID diff, 
            # but usually the setup script ensures clean state).
            # If setup failed to disable it, we might still award points if the agent *verified* it or kept it.
            # Ideally, setup script ensures it's disabled.
            score += 0 
        else:
            score += 25
            feedback.append("Tracking Codes module enabled (+25)")
    else:
        feedback.append("Tracking Codes module NOT enabled")

    # 2. Check Codes
    found_codes = result.get("codes_found", [])
    required_codes = ["Sales", "Warehouse", "Administration"]
    
    for code in required_codes:
        if code in found_codes:
            score += 25
            feedback.append(f"Tracking code '{code}' created (+25)")
        else:
            feedback.append(f"Tracking code '{code}' NOT found")

    # Final Check
    passed = (score >= 75)  # Require module + at least 2 codes, or all 3 codes
    
    return {
        "passed": passed,
        "score": score,
        "feedback": "; ".join(feedback)
    }