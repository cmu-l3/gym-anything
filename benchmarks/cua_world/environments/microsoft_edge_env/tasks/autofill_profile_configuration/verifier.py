#!/usr/bin/env python3
"""
Verifier for autofill_profile_configuration task.
Verifies that the "Save and fill" feature is enabled and a correct profile exists.
"""

import json
import logging
import os
import tempfile
import sys

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_autofill_profile(traj, env_info, task_info):
    """
    Verify the agent configured the autofill profile correctly.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Get Expected Data
    metadata = task_info.get('metadata', {})
    expected = metadata.get('expected_profile', {})
    
    # Retrieve result file
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
    max_score = 100
    feedback = []
    
    # 1. Verify Feature Enabled (20 pts)
    # autofill_enabled is True by default in fresh profiles, but we want to ensure 
    # the agent didn't turn it off, or enabled it if we had disabled it (though we start clean).
    # The prompt explicitly asks to "Ensure... is turned ON".
    if result.get('autofill_enabled', False):
        score += 20
        feedback.append("Autofill feature is enabled.")
    else:
        feedback.append("Autofill feature is DISABLED.")

    # 2. Find Matching Profile (80 pts total split across fields)
    profiles = result.get('profiles', [])
    if not profiles:
        return {
            "passed": False, 
            "score": score, 
            "feedback": "No autofill profiles found. " + " ".join(feedback)
        }

    # Helper to clean strings for comparison
    def clean(s): return str(s).strip().lower()

    # Search for the best matching profile
    best_profile_score = 0
    best_match_details = []

    for p in profiles:
        current_p_score = 0
        current_p_details = []
        
        # We need to map DB fields to expected fields
        # Note: DB fields often use 'street_address' (multiline) or 'address_home_line1' etc.
        # We will check loose matches.
        
        # Check Name (First/Last or Full) (20 pts)
        # DB might have 'first_name', 'last_name', or 'full_name' or none of these if in separate tables
        # Our export script attempts to join them.
        
        db_first = p.get('first_name', '')
        db_last = p.get('last_name', '')
        db_full = p.get('full_name', '')
        
        exp_first = expected['first_name']
        exp_last = expected['last_name']
        exp_full = f"{exp_first} {exp_last}"
        
        name_match = False
        if clean(db_first) == clean(exp_first) and clean(db_last) == clean(exp_last):
            name_match = True
        elif clean(db_full) == clean(exp_full):
            name_match = True
        
        if name_match:
            current_p_score += 20
            current_p_details.append("Name matches")
        
        # Check Organization (10 pts)
        if clean(p.get('company_name', '')) == clean(expected['company']):
            current_p_score += 10
            current_p_details.append("Company matches")

        # Check Address (Street, City, State, Zip) (30 pts)
        # Address in DB often has newlines for street
        db_street = clean(p.get('street_address', ''))
        exp_street = clean(expected['address'])
        
        addr_score = 0
        if exp_street in db_street: # substring match for street (handling suite numbers etc)
            addr_score += 10
        if clean(p.get('city', '')) == clean(expected['city']):
            addr_score += 10
        if clean(p.get('state', '')) == clean(expected['state']): # WA
            addr_score += 5
        if clean(p.get('zipcode', '')) == clean(expected['zip']):
            addr_score += 5
        
        current_p_score += addr_score
        if addr_score == 30:
            current_p_details.append("Full Address matches")
        elif addr_score > 0:
            current_p_details.append(f"Partial Address match ({addr_score}pts)")

        # Check Contact (Phone, Email) (20 pts)
        # Export script puts emails/phones in lists
        contact_score = 0
        
        # Phone
        phones = p.get('phones', [])
        # Also check direct columns if they exist in older schemas
        if 'phone_number' in p: phones.append(p['phone_number'])
        
        phone_match = any(clean(expected['phone']) in clean(ph) for ph in phones)
        if phone_match:
            contact_score += 10
            current_p_details.append("Phone matches")

        # Email
        emails = p.get('emails', [])
        if 'email' in p: emails.append(p['email'])
        
        email_match = any(clean(expected['email']) == clean(em) for em in emails)
        if email_match:
            contact_score += 10
            current_p_details.append("Email matches")
        
        current_p_score += contact_score
        
        # Update best
        if current_p_score > best_profile_score:
            best_profile_score = current_p_score
            best_match_details = current_p_details

    score += best_profile_score
    feedback.append(f"Best profile match score: {best_profile_score}/80.")
    if best_match_details:
        feedback.append("Matched fields: " + ", ".join(best_match_details))

    # Anti-gaming: Check timestamp
    # If the profile was created before task start, it's invalid (but we wiped DB, so unlikely)
    # We rely on clean state setup mostly, but if we found a timestamp in DB, we could check.
    # Given the export script complexity with timestamps across versions, we'll trust the 
    # clean setup + data match.

    passed = (score >= 80)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }