#!/usr/bin/env python3
"""
Verifier for consolidate_manufacturers task.
Checks database integrity: duplicates removed, canonical exists, aircraft re-linked, no data loss.
"""

import json
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_consolidate_manufacturers(traj, env_info, task_info):
    """
    Verify the manufacturer consolidation task.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Copy result file
    import tempfile
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    score = 0
    feedback_parts = []
    
    # Extract data
    init_count = result.get("initial_aircraft_count", 0)
    final_count = result.get("final_aircraft_count", 0)
    dups_remaining = result.get("duplicates_remaining", -1)
    canonical_exists = result.get("canonical_exists", False)
    test_status = result.get("test_aircraft_status", {})
    
    # 1. Critical Check: Data Loss (30 points)
    # The agent fails immediately if aircraft were deleted (cascade delete).
    if final_count < init_count:
        loss = init_count - final_count
        return {
            "passed": False, 
            "score": 0, 
            "feedback": f"CRITICAL FAILURE: Data Loss Detected. {loss} aircraft records were deleted. You likely deleted the manufacturer before moving the aircraft, causing a cascade delete."
        }
    elif final_count == init_count:
        score += 30
        feedback_parts.append("✓ No aircraft data loss (+30)")
    else:
        # Count increased? Weird but acceptable for this specific constraint
        score += 30
        feedback_parts.append("✓ No aircraft data loss (+30)")

    # 2. Duplicates Removed (20 points)
    if dups_remaining == 0:
        score += 20
        feedback_parts.append("✓ Duplicate manufacturers removed (+20)")
    else:
        names = result.get("remaining_names", [])
        feedback_parts.append(f"✗ {dups_remaining} duplicate(s) still exist: {names}")

    # 3. Canonical Exists (10 points)
    if canonical_exists:
        score += 10
        feedback_parts.append("✓ Canonical manufacturer 'Yuneec International' exists (+10)")
    else:
        feedback_parts.append("✗ Canonical manufacturer 'Yuneec International' is missing!")

    # 4. Aircraft Re-linked (30 points)
    # Check specific test aircraft
    unit_a = test_status.get("unit_a", {})
    unit_b = test_status.get("unit_b", {})
    
    relinked_count = 0
    if unit_a.get("exists") and unit_a.get("is_canonical"):
        relinked_count += 1
    
    if unit_b.get("exists") and unit_b.get("is_canonical"):
        relinked_count += 1
        
    if relinked_count == 2:
        score += 30
        feedback_parts.append("✓ All test aircraft correctly re-assigned to canonical manufacturer (+30)")
    elif relinked_count == 1:
        score += 15
        feedback_parts.append("~ Only 1/2 test aircraft correctly re-assigned (+15)")
    else:
        feedback_parts.append("✗ Test aircraft were not re-assigned to 'Yuneec International'")

    # 5. Clean State (10 points)
    # Full points if everything else is perfect
    if score == 90:
        score += 10
        feedback_parts.append("✓ Clean execution (+10)")

    passed = score >= 80
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }