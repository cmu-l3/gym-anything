#!/usr/bin/env python3
import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_add_pharmacy_addressbook(traj, env_info, task_info):
    """
    Verify that the pharmacy was added to the address book with correct details.
    
    Scoring Breakdown (100 pts total):
    - 20 pts: Entry exists in database (Anti-gaming gate)
    - 15 pts: Correct Name
    - 15 pts: Correct Address
    - 10 pts: Correct City/State/Zip
    - 10 pts: Correct Phone
    - 5 pts: Correct Fax
    - 10 pts: Correct Specialty
    - 15 pts: VLM Trajectory Verification (Visual confirmation of UI interaction)
    """
    
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env not available"}

    # 1. Retrieve result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve verification data: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 2. Extract Data
    entry_found = result.get('entry_found', False)
    entry = result.get('entry', {})
    metadata = task_info.get('metadata', {})
    
    score = 0
    feedback = []
    
    # 3. Database Verification (Data Correctness)
    if entry_found:
        score += 20
        feedback.append("Pharmacy entry found in database (+20).")
        
        # Check Name (Check both displayname and facility fields as fallback)
        name_val = (entry.get('displayname') or entry.get('facility') or "").strip()
        if metadata.get('expected_name', '').lower() in name_val.lower():
            score += 15
            feedback.append("Name matches (+15).")
        else:
            feedback.append(f"Name mismatch: found '{name_val}' (-15).")
            
        # Check Address
        addr_val = (entry.get('street_address1') or "").strip()
        if "1625" in addr_val and "Main" in addr_val:
            score += 15
            feedback.append("Address matches (+15).")
        else:
            feedback.append(f"Address mismatch: found '{addr_val}' (-15).")

        # Check City/State/Zip
        city_val = (entry.get('city') or "").strip()
        state_val = (entry.get('state') or "").strip()
        zip_val = (entry.get('zip') or "").strip()
        
        csz_correct = True
        if metadata.get('expected_city', '').lower() not in city_val.lower(): csz_correct = False
        if metadata.get('expected_state', '').lower() not in state_val.lower(): csz_correct = False
        if metadata.get('expected_zip', '') not in zip_val: csz_correct = False
        
        if csz_correct:
            score += 10
            feedback.append("City/State/Zip match (+10).")
        else:
            feedback.append(f"City/State/Zip mismatch: {city_val}, {state_val} {zip_val} (-10).")

        # Check Phone (Normalize)
        phone_val = "".join(filter(str.isdigit, entry.get('phone', '')))
        expected_phone = "".join(filter(str.isdigit, metadata.get('expected_phone', '')))
        if expected_phone in phone_val:
            score += 10
            feedback.append("Phone matches (+10).")
        else:
            feedback.append(f"Phone mismatch: found '{entry.get('phone')}' (-10).")

        # Check Fax
        fax_val = "".join(filter(str.isdigit, entry.get('fax', '')))
        expected_fax = "".join(filter(str.isdigit, metadata.get('expected_fax', '')))
        if expected_fax in fax_val:
            score += 5
            feedback.append("Fax matches (+5).")
        else:
            feedback.append(f"Fax mismatch: found '{entry.get('fax')}' (-5).")
            
        # Check Specialty
        spec_val = (entry.get('specialty') or "").strip()
        if "pharmacy" in spec_val.lower():
            score += 10
            feedback.append("Specialty matches (+10).")
        else:
            feedback.append(f"Specialty mismatch: found '{spec_val}' (-10).")

    else:
        feedback.append("No entry found for 'Springfield Family Pharmacy' in address book.")
        # If entry not found, verify if count increased (maybe named differently?)
        if result.get('current_count', 0) > result.get('initial_count', 0):
            feedback.append("Note: Address book count increased, but specific name not found.")
            score += 5 # Small consolation for trying

    # 4. VLM Verification (Workflow / Anti-Gaming)
    # Ensure the user actually used the interface
    if query_vlm:
        frames = sample_trajectory_frames(traj, n=4)
        final_scr = get_final_screenshot(traj)
        if final_scr:
            frames.append(final_scr)
            
        prompt = """
        Review these screenshots of an EHR agent.
        1. Did the agent navigate to an Address Book, Contacts, or Practice Settings page?
        2. Did the agent fill out a form with pharmacy details (Name, Address, Phone)?
        3. Did the agent save the entry?
        
        Return JSON: {"workflow_valid": true/false, "reason": "..."}
        """
        
        try:
            vlm_res = query_vlm(images=frames, prompt=prompt)
            if vlm_res.get('parsed', {}).get('workflow_valid', False):
                score += 15
                feedback.append("VLM confirms valid workflow (+15).")
            else:
                feedback.append(f"VLM verification failed: {vlm_res.get('parsed', {}).get('reason', 'Unknown')} (-15).")
        except Exception as e:
            logger.warning(f"VLM query failed: {e}")
            # If VLM fails technically, we don't penalize if DB part was perfect
            if score >= 65: 
                score += 15
                feedback.append("VLM skipped (tech error), assuming passed based on DB data.")
    else:
        feedback.append("VLM unavailable.")
        if score >= 65: score += 15 # Grant points if unavailable but data correct

    # 5. Final Determination
    # Pass threshold: 60 (Requires entry existence + most fields correct)
    passed = (score >= 60) and entry_found
    
    return {
        "passed": passed,
        "score": min(100, score),
        "feedback": " ".join(feedback)
    }