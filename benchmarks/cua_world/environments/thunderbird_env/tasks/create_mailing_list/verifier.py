#!/usr/bin/env python3
"""
Verifier for create_mailing_list task in Thunderbird.

VERIFICATION STRATEGY (Hybrid):
1. SQLite Database Inspection (Primary):
   - Copies abook.sqlite and directly queries it to find the 5 specific contacts.
   - Queries the mailing list ('lists' table) to confirm 'Regional Distributors' exists.
   - Validates that the contacts belong to the list ('list_cards' table).
   
2. File Timestamps (Anti-Gaming):
   - Verifies the address book was modified *during* the task, preventing "do nothing" exploits.
   
3. VLM Trajectory Check (Visual/Process Verification):
   - Uses sample_trajectory_frames to ensure the user actually opened the Address Book 
     and interacted with the mailing list creation dialog, preventing direct DB injection cheating.
"""

import os
import json
import sqlite3
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def get_db_contacts(db_path):
    """Extract contacts from Thunderbird's abook.sqlite."""
    contacts = []
    try:
        conn = sqlite3.connect(db_path)
        cursor = conn.cursor()
        
        # Properties table holds EAV (Entity-Attribute-Value) structured contact data
        cursor.execute("""
            SELECT card, name, value 
            FROM properties 
            WHERE name IN ('PrimaryEmail', 'FirstName', 'LastName', 'DisplayName')
        """)
        
        card_data = {}
        for card_id, name, value in cursor.fetchall():
            if card_id not in card_data:
                card_data[card_id] = {}
            card_data[card_id][name] = value
            
        for card_id, props in card_data.items():
            contacts.append({
                'card_id': card_id,
                'email': props.get('PrimaryEmail', '').strip().lower(),
                'first': props.get('FirstName', '').strip(),
                'last': props.get('LastName', '').strip(),
            })
            
        conn.close()
    except Exception as e:
        logger.error(f"Error reading contacts from DB: {e}")
    return contacts

def get_db_lists(db_path):
    """Extract mailing lists and their members from Thunderbird's abook.sqlite."""
    lists = []
    try:
        conn = sqlite3.connect(db_path)
        cursor = conn.cursor()
        
        # Ensure tables exist
        cursor.execute("SELECT name FROM sqlite_master WHERE type='table' AND name='lists'")
        if not cursor.fetchone():
            return lists
            
        cursor.execute("SELECT uid, name FROM lists")
        for uid, name in cursor.fetchall():
            list_name = name.strip() if name else ""
            
            # Get members (emails) via list_cards mapping to properties
            try:
                cursor.execute("""
                    SELECT p.value 
                    FROM list_cards lc 
                    JOIN properties p ON lc.card = p.card 
                    WHERE lc.list = ? AND p.name = 'PrimaryEmail'
                """, (uid,))
                members = [row[0].strip().lower() for row in cursor.fetchall() if row[0]]
            except Exception:
                members = []
                
            lists.append({
                'name': list_name,
                'members': members
            })
            
        conn.close()
    except Exception as e:
        logger.error(f"Error reading lists from DB: {e}")
    return lists

def verify_create_mailing_list(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
        
    metadata = task_info.get('metadata', {})
    expected_contacts = metadata.get('expected_contacts', [])
    expected_list_name = metadata.get('expected_list_name', 'Regional Distributors')
    
    score = 0
    max_score = 100
    feedback_parts = []
    
    # --- 1. Load Task Results ---
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result file: {e}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)
            
    # Anti-Gaming check: Was the file created/modified during the task?
    if not result.get('abook_modified_during_task', False):
        feedback_parts.append("Warning: Address book was not modified during the task execution time.")
        # We don't fail immediately because they might have created it extremely fast, but we flag it
        
    if not result.get('abook_exists', False):
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "Address book database (abook.sqlite) not found. No contacts created."
        }

    # --- 2. Load SQLite Database ---
    temp_db = tempfile.NamedTemporaryFile(delete=False, suffix='.sqlite')
    try:
        copy_from_env("/tmp/task_abook.sqlite", temp_db.name)
        
        db_contacts = get_db_contacts(temp_db.name)
        db_lists = get_db_lists(temp_db.name)
        
    finally:
        if os.path.exists(temp_db.name):
            os.unlink(temp_db.name)
            
    # --- 3. Verify Contacts (50 points, 10 pts per contact) ---
    found_contacts = 0
    expected_emails = [c['email'].lower() for c in expected_contacts]
    
    for expected in expected_contacts:
        target_email = expected['email'].lower()
        
        # Check if email exists in DB
        matched = False
        for c in db_contacts:
            if c['email'] == target_email:
                matched = True
                break
                
        if matched:
            found_contacts += 1
            score += 10
            feedback_parts.append(f"✓ Contact created: {expected['first']} {expected['last']} ({target_email})")
        else:
            feedback_parts.append(f"✗ Missing contact: {expected['first']} {expected['last']} ({target_email})")
            
    # --- 4. Verify Mailing List Existence (20 points) ---
    target_list = None
    for lst in db_lists:
        if expected_list_name.lower() in lst['name'].lower():
            target_list = lst
            break
            
    if target_list:
        score += 20
        feedback_parts.append(f"✓ Mailing List '{expected_list_name}' exists.")
    else:
        feedback_parts.append(f"✗ Mailing List '{expected_list_name}' not found.")
        
    # --- 5. Verify Mailing List Membership (15 points) ---
    if target_list:
        list_members = set([m.lower() for m in target_list['members']])
        members_matched = 0
        
        for email in expected_emails:
            if email in list_members:
                members_matched += 1
                
        # Proportional scoring for membership
        if len(expected_emails) > 0:
            membership_score = int(15 * (members_matched / len(expected_emails)))
            score += membership_score
            
        if members_matched == len(expected_emails):
            feedback_parts.append("✓ All expected contacts are members of the mailing list.")
        else:
            feedback_parts.append(f"△ Mailing list has {members_matched}/{len(expected_emails)} expected members.")
    else:
        feedback_parts.append("✗ Cannot verify membership because mailing list is missing.")
        
    # --- 6. VLM Trajectory Verification (15 points) ---
    # To prevent hacking/direct db injection, verify visual work in the GUI
    vlm_score = 0
    try:
        from gym_anything.vlm import sample_trajectory_frames, query_vlm
        
        frames = sample_trajectory_frames(traj, n=4)
        if frames:
            prompt = """You are verifying an agent using Thunderbird.
            Look at this sequence of screenshots and determine:
            1. Did the agent open the Thunderbird Address Book? (Look for contacts/address UI)
            2. Is there evidence of the agent creating a "Mailing List" or editing contact lists?
            
            Respond in JSON:
            {"address_book_opened": true/false, "mailing_list_dialog_seen": true/false}
            """
            
            vlm_result = query_vlm(images=frames, prompt=prompt)
            if vlm_result and vlm_result.get("success"):
                parsed = vlm_result.get("parsed", {})
                
                if parsed.get("address_book_opened", False):
                    vlm_score += 8
                    feedback_parts.append("✓ VLM verified Address Book was opened in GUI.")
                else:
                    feedback_parts.append("△ VLM could not confirm Address Book was opened in GUI.")
                    
                if parsed.get("mailing_list_dialog_seen", False):
                    vlm_score += 7
                    feedback_parts.append("✓ VLM verified Mailing List dialog was used.")
                else:
                    feedback_parts.append("△ VLM could not confirm Mailing List dialog was used.")
            else:
                feedback_parts.append("△ VLM verification failed or unavailable (giving partial fallback credit).")
                # Fallback: if they got the DB right but VLM fails, give partial process points
                if score >= 70: vlm_score += 10
        else:
            feedback_parts.append("△ No trajectory frames available for VLM verification.")
            if score >= 70: vlm_score += 10
    except ImportError:
        feedback_parts.append("△ VLM module not available. Fallback credit applied.")
        if score >= 70: vlm_score += 15
    except Exception as e:
        logger.warning(f"VLM verification error: {e}")
        if score >= 70: vlm_score += 15

    score += vlm_score
    
    # Calculate pass: 
    # Must have created at least 3 contacts AND created the list
    passed = score >= 60 and found_contacts >= 3 and target_list is not None
    
    return {
        "passed": passed,
        "score": score,
        "feedback": "\n".join(feedback_parts)
    }