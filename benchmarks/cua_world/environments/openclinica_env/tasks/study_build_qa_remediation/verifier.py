#!/usr/bin/env python3
"""Verifier for study_build_qa_remediation task."""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)

def verify_qa_remediation(traj, env_info, task_info):
    """
    Verify study_build_qa_remediation task completion.
    
    Scoring Breakdown (100 Points Total):
    - Study Phase Corrected to 'Phase II' (20 pts)
    - Baseline Visit repeating flag set to false (20 pts)
    - AE Report type set to 'Unscheduled' (20 pts)
    - Demographics CRF removed from Week 8 (20 pts)
    - Vital Signs CRF assigned to Screening (20 pts)
    - Audit log penalty (-100 pts) if no GUI interaction detected
    
    Pass Threshold: 80 points (Must get at least 4 out of 5 fixes correct)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # --- Read Results from Environment ---
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/qa_remediation_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except FileNotFoundError:
        return {"passed": False, "score": 0, "feedback": "Result file not found — export script did not run"}
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # --- Verify Integrity Nonce ---
    nonce_temp = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
    try:
        copy_from_env("/tmp/result_nonce", nonce_temp.name)
        with open(nonce_temp.name, 'r') as f:
            expected_nonce = f.read().strip()
    except Exception:
        expected_nonce = ""
    finally:
        if os.path.exists(nonce_temp.name):
            os.unlink(nonce_temp.name)

    result_nonce = result.get('result_nonce', '')
    if expected_nonce and result_nonce != expected_nonce:
        return {
            "passed": False,
            "score": 0,
            "feedback": "INTEGRITY FAIL: Result file nonce mismatch — possible tampering"
        }

    score = 0
    feedback_parts = []

    # --- Criterion 1: Study Phase (20 pts) ---
    phase = result.get('study_phase', '').lower()
    if 'phase ii' in phase:
        score += 20
        feedback_parts.append("✅ Study Phase corrected to Phase II")
    else:
        feedback_parts.append(f"❌ Study Phase is '{phase}' (expected 'Phase II')")

    # --- Criterion 2: Baseline Repeating (20 pts) ---
    repeating = result.get('baseline_repeating', '').lower().strip()
    if repeating in ['false', 'f', '0', 'no']:
        score += 20
        feedback_parts.append("✅ Baseline Visit set to Non-repeating")
    else:
        feedback_parts.append(f"❌ Baseline Visit repeating is '{repeating}' (expected Non-repeating)")

    # --- Criterion 3: AE Type (20 pts) ---
    ae_type = result.get('ae_type', '').lower().strip()
    if 'unscheduled' in ae_type:
        score += 20
        feedback_parts.append("✅ Adverse Event Report set to Unscheduled")
    else:
        feedback_parts.append(f"❌ Adverse Event Report type is '{ae_type}' (expected 'Unscheduled')")

    # --- Criterion 4A: Demographics removed from Week 8 (20 pts) ---
    demo_wk8_status = int(result.get('demo_wk8_status', 0))
    # status_id 1 is active. If it's removed, it's either deleted (0) or soft-deleted (3/4)
    if demo_wk8_status != 1:
        score += 20
        feedback_parts.append("✅ Demographics CRF successfully removed from Week 8")
    else:
        feedback_parts.append("❌ Demographics CRF is still actively assigned to Week 8")

    # --- Criterion 4B: Vital Signs assigned to Screening (20 pts) ---
    vitals_scr_status = int(result.get('vitals_scr_status', 0))
    # Needs to be actively assigned
    if vitals_scr_status == 1:
        score += 20
        feedback_parts.append("✅ Vital Signs CRF successfully assigned to Screening Visit")
    else:
        feedback_parts.append("❌ Vital Signs CRF is not actively assigned to Screening Visit")

    # --- Anti-Gaming: Audit Log Check ---
    audit_baseline = int(result.get('audit_baseline', 0))
    audit_current = int(result.get('audit_current', 0))
    if audit_current <= audit_baseline:
        score -= 100
        feedback_parts.append("❌ PENALTY: No GUI interactions detected in audit log (SQL manipulation bypass).")

    # --- Final Scoring Evaluation ---
    passed = score >= 80

    return {
        "passed": passed,
        "score": max(0, score),
        "feedback": " | ".join(feedback_parts)
    }