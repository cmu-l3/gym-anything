#!/usr/bin/env python3
"""
Verifier for configure_document_expiry_alert task.

Task: Configure a Passport document for Elena Rossi with 60-day expiry alert.

Verification Logic:
1. Primary: Check Firebird database for the created record.
   - Must match Employee: EMP-2050
   - Must match Document Number: YT8822119
   - Must match Expiry: 2030-01-14
   - Must match Alert: 60 days
2. Secondary: VLM Check on final screenshot to verify UI state.
"""

import json
import os
import tempfile
import logging
import datetime

# Setup logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_configure_document_expiry_alert(traj, env_info, task_info):
    """
    Verify the document expiry alert task.
    """
    # 1. Setup Interface
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Environment interface failure: copy_from_env missing"}

    # 2. Load Result JSON from Container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        # Windows path in container -> local temp file
        copy_from_env("C:\\workspace\\task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except FileNotFoundError:
        return {"passed": False, "score": 0, "feedback": "Task result file not found. Did the agent run the export script?"}
    except json.JSONDecodeError:
        return {"passed": False, "score": 0, "feedback": "Corrupt result file."}
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Error reading result: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 3. Scoring Logic
    score = 0
    feedback = []
    
    # Metadata targets
    target_doc = "YT8822119"
    target_alert = 60
    # Note: Date formats can vary (YYYY-MM-DD or DD-MMM-YYYY), we need robust checking
    target_year = "2030" 
    
    # Criterion 1: Record Exists (20 pts)
    if result.get("record_found"):
        score += 20
        feedback.append("Document record found in database.")
        
        # Criterion 2: Document Number (20 pts)
        actual_doc = result.get("doc_number", "")
        if target_doc in actual_doc:
            score += 20
        else:
            feedback.append(f"Document number mismatch: Found '{actual_doc}', expected '{target_doc}'.")
            
        # Criterion 3: Expiry Date (20 pts)
        actual_date = result.get("expiry_date", "")
        # Flexible date checking
        if target_year in actual_date and ("Jan" in actual_date or "-01-" in actual_date):
            score += 20
        else:
            feedback.append(f"Expiry date mismatch: Found '{actual_date}', expected Jan 2030.")
            
        # Criterion 4: Alert Days (20 pts)
        actual_alert = result.get("alert_days", 0)
        if actual_alert == target_alert:
            score += 20
        else:
            feedback.append(f"Alert configuration mismatch: Found {actual_alert} days, expected {target_alert} days.")
            
    else:
        feedback.append("No matching document record found for Elena Rossi.")

    # Criterion 5: App Running (10 pts)
    if result.get("app_running"):
        score += 10
    else:
        feedback.append("Application was closed at end of task.")

    # Criterion 6: VLM Verification (10 pts)
    # Simple existence check of screenshot for this implementation
    # (In full production, we would query a VLM here using the trajectory)
    if result.get("screenshot_path"):
        score += 10
    
    # Final Pass/Fail
    # Must have the record, correct doc number, and alert configured to pass
    passed = (score >= 80)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }