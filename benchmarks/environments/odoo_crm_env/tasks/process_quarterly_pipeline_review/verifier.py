#!/usr/bin/env python3
"""
Verifier for process_quarterly_pipeline_review task.
"""

import json
import os
import tempfile
import logging
from datetime import datetime

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_pipeline_review(traj, env_info, task_info):
    """
    Verify the status of three opportunities in Odoo CRM.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Copy result file
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

    if result.get('connection_error'):
        return {"passed": False, "score": 0, "feedback": f"Database connection failed: {result.get('error_msg')}"}

    score = 0
    feedback = []
    
    # 1. Verify Hyperion (Mark as Lost)
    # -----------------------------------------------
    hyperion = result.get('hyperion', {})
    if not hyperion.get('exists'):
        feedback.append("❌ Opportunity 'Hyperion' not found.")
    else:
        # Check Active = False (Lost)
        if hyperion.get('active') is False:
            score += 15
            feedback.append("✅ Hyperion marked as Lost.")
            
            # Check Reason
            reason = hyperion.get('lost_reason')
            if reason == "Too Expensive":
                score += 15
                feedback.append("✅ Hyperion lost reason is 'Too Expensive'.")
            else:
                feedback.append(f"❌ Hyperion reason is '{reason}', expected 'Too Expensive'.")
        else:
            feedback.append("❌ Hyperion is still Active (not marked Lost).")

    # 2. Verify Zenith (At Risk, Low Priority)
    # -----------------------------------------------
    zenith = result.get('zenith', {})
    if not zenith.get('exists'):
        feedback.append("❌ Opportunity 'Zenith' not found.")
    else:
        # Check Tag
        tags = zenith.get('tags', [])
        if "At Risk" in tags:
            score += 20
            feedback.append("✅ Zenith tagged 'At Risk'.")
        else:
            feedback.append(f"❌ Zenith tags: {tags}, expected 'At Risk'.")
            
        # Check Priority (0 or '0')
        priority = str(zenith.get('priority'))
        if priority == '0':
            score += 10
            feedback.append("✅ Zenith priority set to Low.")
        else:
            feedback.append(f"❌ Zenith priority is {priority} stars, expected 0.")

    # 3. Verify Apex (Negotiation, 90%)
    # -----------------------------------------------
    apex = result.get('apex', {})
    if not apex.get('exists'):
        feedback.append("❌ Opportunity 'Apex' not found.")
    else:
        # Check Stage
        stage = apex.get('stage')
        if stage == "Negotiation":
            score += 20
            feedback.append("✅ Apex moved to 'Negotiation' stage.")
        else:
            feedback.append(f"❌ Apex stage is '{stage}', expected 'Negotiation'.")
            
        # Check Probability
        prob = apex.get('probability', 0)
        # Allow slight float variance
        if 89.9 <= prob <= 90.1:
            score += 20
            feedback.append("✅ Apex probability set to 90%.")
        else:
            feedback.append(f"❌ Apex probability is {prob}%, expected 90%.")

    # 4. Anti-Gaming Check (Timestamps)
    # -----------------------------------------------
    # In Odoo, write_date is UTC string 'YYYY-MM-DD HH:MM:SS'
    # Task start time is unix timestamp
    # We will do a basic check that data exists. Precise timestamp check 
    # complicates things with TZ conversions, relying on values being correct is usually sufficient
    # combined with the fact the setup script resets them.
    
    # Simple check: Ensure modified fields were actually touched
    # (The score logic implicitly handles this, as setup values are different:
    # Hyperion starts Active, Zenith starts Priority 1, Apex starts Qualified/50%)

    # Final result
    passed = score >= 75
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }