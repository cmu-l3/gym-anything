#!/usr/bin/env python3
"""
Verifier for power_dependency_mapping task.

Checks:
1. Five specific relations exist between the electrical CIs.
2. All original CIs are preserved (not deleted).
3. "Do Nothing" check (score 0 if no relations found).
"""

import json
import logging
import os
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

REQUIRED_RELATIONS = [
    ("ELEC-XFMR-001", "ELEC-SWGR-001", 20),
    ("ELEC-SWGR-001", "ELEC-DP-001", 20),
    ("ELEC-SWGR-001", "ELEC-DP-002", 15),
    ("ELEC-SWGR-001", "ELEC-ATS-001", 15),
    ("ELEC-ATS-001", "ELEC-UPS-001", 15)
]

def verify_power_dependency_mapping(traj, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Retrieve result file
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
    
    # Check 1: Anti-gaming "Do Nothing"
    # If no relations found between our CIs, score is 0 regardless of preservation
    found_rels = result.get("relations_found", [])
    if not found_rels:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "No relationships found between the electrical CIs. Did you save the changes?"
        }

    # Helper: Normalize relations for checking
    # Some domains are bidirectional. We accept A->B or B->A.
    # We create a set of frozensets or sorted tuples if direction doesn't matter,
    # but strictly speaking power is directed. However, to be robust against schema,
    # we'll accept either direction.
    existing_pairs = set()
    for r in found_rels:
        # Store both directions to allow flexible matching
        existing_pairs.add((r['src'], r['dst']))
        existing_pairs.add((r['dst'], r['src']))

    # Check 2: Verify specific relations
    for src, dst, pts in REQUIRED_RELATIONS:
        if (src, dst) in existing_pairs:
            score += pts
            feedback.append(f"[PASS] Link {src} <-> {dst} found (+{pts})")
        else:
            feedback.append(f"[FAIL] Link {src} -> {dst} MISSING")

    # Check 3: Preservation of CIs (15 pts)
    # All 6 CIs must exist and be active
    cis_found = result.get("cis_found", {})
    all_cis_ok = True
    if len(cis_found) < 6:
        all_cis_ok = False
    else:
        for code, info in cis_found.items():
            if not info.get("exists") or not info.get("active"):
                all_cis_ok = False
                feedback.append(f"CI {code} was deleted or deactivated")
                break
    
    if all_cis_ok:
        score += 15
        feedback.append("[PASS] All CIs preserved (+15)")
    else:
        feedback.append("[FAIL] Some CIs were deleted/modified (-15)")

    # Final tally
    passed = score >= 60
    
    return {
        "passed": passed,
        "score": score,
        "feedback": "\n".join(feedback)
    }