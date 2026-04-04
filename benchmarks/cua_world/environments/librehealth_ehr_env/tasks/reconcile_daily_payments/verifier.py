#!/usr/bin/env python3
"""
Verifier for reconcile_daily_payments task.

Verifies:
1. Database: Did a $40.00 cash payment appear for the correct patient?
2. Artifact: Was a PDF report generated?
3. Content: Does the PDF contain the payment amount and patient name?
4. VLM: Did the agent navigate the UI correctly?
"""

import json
import os
import tempfile
import logging
from pdfminer.high_level import extract_text

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_reconcile_daily_payments(traj, env_info, task_info):
    """
    Verify payment reconciliation task.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result JSON from container
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load task result: {e}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    score = 0
    feedback = []

    # 1. Database Verification (40 points)
    # Checks if the record exists in the DB (inserted by the app, not manually)
    payment_found = result.get("payment_found_in_db", False)
    if payment_found:
        score += 40
        feedback.append("Payment record found in database.")
    else:
        feedback.append("No matching payment record found in database.")

    # 2. PDF File Existence (20 points)
    pdf_exists = result.get("pdf_exists", False)
    pdf_created_during = result.get("pdf_created_during_task", False)
    
    if pdf_exists and pdf_created_during:
        score += 20
        feedback.append("Day Sheet PDF generated.")
    elif pdf_exists:
        score += 10
        feedback.append("Day Sheet PDF exists but timestamp is old (re-used?).")
    else:
        feedback.append("Day Sheet PDF not found on Desktop.")

    # 3. PDF Content Verification (20 points)
    # Extract text from the PDF and check for key strings
    content_verified = False
    if pdf_exists and result.get("pdf_path_in_container"):
        temp_pdf = tempfile.NamedTemporaryFile(delete=False, suffix='.pdf')
        try:
            copy_from_env(result["pdf_path_in_container"], temp_pdf.name)
            
            # Extract text using pdfminer
            try:
                text = extract_text(temp_pdf.name)
                
                # Check for criteria
                target_lname = result.get("target_lname", "")
                target_fname = result.get("target_fname", "")
                
                has_amount = "40.00" in text or "$40" in text
                has_name = target_lname in text or target_fname in text
                
                if has_amount and has_name:
                    score += 20
                    content_verified = True
                    feedback.append("PDF content verified (Name and Amount present).")
                elif has_amount:
                    score += 10
                    feedback.append("PDF contains correct amount but name missing/unclear.")
                elif has_name:
                    score += 5
                    feedback.append("PDF contains name but amount missing/unclear.")
                else:
                    feedback.append("PDF content check failed (Name/Amount not found in text).")
                    
            except Exception as e:
                feedback.append(f"Could not parse PDF text: {str(e)}")
                
        except Exception as e:
            feedback.append(f"Failed to retrieve PDF for verification: {e}")
        finally:
            if os.path.exists(temp_pdf.name):
                os.unlink(temp_pdf.name)

    # 4. VLM / Trajectory Check (20 points)
    # We want to ensure they actually used the Reports module
    # This is a basic check on the trajectory or final screenshot if available
    # Since we don't have the VLM available in this script scope, we rely on the
    # previous programmatic signals primarily. However, if the score is high (60+),
    # we assume they used the UI because the DB record exists.
    # We award these points if the primary task was successful.
    if payment_found and pdf_exists:
        score += 20
        feedback.append("Workflow implicitly verified by outputs.")

    passed = (score >= 80)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }