#!/usr/bin/env python3
import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_token_segmentation(traj, env_info, task_info):
    """
    Verify Token Custom Attributes Task.
    
    Criteria:
    1. Survey exists (Gate)
    2. Token table initialized
    3. 4 Custom Attributes defined (checked via descriptions)
    4. 8 Participants added
    5. Correct emails
    6. Attributes populated for participants
    7. Basic survey structure (Group/Question)
    """
    
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # Metadata expectations
    metadata = task_info.get('metadata', {})
    expected_attributes = [a.lower() for a in metadata.get('expected_attributes', [])]
    expected_participants_meta = metadata.get('expected_participants', [])
    expected_emails = set(p['email'].lower() for p in expected_participants_meta)

    score = 0
    feedback = []

    # 1. Gate: Survey Found
    if not result.get('survey_found'):
        return {"passed": False, "score": 0, "feedback": "Survey 'Post-Purchase Customer Satisfaction' not found."}
    
    # 2. Token Table Exists (15 pts)
    if result.get('token_table_exists'):
        score += 15
        feedback.append("Token table initialized.")
    else:
        feedback.append("Token table NOT initialized.")
        return {"passed": False, "score": score, "feedback": "\n".join(feedback)}

    # 3. Attribute Descriptions (15 pts)
    # The raw string in DB often looks like: {"attribute_1":{"description":"Customer Segment",...}, ...} or serialized PHP
    # We check if the expected attribute names appear in the raw description string
    raw_desc = str(result.get('attribute_descriptions_raw', '')).lower()
    attr_matches = 0
    for attr in expected_attributes:
        if attr in raw_desc:
            attr_matches += 1
    
    if attr_matches >= 4:
        score += 15
        feedback.append("All 4 custom attribute descriptions configured.")
    elif attr_matches > 0:
        score += 5 * attr_matches # Partial credit
        feedback.append(f"Only {attr_matches}/4 attribute descriptions found.")
    else:
        feedback.append("No custom attribute descriptions found.")

    # 4. Participant Count (15 pts)
    p_count = result.get('participant_count', 0)
    if p_count >= 8:
        score += 15
        feedback.append(f"Participant count met ({p_count}).")
    else:
        feedback.append(f"Insufficient participants: {p_count}/8.")

    # 5. Check Emails (15 pts)
    participants = result.get('participants', [])
    found_emails = set(p.get('email', '').lower() for p in participants)
    
    # Check intersection
    matching_emails = found_emails.intersection(expected_emails)
    if len(matching_emails) >= 8:
        score += 15
        feedback.append("All expected participant emails found.")
    elif len(matching_emails) > 0:
        # Scale score
        email_score = int(15 * (len(matching_emails) / 8))
        score += email_score
        feedback.append(f"Found {len(matching_emails)}/8 expected emails.")
    else:
        feedback.append("No expected emails found.")

    # 6. Attributes Populated (15 pts)
    # We check if the participants have values in their attribute columns
    # We don't strictly validate every single value against the spec for this specific score bucket,
    # but we check if 8 people have non-empty attributes.
    populated_count = result.get('attributes_populated_count', 0)
    if populated_count >= 8:
        score += 15
        feedback.append("Attributes populated for 8+ participants.")
    else:
        feedback.append(f"Attributes only fully populated for {populated_count} participants.")

    # 7. Basic Structure (10 pts)
    if result.get('group_count', 0) >= 1 and result.get('question_count', 0) >= 1:
        score += 10
        feedback.append("Survey structure (group/question) exists.")
    else:
        feedback.append("Survey is empty (no groups/questions).")

    # 8. Data Spot Check (15 pts - Implicit verification of correctness)
    # We verify one specific user to ensure data isn't junk
    spot_check_passed = False
    target_email = "s.mitchell@globalretail.com"
    # Attributes order might vary, so we look for values presence
    target_values = ["premium", "northeast", "gold", "high"]
    
    for p in participants:
        if p.get('email', '').lower() == target_email:
            # Gather all attribute values for this user
            user_attrs = [
                str(p.get('attr_1', '')).lower(),
                str(p.get('attr_2', '')).lower(),
                str(p.get('attr_3', '')).lower(),
                str(p.get('attr_4', '')).lower()
            ]
            # Check if all target values exist in the user's attributes (order agnostic)
            if all(val in user_attrs for val in target_values):
                spot_check_passed = True
            break
            
    if spot_check_passed:
        score += 15
        feedback.append("Data spot-check passed (Sarah Mitchell has correct attributes).")
    else:
        feedback.append("Data spot-check failed: Sarah Mitchell missing correct attribute values.")

    return {
        "passed": score >= 70,
        "score": score,
        "feedback": " | ".join(feedback)
    }