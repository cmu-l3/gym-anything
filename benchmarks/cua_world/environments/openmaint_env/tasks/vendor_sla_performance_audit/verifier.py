#!/usr/bin/env python3
import json
import logging
import os
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_vendor_sla_performance_audit(traj, env_info, task_info):
    """
    Verifies that the agent correctly audited the Work Orders based on the SLA policy.
    """
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Environment copy failed"}

    # 1. Retrieve Result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/sla_audit_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            results = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 2. Define Expected States
    # Format: Code -> {Expected Tag, Explanation}
    expected_logic = {
        "WO-SLA-001": {"tag": "[SLA: COMPLIANT]", "reason": "6h duration (Same day)"},
        "WO-SLA-002": {"tag": "[SLA: BREACHED]", "reason": "24.5h duration (>24h)"},
        "WO-SLA-003": {"tag": "[SLA: COMPLIANT]", "reason": "23h duration (<24h)"},
        "WO-SLA-004": {"tag": "[SLA: BREACHED]", "reason": "32h duration (>24h)"},
        "WO-SLA-005": {"tag": "[SLA: EXEMPT]", "reason": "Waiting for Parts / On Hold"},
        "WO-SLA-006": {"tag": None, "reason": "Still open / No resolution time"}
    }

    score = 0
    max_score = 100
    feedback = []
    
    correct_tags = 0
    total_checks = len(expected_logic)

    # 3. Evaluate Each Ticket
    for code, criteria in expected_logic.items():
        data = results.get(code, {})
        if data.get("error"):
            feedback.append(f"{code}: Failed (Ticket missing or deleted)")
            continue

        description = data.get("Description", "").strip()
        expected_tag = criteria["tag"]

        if expected_tag is None:
            # Should NOT have any SLA tag
            if "[SLA:" in description:
                feedback.append(f"{code}: Failed. Tagged '{description[:15]}...' but should be untouched.")
            else:
                score += 15 # 15 pts for skipping active ticket correctly
                correct_tags += 1
                feedback.append(f"{code}: Passed (Correctly skipped)")
        else:
            # Check if description STARTS with the tag
            if description.startswith(expected_tag):
                # Points distribution
                if code == "WO-SLA-005":
                    score += 25 # High value for exception handling
                else:
                    score += 15 # Standard value for math logic
                
                correct_tags += 1
                feedback.append(f"{code}: Passed ({expected_tag})")
            else:
                # Partial check: did they put the tag somewhere else?
                if expected_tag in description:
                    score += 5 # Pity points for wrong format
                    feedback.append(f"{code}: Partial. Tag found but not at start.")
                else:
                    feedback.append(f"{code}: Failed. Expected {expected_tag}, found: '{description[:20]}...'")

    # 4. Anti-Gaming Check (Did they actually modify the records?)
    # We check if *any* description has changed from the seeded version?
    # Actually, the verifier above checks if the Description *contains* the tag.
    # The Setup seeded descriptions WITHOUT tags.
    # So if the tag is present, they must have modified it.
    # We trust the logic check.

    # 5. Final Calculation
    # Total possible: 15*4 (60) + 25 (Exception) + 15 (Skip) = 100.
    
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": "\n".join(feedback)
    }