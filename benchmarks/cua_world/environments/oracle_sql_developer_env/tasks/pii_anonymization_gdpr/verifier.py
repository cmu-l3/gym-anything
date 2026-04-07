#!/usr/bin/env python3
"""Verifier for PII Anonymization GDPR task."""

import json
import logging
import os
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def _check_gui_usage(gui_evidence):
    """Check if SQL Developer GUI was actually used (2+ signals required)."""
    if not gui_evidence:
        return False, 0.0, "No GUI evidence"
    signals = 0
    details = []
    if gui_evidence.get('mru_connection_count', 0) > 0:
        signals += 1
        details.append(f"MRU:{gui_evidence['mru_connection_count']}")
    if gui_evidence.get('sqldev_oracle_sessions', 0) > 0:
        signals += 1
        details.append(f"sessions:{gui_evidence['sqldev_oracle_sessions']}")
    if gui_evidence.get('sql_history_count', 0) > 0:
        signals += 1
        details.append(f"history:{gui_evidence['sql_history_count']}")
    gui_used = signals >= 2
    return gui_used, min(signals / 3, 1.0), "; ".join(details) or "No signals"

def verify_pii_anonymization(traj, env_info, task_info):
    """
    Verify PII Anonymization task completion.
    
    Scoring (100 pts total):
    1. Package & Functions (25 pts):
       - package exists & valid (10 pts)
       - 6 functions exist (10 pts)
       - MASK_NAME is deterministic (5 pts)
    2. Anonymized Views (30 pts):
       - 3 views exist (15 pts, 5 ea)
       - Masking works: emails, phones, ibans (15 pts, 5 ea)
    3. PII Scan Results (15 pts):
       - table exists (5 pts)
       - rows > 0 & found emails (10 pts)
    4. Audit Log (10 pts):
       - table exists (5 pts)
       - rows > 0 (5 pts)
    5. Redaction & Export (15 pts):
       - ticket text redacted (5 pts)
       - CSV exported > 100 bytes (10 pts)
    6. GUI Usage (5 pts)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    try:
        temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/gdpr_result.json", temp_result.name)
            with open(temp_result.name, 'r') as f:
                result = json.load(f)
        finally:
            os.unlink(temp_result.name)

        score = 0
        feedback = []

        # 1. Package
        if result.get("pkg_valid"):
            score += 10
            feedback.append("Package exists and is valid (10/10)")
        elif result.get("pkg_exists"):
            score += 5
            feedback.append("Package exists but invalid (5/10)")
        else:
            feedback.append("Package missing (0/10)")

        func_count = result.get("func_count", 0)
        if func_count == 6:
            score += 10
            feedback.append("All 6 functions exist (10/10)")
        elif func_count > 0:
            pts = int((func_count/6.0)*10)
            score += pts
            feedback.append(f"{func_count}/6 functions exist ({pts}/10)")
        else:
            feedback.append("Functions missing (0/10)")

        if result.get("deterministic_name"):
            score += 5
            feedback.append("MASK_NAME is deterministic (5/5)")

        # 2. Views
        views_found = 0
        if result.get("customers_vw_exists"): views_found += 1
        if result.get("trans_vw_exists"): views_found += 1
        if result.get("tickets_vw_exists"): views_found += 1
        score += (views_found * 5)
        feedback.append(f"{views_found}/3 views created ({views_found*5}/15)")

        masking_pts = 0
        if result.get("email_masked"): masking_pts += 5
        if result.get("phone_masked"): masking_pts += 5
        if result.get("iban_masked"): masking_pts += 5
        score += masking_pts
        feedback.append(f"Data masking effectiveness ({masking_pts}/15)")

        # 3. PII Scan
        if result.get("pii_scan_tbl_exists"):
            score += 5
            if result.get("scan_found_email") and result.get("pii_scan_rows", 0) > 0:
                score += 10
                feedback.append("PII scanning successful (15/15)")
            else:
                feedback.append("PII scan table exists but no/incomplete results (5/15)")
        else:
            feedback.append("PII scan table missing (0/15)")

        # 4. Audit Log
        if result.get("log_tbl_exists"):
            score += 5
            if result.get("log_rows", 0) > 0:
                score += 5
                feedback.append("Audit log populated (10/10)")
            else:
                feedback.append("Audit log table empty (5/10)")
        else:
            feedback.append("Audit log missing (0/10)")

        # 5. Redaction & Export
        if result.get("tickets_redacted"):
            score += 5
            feedback.append("Ticket text successfully redacted (5/5)")
            
        csv_size = result.get("csv_size", 0)
        if result.get("csv_exists") and csv_size > 100:
            score += 10
            feedback.append(f"CSV report exported, size {csv_size} bytes (10/10)")
        else:
            feedback.append("CSV report missing or too small (0/10)")

        # 6. GUI
        gui_evidence = result.get("gui_evidence", {})
        gui_used, _, gui_details = _check_gui_usage(gui_evidence)
        if gui_used:
            score += 5
            feedback.append(f"GUI usage confirmed [{gui_details}] (5/5)")
        else:
            feedback.append("Insufficient GUI usage evidence (0/5)")

        passed = score >= 60 and result.get("pkg_exists") and views_found >= 1
        
        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback)
        }

    except Exception as e:
        logger.error(f"Verification failed: {e}")
        return {"passed": False, "score": 0, "feedback": f"Verification error: {e}"}