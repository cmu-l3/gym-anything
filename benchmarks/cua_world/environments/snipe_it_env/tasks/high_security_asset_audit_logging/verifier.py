#!/usr/bin/env python3
"""
Verifier for high_security_asset_audit_logging task.

Scoring breakdown (100 points total):
- C1 (30 pts): SEC-LPT-01, 02, 03 successfully audited via the Audit module.
- C2 (15 pts): SEC-LPT-01, 02, 03, 04 Next Audit Date set to 2026-06-08.
- C3 (15 pts): SEC-LPT-04 audited successfully.
- C4 (15 pts): SEC-LPT-04 location properly updated to SCIF Bravo.
- C5 (20 pts): SEC-LPT-05 status changed to Lost/Stolen (and NOT audited).
- C6 (5 pts): No collateral damage (no other assets audited).
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)

RESULT_PATH = "/tmp/high_security_asset_audit_logging_result.json"


def verify_high_security_audit(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function unavailable"}

    try:
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env(RESULT_PATH, temp_file.name)
            with open(temp_file.name, 'r') as f:
                result = json.load(f)
        finally:
            os.unlink(temp_file.name)
    except FileNotFoundError:
        return {"passed": False, "score": 0, "feedback": "Result file not found in VM."}
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Error reading result: {e}"}

    score = 0
    feedback = []
    assets = result.get("assets", {})

    # --- Do-nothing check ---
    any_action_taken = False
    for tag in ["SEC-LPT-01", "SEC-LPT-02", "SEC-LPT-03", "SEC-LPT-04", "SEC-LPT-05"]:
        asset = assets.get(tag, {})
        if asset.get("audited") or asset.get("status") == "Lost/Stolen":
            any_action_taken = True
            break
    
    if not any_action_taken:
        return {"passed": False, "score": 0, "feedback": "DO-NOTHING: No target assets were audited or modified."}

    # --- C1: SEC-LPT-01, 02, 03 standard audits (30 pts) ---
    c1_tags = ["SEC-LPT-01", "SEC-LPT-02", "SEC-LPT-03"]
    c1_audited_count = sum(1 for tag in c1_tags if assets.get(tag, {}).get("audited", False))
    
    if c1_audited_count == 3:
        score += 30
        feedback.append("C1: SEC-LPT-01, 02, and 03 correctly audited (+30)")
    else:
        pts = c1_audited_count * 10
        score += pts
        feedback.append(f"C1: {c1_audited_count}/3 standard assets audited (+{pts})")

    # --- C2: Next Audit Dates set to 2026-06-08 (15 pts) ---
    c2_tags = ["SEC-LPT-01", "SEC-LPT-02", "SEC-LPT-03", "SEC-LPT-04"]
    c2_date_count = 0
    for tag in c2_tags:
        next_date = assets.get(tag, {}).get("next_audit_date", "")
        if "2026-06-08" in next_date:
            c2_date_count += 1
            
    if c2_date_count == 4:
        score += 15
        feedback.append("C2: All 4 audited assets have Next Audit Date = 2026-06-08 (+15)")
    else:
        pts = int(15 * (c2_date_count / 4))
        score += pts
        feedback.append(f"C2: {c2_date_count}/4 Next Audit Dates correctly set to 2026-06-08 (+{pts})")

    # --- C3: SEC-LPT-04 audited (15 pts) ---
    lpt04 = assets.get("SEC-LPT-04", {})
    if lpt04.get("audited"):
        score += 15
        feedback.append("C3: SEC-LPT-04 correctly audited (+15)")
    else:
        feedback.append("C3: SEC-LPT-04 was NOT audited (+0)")

    # --- C4: SEC-LPT-04 location updated to SCIF Bravo (15 pts) ---
    if lpt04.get("location") == "SCIF Bravo":
        score += 15
        feedback.append("C4: SEC-LPT-04 location correctly updated to SCIF Bravo (+15)")
    else:
        feedback.append(f"C4: SEC-LPT-04 location is '{lpt04.get('location', 'unknown')}', expected 'SCIF Bravo' (+0)")

    # --- C5: SEC-LPT-05 marked Lost/Stolen and NOT audited (20 pts) ---
    lpt05 = assets.get("SEC-LPT-05", {})
    if lpt05.get("status") == "Lost/Stolen":
        if not lpt05.get("audited"):
            score += 20
            feedback.append("C5: SEC-LPT-05 correctly marked Lost/Stolen and bypassed audit (+20)")
        else:
            score += 10
            feedback.append("C5: SEC-LPT-05 marked Lost/Stolen, but incorrectly audited anyway (+10)")
    else:
        feedback.append(f"C5: SEC-LPT-05 status is '{lpt05.get('status', 'unknown')}', expected 'Lost/Stolen' (+0)")

    # --- C6: No collateral damage (5 pts) ---
    collateral = int(result.get("collateral_audits", 0))
    if collateral == 0:
        score += 5
        feedback.append("C6: No collateral assets were audited (+5)")
    else:
        feedback.append(f"C6: {collateral} unrelated assets were improperly audited (+0)")

    passed = score >= 75 and c1_audited_count > 0 and lpt04.get("audited") and (lpt05.get("status") == "Lost/Stolen")
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }