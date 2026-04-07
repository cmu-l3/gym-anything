#!/usr/bin/env python3
"""
Verifier for emergency_flood_response_asset_triage task.
"""

import json
import logging
import os
import tempfile
import sys

# Setup Logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_emergency_flood_response_asset_triage(traj, env_info, task_info):
    """
    Verifies that the agent correctly tagged assets and created the work order.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Retrieve Result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/flood_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []

    # Expected Configuration
    assets = result.get("assets", {})
    
    # 1. Check RELOCATE Tags (30 pts)
    relocate_targets = ["AST-SRV-B01", "AST-ARCH-B01", "AST-UPS-B01"]
    relocate_hits = 0
    for code in relocate_targets:
        desc = assets.get(code, {}).get("description", "")
        if "[RELOCATE]" in desc:
            relocate_hits += 1
        elif "[PROTECT]" in desc:
            feedback.append(f"Wrong tag on {code}: found [PROTECT], expected [RELOCATE]")
    
    score += relocate_hits * 10
    feedback.append(f"Relocate Tags: {relocate_hits}/3 found")

    # 2. Check PROTECT Tags (20 pts)
    # Note: Sump Pump is the trap - it's mechanical AND critical
    protect_targets = ["AST-PUMP-MAIN", "AST-PUMP-SUMP"]
    protect_hits = 0
    for code in protect_targets:
        desc = assets.get(code, {}).get("description", "")
        if "[PROTECT]" in desc:
            protect_hits += 1
        elif "[RELOCATE]" in desc:
            feedback.append(f"Wrong tag on {code}: found [RELOCATE], expected [PROTECT]")
    
    score += protect_hits * 10
    feedback.append(f"Protect Tags: {protect_hits}/2 found")

    # 3. Check Furniture (15 pts) - Should NOT be tagged
    desk_desc = assets.get("AST-DESK-B01", {}).get("description", "")
    if "[RELOCATE]" in desk_desc or "[PROTECT]" in desk_desc:
        feedback.append("Furniture was incorrectly tagged!")
    else:
        score += 15
        feedback.append("Furniture correctly ignored")

    # 4. Sump Pump Trap Specific Check (15 pts)
    # Already awarded 10 pts in step 2 if correct, but this adds bonus for NOT moving it
    # Actually, the rubric says:
    # - Relocation Tags: 30
    # - Protection Tags: 20
    # - Furniture: 15
    # - Sump Pump Trap: 15 (Sump pump is [PROTECT] NOT [RELOCATE])
    # So if step 2 gave points for [PROTECT], this step confirms it wasn't [RELOCATE]
    
    sump_desc = assets.get("AST-PUMP-SUMP", {}).get("description", "")
    if "[PROTECT]" in sump_desc and "[RELOCATE]" not in sump_desc:
        score += 15
        feedback.append("Sump Pump correctly identified as exception (Protect-in-place)")
    elif "[RELOCATE]" in sump_desc:
        # Step 2 gave 0 points for this asset, so we just miss these 15 too.
        feedback.append("Sump Pump incorrectly tagged for relocation (Trap failed)")

    # 5. Work Order Check (20 pts)
    wo = result.get("work_order")
    if wo:
        prio = wo.get("priority", "").lower()
        if "critical" in prio or "high" in prio or "urgent" in prio:
            score += 20
            feedback.append("Critical Work Order created successfully")
        else:
            score += 10
            feedback.append(f"Work Order created but priority '{prio}' is not Critical (Partial credit)")
    else:
        feedback.append("No Flood-related Work Order found")

    # Final tally
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }