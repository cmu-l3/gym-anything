#!/usr/bin/env python3
"""
Verifier for confidential_location_ehs_security task.

Scoring System (100 Points Total, Passing threshold >= 70 AND Chlorine MUST be confidential):
- File Output Saved: 10 pts
- Facility Status Update (Unmanned & Occupants = 0): 20 pts (10+10)
- Chlorine EHS Confidentiality Configured: 30 pts (CRITICAL PASS REQUIREMENT)
- Sodium Hypochlorite Added With Valid Config: 20 pts
- Sodium Hypochlorite Public Integrity (NOT Confidential): 20 pts
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_confidential_location_ehs_security(traj, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get("metadata", {})
    result_file = metadata.get("result_file", "C:\\Users\\Docker\\Desktop\\confidential_location_result.json")
    pass_threshold = metadata.get("pass_threshold", 70)

    tmp = tempfile.NamedTemporaryFile(suffix=".json", delete=False)
    try:
        copy_from_env(result_file, tmp.name)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Export file not found: {e}"}

    try:
        with open(tmp.name, "r", encoding="utf-8-sig") as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Could not parse result JSON: {e}"}
    finally:
        try:
            os.unlink(tmp.name)
        except Exception:
            pass

    if not result.get("file_exists", False):
        return {"passed": False, "score": 0, "feedback": "Output .t2s file not found at expected path (do-nothing detected)."}

    score = 10
    fb = ["PASS: Output file saved (+10)"]

    # 1. Operational status and max occupants (20 pts)
    manned = result.get("manned", "")
    max_occ = result.get("max_occupants", "")
    
    if manned in ["false", "0", "unmanned", "no"]:
        score += 10
        fb.append("PASS: Operational status set to Unmanned (+10)")
    else:
        fb.append(f"FAIL: Operational status not Unmanned (got '{manned}')")

    if max_occ == "0":
        score += 10
        fb.append("PASS: Max occupants set to 0 (+10)")
    else:
        fb.append(f"FAIL: Max occupants not 0 (got '{max_occ}')")

    # 2. EHS Confidentiality - Chlorine (30 pts)
    chlorine_conf = result.get("chlorine_confidential", False)
    if chlorine_conf is True:
        score += 30
        fb.append("PASS: Chlorine storage location marked Confidential (+30)")
    else:
        fb.append("FAIL: Chlorine storage location NOT marked Confidential")

    # 3. New Chemical Added - Sodium Hypochlorite (20 pts)
    sod_hypo_added = result.get("sodium_hypo_added", False)
    if sod_hypo_added:
        chem_score = 5
        fb.append("PASS: Sodium Hypochlorite added (+5)")
        
        if result.get("sodium_hypo_liquid"):
            chem_score += 5
        if abs(result.get("sodium_hypo_max", 0) - 15000) < 100:
            chem_score += 5
        if abs(result.get("sodium_hypo_avg", 0) - 10000) < 100:
            chem_score += 5
            
        score += chem_score
        fb.append(f"PASS: Sodium Hypo correct quantities/state (+{chem_score-5})")
    else:
        fb.append("FAIL: Sodium Hypochlorite (CAS 7681-52-9) not added")

    # 4. Public Integrity - Sodium Hypochlorite storage NOT confidential (20 pts)
    sod_hypo_conf = result.get("sodium_hypo_confidential", None)
    if sod_hypo_added:
        if sod_hypo_conf is False or sod_hypo_conf is None:
            score += 20
            fb.append("PASS: Sodium Hypochlorite storage correctly NOT confidential (+20)")
        else:
            fb.append("FAIL: Sodium Hypochlorite storage incorrectly marked confidential")
    else:
        fb.append("FAIL: Cannot verify Sodium Hypo confidentiality (chemical missing)")

    # Chlorine confidential requirement represents a critical security issue - fail whole task if not done
    passed = (score >= pass_threshold) and chlorine_conf is True
    
    if score >= pass_threshold and not chlorine_conf:
        fb.append("CRITICAL FAIL: Score met threshold but Chlorine was NOT marked confidential (Security violation).")

    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(fb),
    }