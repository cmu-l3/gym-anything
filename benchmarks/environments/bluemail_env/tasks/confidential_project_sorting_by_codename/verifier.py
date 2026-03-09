#!/usr/bin/env python3
"""
Verifier for confidential_project_sorting_by_codename task.

CRITERIA:
1. Folder Structure (20 pts): Parent 'Projects' + 3 subfolders exist.
2. Sorting Accuracy (60 pts): Emails inside folders must match keywords/priority.
3. Reporting (20 pts): Draft/Sent email to CTO exists with correct counts.
"""

import json
import tempfile
import os
import re
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_confidential_project_sorting(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
        
    # Get metadata
    metadata = task_info.get('metadata', {})
    keywords = metadata.get('keywords', {})
    
    # Priority: Shield > Mind > Grid
    # We define classification logic here to check against the agent's work
    def classify_email(text):
        # Check Shield
        for kw in keywords['shield']:
            if kw in text:
                return 'shield'
        # Check Mind
        for kw in keywords['mind']:
            if kw in text:
                return 'mind'
        # Check Grid
        for kw in keywords['grid']:
            if kw in text:
                return 'grid'
        return None

    # Load result
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

    analysis = result.get('maildir_analysis', {})
    subfolders = analysis.get('subfolders', {})
    
    score = 0
    feedback = []
    
    # =========================================================
    # 1. Folder Structure (20 pts)
    # =========================================================
    structure_score = 0
    if analysis.get('projects_root'):
        structure_score += 5
        feedback.append("Parent 'Projects' folder found.")
    else:
        feedback.append("Parent 'Projects' folder NOT found.")
        
    found_subs = subfolders.keys() # shield, mind, grid
    for req in ['shield', 'mind', 'grid']:
        if req in found_subs:
            structure_score += 5
            feedback.append(f"Subfolder Project-{req.capitalize()} found.")
        else:
            feedback.append(f"Subfolder Project-{req.capitalize()} NOT found.")
            
    score += structure_score

    # =========================================================
    # 2. Sorting Accuracy (60 pts)
    # =========================================================
    # We check every email in every folder.
    # Total correct placements / Total emails moved * 60
    
    total_emails_checked = 0
    correct_placements = 0
    misplacements = 0
    
    # Also track counts for report verification
    actual_counts = {'shield': 0, 'mind': 0, 'grid': 0}
    
    for folder_key, folder_data in subfolders.items():
        email_list = folder_data.get('emails', [])
        actual_counts[folder_key] = len(email_list)
        
        for email in email_list:
            total_emails_checked += 1
            text = email.get('full_text', '')
            ground_truth = classify_email(text)
            
            if ground_truth == folder_key:
                correct_placements += 1
            else:
                misplacements += 1
                # Optional: Detailed feedback for debugging
                # feedback.append(f"Misplaced email in {folder_key}: Subject '{email.get('subject')[:20]}...' should be {ground_truth}")

    sorting_score = 0
    if total_emails_checked > 0:
        # Calculate accuracy
        accuracy = correct_placements / total_emails_checked
        sorting_score = int(accuracy * 60)
        feedback.append(f"Sorting accuracy: {correct_placements}/{total_emails_checked} ({int(accuracy*100)}%)")
    elif structure_score > 0:
        feedback.append("Folders created but no emails moved.")
    
    score += sorting_score

    # =========================================================
    # 3. Report Verification (20 pts)
    # =========================================================
    report_score = 0
    drafts = analysis.get('drafts', [])
    sent = analysis.get('sent', [])
    all_msgs = drafts + sent
    
    report_found = False
    for msg in all_msgs:
        if 'cto@company.com' in msg.get('to', '').lower():
            report_found = True
            body = msg.get('body', '')
            subject = msg.get('subject', '')
            
            # Check for numbers
            # We look for the counts reported by the agent
            # We accept approximate format "Shield: 5" or "Shield 5"
            
            # Simple check: Does the body contain the numbers corresponding to the folders?
            # Since we don't know exactly what the agent *saw* (maybe it missed one), 
            # we check if the reported numbers match the *folder contents*.
            # If the folder has 5 emails, and report says 5, that's consistent.
            
            matches = 0
            for key in ['shield', 'mind', 'grid']:
                count = actual_counts[key]
                # Regex for "Shield: 5" or "Shield... 5"
                # Pattern: Name followed by number within reasonable distance
                pattern = re.compile(f"{key}.*?(\\d+)", re.IGNORECASE | re.DOTALL)
                match = pattern.search(body)
                if match:
                    reported_num = int(match.group(1))
                    if abs(reported_num - count) <= 1: # Allow off-by-one
                        matches += 1
            
            if matches >= 2: # At least 2/3 counts are correct/consistent
                report_score = 20
                feedback.append("Report found with consistent counts.")
            else:
                report_score = 10 # Found report but numbers don't match well
                feedback.append("Report found but counts don't match folder contents.")
            break
            
    if not report_found:
        feedback.append("No report email found to cto@company.com")
        
    score += report_score

    # =========================================================
    # Final Result
    # =========================================================
    return {
        "passed": score >= 70,
        "score": score,
        "feedback": " ".join(feedback),
        "details": {
            "structure_score": structure_score,
            "sorting_score": sorting_score,
            "report_score": report_score,
            "actual_counts": actual_counts
        }
    }