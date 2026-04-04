#!/usr/bin/env python3
"""
Verifier for cpdb_panel_management task.

Verifies:
1. 5 Specific participants added to CPDB.
2. Custom attributes 'Market_Segment' and 'Recruitment_Source' created.
3. Custom attributes populated correctly for participants.
4. Participants shared with the specific survey (exist in token table).
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_cpdb_panel_management(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy unavailable"}

    # Load result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/cpdb_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    metadata = task_info.get('metadata', {})
    expected_participants = metadata.get('expected_participants', [])
    expected_attributes = metadata.get('expected_attributes', ["Market_Segment", "Recruitment_Source"])

    score = 0
    max_score = 100
    feedback = []

    # Data from result
    participants = result.get('participants', [])
    attributes = result.get('attributes', [])
    attribute_values = result.get('attribute_values', [])
    survey_tokens = result.get('survey_tokens', [])

    # 1. Verify Participants (20 pts)
    # Check if all 5 emails exist in CPDB
    found_emails = [p.get('email', '').lower() for p in participants]
    participants_found = 0
    for expected in expected_participants:
        if expected['email'].lower() in found_emails:
            participants_found += 1
    
    if participants_found >= 5:
        score += 20
        feedback.append("All 5 participants found in CPDB.")
    else:
        feedback.append(f"Found {participants_found}/5 participants in CPDB.")
        score += (participants_found * 4)

    # 2. Verify Attributes Definition (20 pts - 10 each)
    found_attrs = [a.get('defaultname', '') for a in attributes]
    attr_score = 0
    for req_attr in expected_attributes:
        # Fuzzy match for attribute names (e.g. "Market Segment" vs "Market_Segment")
        match = any(req_attr.lower().replace('_', '') in fa.lower().replace('_', '').replace(' ', '') for fa in found_attrs)
        if match:
            attr_score += 10
            feedback.append(f"Attribute '{req_attr}' defined.")
        else:
            feedback.append(f"Attribute '{req_attr}' missing.")
    score += attr_score

    # 3. Verify Attribute Values (20 pts)
    # Check if values are populated for the found participants
    # We map participant email -> attribute -> value
    # First, build map of participant_id -> email
    pid_to_email = {p['participant_id']: p['email'].lower() for p in participants}
    
    # Build map of email -> attribute_name -> value
    p_values = {}
    for val in attribute_values:
        pid = val.get('participant_id')
        email = pid_to_email.get(pid)
        if not email: continue
        
        attr_name = val.get('attribute_name', '').lower().replace('_', '').replace(' ', '')
        value = val.get('value', '')
        
        if email not in p_values: p_values[email] = {}
        p_values[email][attr_name] = value

    # Check expectations
    val_correct = 0
    total_checks = len(expected_participants) * 2 # 2 attributes per participant
    
    for expected in expected_participants:
        email = expected['email'].lower()
        if email not in p_values: continue
        
        # Check Segment
        seg_expected = expected['segment']
        seg_actual = ""
        # Find the actual value for "marketsegment"
        for k, v in p_values[email].items():
            if "marketsegment" in k:
                seg_actual = v
                break
        
        if seg_expected.lower() in seg_actual.lower():
            val_correct += 1
            
        # Check Source
        src_expected = expected['source']
        src_actual = ""
        for k, v in p_values[email].items():
            if "recruitmentsource" in k:
                src_actual = v
                break
                
        if src_expected.lower() in src_actual.lower():
            val_correct += 1

    # Scale to 20 points
    val_score = int((val_correct / total_checks) * 20) if total_checks > 0 else 0
    score += val_score
    if val_score == 20:
        feedback.append("All attribute values populated correctly.")
    else:
        feedback.append(f"Attribute values partially correct ({val_correct}/{total_checks}).")

    # 4. Verify Sharing with Survey (40 pts)
    # Check if participants exist in the survey token table
    token_emails = [t.get('email', '').lower() for t in survey_tokens]
    shared_count = 0
    for expected in expected_participants:
        if expected['email'].lower() in token_emails:
            shared_count += 1
            
    if shared_count >= 5:
        score += 40
        feedback.append("All participants shared with survey.")
    else:
        share_score = shared_count * 8
        score += share_score
        feedback.append(f"Only {shared_count}/5 participants shared with survey.")

    return {
        "passed": score >= 70,
        "score": score,
        "feedback": " ".join(feedback)
    }