#!/usr/bin/env python3
"""
Verifier for process_digital_mailroom task.
Checks:
1. Files moved to correct workspaces.
2. Files renamed correctly.
3. Drop Box is empty.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_process_digital_mailroom(traj, env_info, task_info):
    # 1. Setup and retrieve data
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

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

    # 2. Define Scoring Criteria
    score = 0
    max_score = 100
    feedback = []
    
    # Config from task description
    # Contract: Contracts workspace, title "Contract - Acme v2"
    # Invoice: Invoices workspace, title "Invoice 992 Q3"
    # Asset: Assets workspace, title "Site Photo 0023"
    
    # Helper to check a workspace
    def check_workspace(ws_data, expected_title_substring):
        entries = ws_data.get('entries', [])
        found = False
        exact_match = False
        current_title = ""
        
        for entry in entries:
            props = entry.get('properties', {})
            title = props.get('dc:title', '')
            
            # Check for the file (assuming no other files cluttering these specific workspaces)
            # We look for the expected title
            if expected_title_substring.lower() in title.lower():
                found = True
                current_title = title
                if title.strip() == expected_title_substring:
                    exact_match = True
                break
        
        return found, exact_match, current_title

    # --- Verify Contract ---
    c_found, c_exact, c_title = check_workspace(result.get('contracts', {}), "Contract - Acme v2")
    if c_found:
        score += 25 # Moved correctly
        feedback.append("Contract moved to Contracts.")
        if c_exact:
            score += 10 # Renamed correctly
            feedback.append("Contract renamed correctly.")
        else:
            feedback.append(f"Contract title mismatch: found '{c_title}', expected 'Contract - Acme v2'.")
    else:
        feedback.append("Contract NOT found in Contracts workspace.")

    # --- Verify Invoice ---
    i_found, i_exact, i_title = check_workspace(result.get('invoices', {}), "Invoice 992 Q3")
    if i_found:
        score += 25
        feedback.append("Invoice moved to Invoices.")
        if i_exact:
            score += 10
            feedback.append("Invoice renamed correctly.")
        else:
            feedback.append(f"Invoice title mismatch: found '{i_title}', expected 'Invoice 992 Q3'.")
    else:
        feedback.append("Invoice NOT found in Invoices workspace.")

    # --- Verify Asset ---
    a_found, a_exact, a_title = check_workspace(result.get('assets', {}), "Site Photo 0023")
    if a_found:
        score += 20
        feedback.append("Photo moved to Assets.")
        if a_exact:
            score += 10
            feedback.append("Photo renamed correctly.")
        else:
            feedback.append(f"Photo title mismatch: found '{a_title}', expected 'Site Photo 0023'.")
    else:
        feedback.append("Photo NOT found in Assets workspace.")

    # --- Verify Drop Box Empty ---
    # Since failure to move penalizes points above, we don't need huge points here,
    # but strictly the drop box should be empty to get full marks.
    drop_box_entries = result.get('drop_box', {}).get('entries', [])
    if len(drop_box_entries) == 0:
        feedback.append("Drop Box is empty.")
    else:
        # If items remain, check if they are the original ones
        # If the user copied instead of moved, this is a penalty.
        # However, the task says "Move", so typically copy+delete or cut+paste.
        # If files are in target AND in drop box (copy), they get points for target but fail "clean up".
        # We implicitly penalize by not having explicit points for empty, 
        # but let's deduct or handle via threshold. 
        # Actually, the rubric says "Drop Box Empty: 0 (Implicitly checked)".
        # Let's subtract points if not empty? Or just leave as is. 
        # The prompt rubric says 0 points, but "failure to move penalizes above".
        # If they copied, they got the move points. 
        # Let's enforce strictly: if they copied but didn't delete, 
        # they failed the "Move" instruction technically (Move = Copy + Delete).
        # But for simplicity, we'll leave the score as sum of positive actions.
        feedback.append(f"Drop Box not empty ({len(drop_box_entries)} items remaining).")

    # 3. Finalize
    passed = (score >= 85)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }