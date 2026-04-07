#!/usr/bin/env python3
import json
import os
import tempfile
import re

def verify_add_insurance_payer(traj, env_info, task_info):
    """
    Verifies that the agent added 'Aetna Better Health' to the address book
    with the correct details.
    """
    # 1. Setup: Load result data
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System Error: copy_from_env missing"}

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

    # 2. Extract Metadata & Result Data
    metadata = task_info.get('metadata', {})
    
    # Expected Values
    exp_name = metadata.get("expected_name", "Aetna Better Health").lower()
    exp_addr = metadata.get("expected_address", "PO Box 982960").lower()
    exp_city = metadata.get("expected_city", "El Paso").lower()
    exp_state = metadata.get("expected_state", "TX").lower()
    exp_zip = metadata.get("expected_zip", "79998")
    exp_phone = re.sub(r'\D', '', metadata.get("expected_phone", "8003060337"))
    exp_fax = re.sub(r'\D', '', metadata.get("expected_fax", "8605550199"))
    exp_payer_id = metadata.get("expected_payer_id", "60054")

    # Actual Values
    record_found = result.get('record_found', False)
    record = result.get('record', {})
    
    initial_count = int(result.get('initial_count', 0))
    current_count = int(result.get('current_count', 0))

    # 3. Scoring Logic
    score = 0
    feedback = []

    if not record_found:
        feedback.append("No address book entry found for 'Aetna Better Health'.")
        # Anti-gaming check: Did they add *something* else?
        if current_count > initial_count:
            feedback.append("A new record was added, but the name did not match 'Aetna Better Health'.")
        return {"passed": False, "score": 0, "feedback": " ".join(feedback)}
    
    # Base points for creating the record
    score += 30
    feedback.append("Record created.")

    # Check Address (20 pts)
    act_addr = record.get('address', '').lower()
    act_city = record.get('city', '').lower()
    act_state = record.get('state', '').lower()
    act_zip = record.get('zip', '').strip()
    
    # Allow partial match for street address (e.g., 'PO Box 982960' vs 'P.O. Box 982960')
    addr_match = exp_addr.replace('.','') in act_addr.replace('.','')
    city_match = exp_city in act_city
    state_match = exp_state in act_state
    zip_match = exp_zip in act_zip

    if addr_match and city_match and state_match and zip_match:
        score += 20
        feedback.append("Address details correct.")
    else:
        misses = []
        if not addr_match: misses.append(f"Street ({act_addr})")
        if not city_match: misses.append(f"City ({act_city})")
        if not state_match: misses.append(f"State ({act_state})")
        if not zip_match: misses.append(f"Zip ({act_zip})")
        feedback.append(f"Address incorrect/incomplete: {', '.join(misses)}.")

    # Check Phone/Fax (15 pts)
    act_phone = re.sub(r'\D', '', record.get('phone', ''))
    act_fax = re.sub(r'\D', '', record.get('fax', ''))
    
    if exp_phone in act_phone and exp_fax in act_fax:
        score += 15
        feedback.append("Contact numbers correct.")
    elif exp_phone in act_phone:
        score += 10
        feedback.append("Phone correct, Fax incorrect/missing.")
    else:
        feedback.append(f"Phone incorrect (found {act_phone}).")

    # Check Payer ID (25 pts) - Look in comments or potential custom fields
    # Sometimes it's put in 'specialty' or 'comments' depending on user choice
    act_comments = record.get('comments', '')
    act_specialty = record.get('specialty', '') # Some users might put it here
    
    # Check if Payer ID is present in comments or specialty
    if exp_payer_id in act_comments or exp_payer_id in act_specialty:
        score += 25
        feedback.append("Payer ID found.")
    else:
        feedback.append(f"Payer ID {exp_payer_id} not found in comments or notes.")

    # Check Type/Categorization (10 pts)
    # In NOSH, 'specialty' or 'displayname' sometimes holds clues, but often Insurance is just an entry
    # We'll give points if they put "Insurance" in specialty or if the record exists (lenient)
    # Strict check: 'specialty' field often used for category in address book
    if "insurance" in act_specialty.lower() or "payer" in act_specialty.lower():
         score += 10
         feedback.append("Categorized as Insurance.")
    else:
         # Fallback: if they did everything else right, we assume they selected the right type in UI 
         # even if database schema for 'type' is obscure.
         # For this specific task, if they got the Payer ID right, they likely put it in the right place.
         if score >= 75:
             score += 10
             feedback.append("Implicit category credit.")

    # 4. Final Verdict
    passed = score >= 75
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }