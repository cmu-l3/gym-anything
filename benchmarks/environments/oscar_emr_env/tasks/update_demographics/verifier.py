#!/usr/bin/env python3
"""
Verifier for update_demographics task in Oscar EMR.
"""

import json
import os
import tempfile
import logging
import re

# Import VLM utilities if available, otherwise mock
try:
    from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm
except ImportError:
    # Mocks for local testing without framework
    def sample_trajectory_frames(traj, n=5): return []
    def get_final_screenshot(traj): return None
    def query_vlm(prompt, images): return {"parsed": {"success": False}}

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def normalize_phone(phone):
    """Normalize phone string to digits only."""
    if not phone:
        return ""
    return re.sub(r'\D', '', phone)

def normalize_string(s):
    """Normalize string for comparison (lower case, strip spaces)."""
    if not s:
        return ""
    return s.strip().lower()

def verify_update_demographics(traj, env_info, task_info):
    """
    Verify that patient demographics were updated correctly.
    
    Checks:
    1. Database state matches expected values (Address, City, Prov, Zip, Phone, Email)
    2. Changes were actually made (Anti-gaming via change detection)
    3. VLM verification of workflow (Trajectory)
    """
    
    # 1. Setup Result Retrieval
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
        
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load task result: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)
            
    # 2. Extract Data
    final_state = result.get('final_state', {})
    changes_detected = result.get('changes_detected', False)
    
    metadata = task_info.get('metadata', {})
    
    # Expected values
    exp_address = normalize_string(metadata.get('expected_address', '200 Bay Street'))
    exp_city = normalize_string(metadata.get('expected_city', 'Toronto'))
    exp_prov = normalize_string(metadata.get('expected_province', 'ON'))
    exp_postal = normalize_string(metadata.get('expected_postal', 'M5J 2J2')).replace(" ", "")
    exp_phone = normalize_phone(metadata.get('expected_phone', '647-555-0187'))
    exp_email = normalize_string(metadata.get('expected_email', 'emily.williams.new@gmail.com'))
    
    # Actual values
    act_address = normalize_string(final_state.get('address', ''))
    act_city = normalize_string(final_state.get('city', ''))
    act_prov = normalize_string(final_state.get('province', ''))
    act_postal = normalize_string(final_state.get('postal', '')).replace(" ", "")
    act_phone = normalize_phone(final_state.get('phone', ''))
    act_email = normalize_string(final_state.get('email', ''))
    
    # 3. Scoring Logic
    score = 0
    feedback_parts = []
    
    # Anti-gaming check (5 pts)
    if changes_detected:
        score += 5
        feedback_parts.append("Changes detected in database.")
    else:
        feedback_parts.append("No changes detected in database.")
        
    # Field Verification (75 pts total)
    
    # Address (20 pts)
    # Check if expected address is a substring of actual (handles "Suite 1500" variations)
    if exp_address in act_address:
        score += 20
        feedback_parts.append("Address updated correctly.")
    elif "200 bay" in act_address:
        score += 10
        feedback_parts.append("Address partially correct (missing details).")
    else:
        feedback_parts.append(f"Address incorrect (Expected containing '{exp_address}', got '{act_address}').")

    # City (10 pts)
    if act_city == exp_city:
        score += 10
        feedback_parts.append("City correct.")
    else:
        feedback_parts.append(f"City incorrect (Expected '{exp_city}', got '{act_city}').")
        
    # Province (5 pts)
    if act_prov == exp_prov:
        score += 5
        feedback_parts.append("Province correct.")
    else:
        feedback_parts.append("Province incorrect.")
        
    # Postal (10 pts)
    if act_postal == exp_postal:
        score += 10
        feedback_parts.append("Postal code correct.")
    elif act_postal[:3] == exp_postal[:3]:
        score += 5
        feedback_parts.append("Postal code partially correct.")
    else:
        feedback_parts.append("Postal code incorrect.")
        
    # Phone (15 pts)
    if exp_phone in act_phone:
        score += 15
        feedback_parts.append("Phone updated correctly.")
    else:
        feedback_parts.append(f"Phone incorrect (Expected digits '{exp_phone}', got '{act_phone}').")
        
    # Email (15 pts)
    if act_email == exp_email:
        score += 15
        feedback_parts.append("Email updated correctly.")
    else:
        feedback_parts.append(f"Email incorrect (Expected '{exp_email}', got '{act_email}').")

    # 4. VLM Verification (20 pts)
    # We check if the agent actually navigated the UI
    vlm_score = 0
    vlm_feedback = ""
    
    frames = sample_trajectory_frames(traj, n=4)
    if frames:
        prompt = """
        Analyze these screenshots of a user using Oscar EMR.
        Look for:
        1. A patient search screen or master record.
        2. A form with demographic fields (Name, Address, Phone).
        3. Evidence of typing or editing fields.
        
        Did the user navigate to a demographic editing form?
        Reply JSON: {"form_accessed": true/false, "editing_observed": true/false}
        """
        
        try:
            vlm_res = query_vlm(prompt=prompt, images=frames)
            parsed = vlm_res.get('parsed', {})
            
            if parsed.get('form_accessed', False):
                vlm_score += 10
                vlm_feedback += "VLM: Form access observed. "
            
            if parsed.get('editing_observed', False):
                vlm_score += 10
                vlm_feedback += "VLM: Editing observed. "
                
        except Exception as e:
            logger.warning(f"VLM check failed: {e}")
            # Fallback: if database score is high, assume VLM would pass
            if score >= 60:
                vlm_score = 20
                vlm_feedback = "VLM check skipped (DB score high). "
    else:
        # No frames available
        vlm_feedback = "No trajectory frames. "
        
    score += vlm_score
    feedback_parts.append(vlm_feedback)
    
    # 5. Final Result
    passed = score >= 60 and changes_detected
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback_parts)
    }