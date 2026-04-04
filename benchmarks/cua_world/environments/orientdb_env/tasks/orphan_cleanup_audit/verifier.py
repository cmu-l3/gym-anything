#!/usr/bin/env python3
"""
Verifier for orphan_cleanup_audit task.

Checks:
1. Database State (50 pts):
   - Specific orphan vertices must be gone.
   - Non-orphan vertices must still exist (integrity check).
2. Audit Report (50 pts):
   - File existence.
   - Correct counts reported.
   - Correct details (emails/names) listed.
"""

import json
import os
import tempfile
import logging
import re

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_orphan_cleanup_audit(traj, env_info, task_info):
    """Verify orphan deletion and audit report."""
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result from container
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
    feedback_parts = []
    
    # --- 1. Database Verification (50 points) ---
    db_state = result.get("db_state", {})
    
    # A. Orphan Profiles (20 pts)
    p_deleted = db_state.get("orphan_profiles_deleted", 0)
    if p_deleted == 8:
        score += 20
        feedback_parts.append("All orphan profiles deleted (20/20)")
    elif p_deleted > 0:
        partial = int((p_deleted / 8) * 20)
        score += partial
        feedback_parts.append(f"Some orphan profiles deleted ({p_deleted}/8) (+{partial})")
    else:
        feedback_parts.append("No orphan profiles deleted")

    # B. Orphan Hotels (15 pts)
    h_deleted = db_state.get("orphan_hotels_deleted", 0)
    if h_deleted == 4:
        score += 15
        feedback_parts.append("All orphan hotels deleted (15/15)")
    elif h_deleted > 0:
        partial = int((h_deleted / 4) * 15)
        score += partial
        feedback_parts.append(f"Some orphan hotels deleted ({h_deleted}/4) (+{partial})")
    else:
        feedback_parts.append("No orphan hotels deleted")

    # C. Data Integrity (15 pts) - Penalize if legitimate data was lost
    init_p = db_state.get("initial_connected_profiles", 0)
    curr_p = db_state.get("current_connected_profiles", 0)
    init_h = db_state.get("initial_connected_hotels", 0)
    curr_h = db_state.get("current_connected_hotels", 0)
    
    integrity_loss = False
    if curr_p < init_p:
        integrity_loss = True
        feedback_parts.append(f"CRITICAL: Deleted {init_p - curr_p} non-orphan profiles!")
    if curr_h < init_h:
        integrity_loss = True
        feedback_parts.append(f"CRITICAL: Deleted {init_h - curr_h} non-orphan hotels!")
        
    if not integrity_loss:
        score += 15
        feedback_parts.append("Data integrity maintained (15/15)")
    else:
        feedback_parts.append("Data integrity check failed (0/15)")

    # --- 2. Audit Report Verification (50 points) ---
    report = result.get("report_file", {})
    if not report.get("exists", False):
        feedback_parts.append("Audit report file not found (0/50)")
    else:
        # File exists (5 pts)
        score += 5
        feedback_parts.append("Report file exists (+5)")
        
        content = report.get("content_json", "")
        # Normalize content
        content_lower = content.lower()
        
        # Check counts (15 pts total)
        # Look for patterns like "Orphan Profiles Found: 8"
        if re.search(r"orphan profiles.*8", content_lower):
            score += 5
            feedback_parts.append("Correct profile count reported (+5)")
        if re.search(r"orphan hotels.*4", content_lower):
            score += 5
            feedback_parts.append("Correct hotel count reported (+5)")
        if re.search(r"total.*12", content_lower):
            score += 5
            feedback_parts.append("Correct total count reported (+5)")
            
        # Check details (30 pts total)
        # Check for presence of orphan emails
        found_emails = 0
        expected_emails = task_info.get("metadata", {}).get("orphan_profiles", [])
        for email in expected_emails:
            if email.lower() in content_lower:
                found_emails += 1
        
        # Proportional score for emails (max 20 pts)
        if len(expected_emails) > 0:
            email_score = int((found_emails / len(expected_emails)) * 20)
            score += email_score
            if email_score > 0:
                feedback_parts.append(f"Listed {found_emails} orphan emails (+{email_score})")

        # Check for presence of hotel names
        found_hotels = 0
        expected_hotels = task_info.get("metadata", {}).get("orphan_hotels", [])
        for hotel in expected_hotels:
            if hotel.lower() in content_lower:
                found_hotels += 1
                
        # Proportional score for hotels (max 10 pts)
        if len(expected_hotels) > 0:
            hotel_score = int((found_hotels / len(expected_hotels)) * 10)
            score += hotel_score
            if hotel_score > 0:
                feedback_parts.append(f"Listed {found_hotels} orphan hotels (+{hotel_score})")

    # Final logic
    passed = (score >= 60) and (p_deleted > 0 or h_deleted > 0)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": "; ".join(feedback_parts)
    }