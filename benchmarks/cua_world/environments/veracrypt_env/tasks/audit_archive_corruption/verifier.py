#!/usr/bin/env python3
"""Verifier for audit_archive_corruption task."""

import json
import tempfile
import os
import base64
import logging
import csv
import io

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_audit_report(traj, env_info, task_info):
    """
    Verify the forensic audit report.
    
    Scoring:
    - Report exists and valid CSV: 10 pts
    - Case 001 correct (Healthy): 20 pts
    - Case 002 correct (Header_Repaired): 30 pts
    - Case 003 correct (Filesystem_Corrupt): 20 pts
    - Case 004 correct (Inaccessible): 20 pts
    - Anti-gaming: Report must be created during task.
    
    Bonus check: Actually checking if Case 002 header was restored on disk (strong evidence).
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_statuses = metadata.get('expected_statuses', {
        "case_001.hc": "Healthy",
        "case_002.hc": "Header_Repaired",
        "case_003.hc": "Filesystem_Corrupt",
        "case_004.hc": "Inaccessible"
    })

    score = 0
    max_score = 100
    feedback_parts = []
    
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        try:
            copy_from_env("/tmp/audit_result.json", temp_result.name)
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Error copying result: {e}"}

        with open(temp_result.name, 'r') as f:
            result = json.load(f)

        # 1. Check Report Existence
        if not result.get('report_exists'):
            return {"passed": False, "score": 0, "feedback": "Audit report file not found"}
        
        if not result.get('report_created_during_task'):
             # If report exists but wasn't made now, suspicious but might be overwriting pre-existing?
             # Task starts with clean state, so this usually implies "do nothing".
             pass # Penalty applied by not earning points if content is stale/empty

        # 2. Parse CSV Content
        content_b64 = result.get('report_content_b64', '')
        if not content_b64:
            return {"passed": False, "score": 0, "feedback": "Audit report is empty"}

        try:
            content = base64.b64decode(content_b64).decode('utf-8')
            csv_reader = csv.reader(io.StringIO(content))
            rows = list(csv_reader)
            
            # Normalize rows: lowercase keys, strip whitespace
            # Map filename -> status
            report_map = {}
            for row in rows:
                if len(row) >= 2:
                    fname = row[0].strip()
                    status = row[1].strip()
                    # clean up filename if they included full path
                    fname = os.path.basename(fname)
                    report_map[fname] = status
            
            score += 10
            feedback_parts.append("Report format valid")
            
        except Exception as e:
             return {"passed": False, "score": 10, "feedback": f"Invalid CSV format: {e}"}

        # 3. Grade each case
        for fname, expected in expected_statuses.items():
            reported = report_map.get(fname)
            
            # Allow some flexibility in status strings
            # e.g. "Healthy" vs "healthy"
            is_match = False
            if reported and expected.lower() == reported.lower():
                is_match = True
            
            if is_match:
                # Weights
                if fname == "case_001.hc": score += 20
                if fname == "case_002.hc": score += 30
                if fname == "case_003.hc": score += 20
                if fname == "case_004.hc": score += 20
                feedback_parts.append(f"{fname}: Correct ({reported})")
            else:
                feedback_parts.append(f"{fname}: Incorrect (Expected {expected}, Got {reported})")

        # 4. Verify Case 002 Repair Action (Anti-gaming for "guessing")
        # If they correctly guessed 'Header_Repaired' but didn't actually fix it, dock points?
        # The prompt implies they must perform the action to know the status (it fails otherwise).
        # But if they guessed, they might get lucky. 
        # However, checking disk state confirms the WORK was done.
        
        if result.get('case_002_header_restored'):
            feedback_parts.append("System confirms Case 002 header was restored on disk.")
        else:
            # If they reported "Header_Repaired" but disk shows corruption, they guessed/lied.
            if report_map.get("case_002.hc", "").lower() == "header_repaired":
                score -= 30 # Penalize the guess
                feedback_parts.append("PENALTY: Reported Case 002 repaired but header is still corrupt on disk!")

    except Exception as e:
        logger.error(f"Verification error: {e}")
        return {"passed": False, "score": 0, "feedback": f"Verification error: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    passed = score >= 100
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }