#!/usr/bin/env python3
"""
Verifier for link_contact_to_company task.
"""

import json
import logging
import os
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_link_contact_to_company(traj, env_info, task_info):
    """
    Verify the contact was linked to the correct company and details updated.
    
    Scoring:
    - 50 pts: Contact linked to 'Stratosphere Solutions'
    - 25 pts: Job position updated to 'VP of Engineering'
    - 25 pts: Mobile number set to '+1 (555) 010-9988'
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
        
    # Copy result file
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)
            
    if result.get("error"):
        return {"passed": False, "score": 0, "feedback": f"Export error: {result['error']}"}

    score = 0
    feedback_parts = []
    
    if not result.get("contact_found"):
        return {"passed": False, "score": 0, "feedback": "Target contact record was deleted or not found"}

    # 1. Check Parent Link (50 pts)
    actual_parent_id = result.get("parent_id")
    target_company_id = result.get("target_company_id")
    parent_name = result.get("parent_name", "None")
    
    if actual_parent_id and actual_parent_id == target_company_id:
        score += 50
        feedback_parts.append("✅ Contact correctly linked to Stratosphere Solutions")
    else:
        feedback_parts.append(f"❌ Contact not linked to correct company (Current: {parent_name})")

    # 2. Check Job Position (25 pts)
    job = result.get("job_position", "") or ""
    expected_job = "VP of Engineering"
    
    if job.lower().strip() == expected_job.lower():
        score += 25
        feedback_parts.append(f"✅ Job position updated to '{job}'")
    else:
        feedback_parts.append(f"❌ Job position incorrect (Expected '{expected_job}', got '{job}')")

    # 3. Check Mobile (25 pts)
    mobile = result.get("mobile", "") or ""
    # Normalize phone for flexible matching
    import re
    def normalize_phone(p):
        return "".join(re.findall(r'\d+', p))
    
    if normalize_phone(mobile) == "15550109988":
        score += 25
        feedback_parts.append(f"✅ Mobile number correct")
    else:
        feedback_parts.append(f"❌ Mobile number incorrect (Got '{mobile}')")

    passed = (score >= 75)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }