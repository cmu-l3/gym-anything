#!/usr/bin/env python3
import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_configure_x12_partner(traj, env_info, task_info):
    """
    Verifies that the X12 Billing Partner 'Availity' was correctly configured.
    
    Verification Criteria:
    1. Database record exists (25 pts)
    2. Name matches 'Availity Clearinghouse' (15 pts)
    3. ID Number matches 'AVAIL001' (15 pts)
    4. Sender ID matches '193847502' (15 pts)
    5. Receiver ID matches 'AVAILITY' (15 pts)
    6. Format/Version match '5010'/'005010X222A1' (10 pts)
    7. VLM Workflow Check (5 pts)
    
    Total: 100 pts. Pass threshold: 60 pts.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env not available"}

    # Load metadata expected values
    metadata = task_info.get('metadata', {})
    expected_name = metadata.get('expected_name', "Availity Clearinghouse")
    expected_id = metadata.get('expected_id_number', "AVAIL001")
    expected_sender = metadata.get('expected_sender_id', "193847502")
    expected_receiver = metadata.get('expected_receiver_id', "AVAILITY")
    
    # 1. Retrieve result JSON from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task result: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)
            
    score = 0
    feedback_items = []
    
    # Check Database Record
    record_found = result.get('record_found', False)
    record_data = result.get('record_data', {})
    initial_count = result.get('initial_count', 0)
    final_count = result.get('final_count', 0)
    
    # Criterion 1: Record exists (25 pts)
    # Also verify count increased as an anti-gaming measure
    if record_found:
        if final_count > initial_count:
            score += 25
            feedback_items.append("✅ New X12 partner record created.")
        else:
            # Record exists but count didn't increase? Might be editing an old one (less likely due to setup cleanup)
            # We give partial credit if specific data matches, but penalize "creation"
            score += 10 
            feedback_items.append("⚠️ Record found, but row count did not increase (did you edit an existing one?).")
    else:
        feedback_items.append("❌ No X12 partner record found matching 'Availity'.")
        return {"passed": False, "score": 0, "feedback": " ".join(feedback_items)}

    # Criterion 2: Name (15 pts)
    # Flexible matching (case-insensitive substring)
    actual_name = record_data.get('name', '')
    if "availity" in actual_name.lower():
        score += 15
        feedback_items.append("✅ Name correct.")
    else:
        feedback_items.append(f"❌ Name mismatch: expected '{expected_name}', got '{actual_name}'.")

    # Criterion 3: ID Number (15 pts)
    if record_data.get('id_number') == expected_id:
        score += 15
        feedback_items.append("✅ ID Number correct.")
    else:
        feedback_items.append(f"❌ ID Number mismatch: expected '{expected_id}', got '{record_data.get('id_number')}'.")

    # Criterion 4: Sender ID (15 pts)
    if record_data.get('sender_id') == expected_sender:
        score += 15
        feedback_items.append("✅ Sender ID correct.")
    else:
        feedback_items.append(f"❌ Sender ID mismatch: expected '{expected_sender}', got '{record_data.get('sender_id')}'.")

    # Criterion 5: Receiver ID (15 pts)
    if record_data.get('receiver_id') == expected_receiver:
        score += 15
        feedback_items.append("✅ Receiver ID correct.")
    else:
        feedback_items.append(f"❌ Receiver ID mismatch: expected '{expected_receiver}', got '{record_data.get('receiver_id')}'.")

    # Criterion 6: Format/Version (10 pts)
    # Flexible: '5010' or 'ANSI X12 5010'
    actual_format = record_data.get('format', '')
    if '5010' in actual_format:
        score += 5
        feedback_items.append("✅ Format correct.")
    else:
        feedback_items.append(f"❌ Format mismatch: got '{actual_format}'.")
        
    actual_version = record_data.get('version', '')
    if '005010' in actual_version:
        score += 5
        feedback_items.append("✅ Version correct.")
    else:
        feedback_items.append(f"❌ Version mismatch: got '{actual_version}'.")

    # Criterion 7: VLM Workflow Check (5 pts)
    # We want to verify they actually visited the Administration menu
    frames = sample_trajectory_frames(traj, n=4)
    if frames:
        vlm_prompt = (
            "Does the user navigate to an Administration or Practice Settings menu? "
            "Do you see a form for entering X12 or Billing Partner details (Sender ID, Receiver ID)? "
            "Answer yes/no."
        )
        try:
            vlm_res = query_vlm(images=frames, prompt=vlm_prompt)
            if vlm_res.get('success') and 'yes' in vlm_res.get('parsed', {}).get('response', '').lower():
                score += 5
                feedback_items.append("✅ Visual workflow verified.")
            else:
                feedback_items.append("⚠️ Visual verification inconclusive.")
        except Exception:
            pass # VLM failure shouldn't fail the task if DB checks pass

    # Final Result
    passed = score >= 60 and record_found
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback_items)
    }