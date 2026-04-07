#!/usr/bin/env python3
"""
Verifier for configure_invoice_alert task in iDempiere.

Checks:
1. AD_Alert record exists with name "High Value Purchase"
2. Alert Subject is "Review Invoice > 1000"
3. Select Clause contains required SQL logic parts
4. Recipient is configured for user "GardenAdmin"
"""

import json
import os
import logging
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_configure_invoice_alert(traj, env_info, task_info):
    """
    Verify that the system alert was configured correctly.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Copy result JSON from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # 1. Verify Alert Record Exists (20 pts)
    if result.get('alert_found', False):
        score += 20
        feedback_parts.append("Alert record found")
    else:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "Alert record 'High Value Purchase' not found in database"
        }

    # 2. Verify Subject (10 pts)
    expected_subject = "Review Invoice > 1000"
    actual_subject = result.get('alert_subject', '')
    if expected_subject.lower() in actual_subject.lower():
        score += 10
        feedback_parts.append("Subject correct")
    else:
        feedback_parts.append(f"Subject incorrect (expected '{expected_subject}', got '{actual_subject}')")

    # 3. Verify SQL Logic (45 pts total)
    sql_clause = result.get('select_clause', '')
    
    # Check: Vendor Transaction (IsSOTrx='N')
    if "issotrx='n'" in sql_clause.lower() or "issotrx = 'n'" in sql_clause.lower():
        score += 15
        feedback_parts.append("SQL checks Vendor (IsSOTrx='N')")
    else:
        feedback_parts.append("SQL missing Vendor check (IsSOTrx='N')")

    # Check: Completed Status (DocStatus='CO')
    if "docstatus='co'" in sql_clause.lower() or "docstatus = 'co'" in sql_clause.lower():
        score += 15
        feedback_parts.append("SQL checks Status (DocStatus='CO')")
    else:
        feedback_parts.append("SQL missing Status check (DocStatus='CO')")

    # Check: Amount Threshold (GrandTotal > 1000)
    if "grandtotal > 1000" in sql_clause.lower() or "grandtotal>1000" in sql_clause.lower():
        score += 15
        feedback_parts.append("SQL checks Amount (> 1000)")
    else:
        feedback_parts.append("SQL missing Amount check (GrandTotal > 1000)")

    # 4. Verify Recipient (25 pts total)
    if result.get('recipient_found', False):
        score += 20
        feedback_parts.append("Recipient configured")
        
        recipient_user = result.get('recipient_user', '')
        if "gardenadmin" in recipient_user.lower():
            score += 5
            feedback_parts.append("Recipient is GardenAdmin")
        else:
            feedback_parts.append(f"Recipient user incorrect (got '{recipient_user}')")
    else:
        feedback_parts.append("No recipient configured")

    # Final result
    passed = score >= 60
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }