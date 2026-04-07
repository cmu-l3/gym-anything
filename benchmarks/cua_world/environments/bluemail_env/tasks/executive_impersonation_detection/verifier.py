#!/usr/bin/env python3
"""
Verifier for executive_impersonation_detection task.

SCORING CRITERIA:
1. Quarantine Folder Created (10 pts)
   - Must contain 'BEC' and 'Quarantine' (case-insensitive)
2. Fake Emails Isolated (45 pts)
   - 15 pts per fake email moved to the quarantine folder.
   - 0 pts if left in Inbox.
3. Real Emails Preserved (20 pts)
   - 10 pts per real email REMAINING in Inbox.
   - 0 pts if moved to quarantine (false positive).
4. Report Drafted (15 pts)
   - Draft or Sent email to security@company.com.
5. Forensic Accuracy (10 pts)
   - Report body contains the attacker email addresses.

PASS THRESHOLD: 75/100
"""

import json
import tempfile
import os
import re
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_executive_impersonation_detection(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    fake_senders = metadata.get('fake_senders', [])
    
    # 1. Load Result
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
    feedback = []
    
    locations = result.get("locations", {})
    folders_created = result.get("folders_created", [])
    report = result.get("draft_report") or result.get("security_report_sent")
    
    # ==========================================================
    # Criterion 1: Quarantine Folder Created (10 pts)
    # ==========================================================
    # Relaxed matching: looks for "BEC" and "Quarantine" in name
    valid_folder = None
    for folder in folders_created:
        if "bec" in folder.lower() and "quarantine" in folder.lower():
            valid_folder = folder
            break
            
    if valid_folder:
        score += 10
        feedback.append(f"Correct folder created: '{valid_folder}'")
    else:
        feedback.append("Failed to create folder named 'BEC-Quarantine'")

    # ==========================================================
    # Criterion 2: Fake Emails Isolated (45 pts)
    # ==========================================================
    fake_ids = ["bec_fake_01", "bec_fake_02", "bec_fake_03"]
    fakes_caught = 0
    
    for fid in fake_ids:
        loc = locations.get(fid, "UNKNOWN")
        # Check if location matches the valid folder we found
        if valid_folder and loc == valid_folder:
            score += 15
            fakes_caught += 1
        elif "quarantine" in loc.lower(): # Fallback if they named it differently but didn't register in list
            score += 15
            fakes_caught += 1
        elif loc == "INBOX":
            feedback.append(f"Missed fake email ({fid}) - left in Inbox")
        elif loc == "Junk":
             # Partial credit for Junk folder instead of Quarantine? 
             # Task specifically asked for BEC-Quarantine folder. 
             # Giving 5 pts partial credit for Junk.
             score += 5
             feedback.append(f"Fake email ({fid}) moved to Junk instead of Quarantine (partial credit)")
        else:
            feedback.append(f"Fake email ({fid}) lost in '{loc}'")
            
    if fakes_caught == 3:
        feedback.append("All fake emails correctly quarantined.")

    # ==========================================================
    # Criterion 3: Real Emails Preserved (20 pts)
    # ==========================================================
    real_ids = ["bec_real_01", "bec_real_02"]
    
    for rid in real_ids:
        loc = locations.get(rid, "UNKNOWN")
        if loc == "INBOX":
            score += 10
        elif valid_folder and loc == valid_folder:
            feedback.append(f"False Positive: Real email ({rid}) moved to Quarantine!")
        else:
            # Maybe they moved it to an archive? If so, it's not ideal but better than quarantine.
            # But strict task says "Leave... in the Inbox".
            feedback.append(f"Real email ({rid}) moved to '{loc}' (should remain in Inbox)")

    # ==========================================================
    # Criterion 4: Report Drafted (15 pts)
    # ==========================================================
    if report:
        score += 15
        feedback.append("Report email drafted.")
        
        # Criterion 5: Forensic Accuracy (10 pts)
        # Check if body contains attacker emails
        body_lower = report.get("body", "").lower()
        found_senders = 0
        for fs in fake_senders:
            if fs.lower() in body_lower:
                found_senders += 1
        
        if found_senders > 0:
            score += 10
            feedback.append(f"Report lists {found_senders} attacker addresses.")
        else:
            feedback.append("Report does not contain attacker email addresses.")
    else:
        feedback.append("No report email drafted to security@company.com")

    passed = score >= 75
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }