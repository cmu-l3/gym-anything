import json
import os
import time
import datetime
from gym_anything.vlm import query_vlm, get_final_screenshot, sample_trajectory_frames

def verify_create_business_unit(traj, env_info, task_info):
    """
    Verifies that the agent created the 'IT Security Operations' Business Unit
    with the correct description and proper timestamp.
    """
    # 1. Setup & Data Retrieval
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System Error: copy_from_env not available"}

    metadata = task_info.get('metadata', {})
    required_keywords = metadata.get('required_keywords', [])
    expected_name = metadata.get('expected_name', "IT Security Operations")

    # Retrieve result JSON from container
    local_result_path = "task_result.json"
    try:
        copy_from_env("/tmp/task_result.json", local_result_path)
        with open(local_result_path, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task results: {str(e)}"}
    finally:
        if os.path.exists(local_result_path):
            os.remove(local_result_path)

    # Extract Data
    db_record = result_data.get('db_record', {})
    found = db_record.get('found', 0)
    record_name = db_record.get('name', "")
    description = db_record.get('description', "")
    created_str = db_record.get('created', "")
    
    initial_count = int(result_data.get('initial_count', 0))
    final_count = int(result_data.get('final_count', 0))
    task_start_ts = int(result_data.get('task_start', 0))

    score = 0
    feedback = []

    # 2. Primary Verification: Database Record Existence (30 pts)
    if found > 0 and record_name == expected_name:
        score += 30
        feedback.append("Success: Business Unit record found in database.")
    elif found > 0:
        score += 15
        feedback.append(f"Partial: Record found but name mismatch ('{record_name}' vs '{expected_name}').")
    else:
        feedback.append("Fail: No Business Unit record found with the expected name.")
        return {"passed": False, "score": 0, "feedback": "\n".join(feedback)}

    # 3. Content Verification: Description (20 pts)
    # Check for keywords
    matches = [kw for kw in required_keywords if kw.lower() in description.lower()]
    if len(matches) >= len(required_keywords):
        score += 20
        feedback.append("Success: Description contains all required keywords.")
    elif len(matches) > 0:
        score += 10
        feedback.append(f"Partial: Description missing some keywords. Found: {matches}")
    else:
        feedback.append("Fail: Description does not contain required details.")

    # 4. Anti-Gaming: Timestamp Validation (15 pts)
    # Parse DB timestamp (format typically YYYY-MM-DD HH:MM:SS)
    timestamp_valid = False
    try:
        # Assuming MySQL datetime format
        if created_str:
            created_dt = datetime.datetime.strptime(created_str, "%Y-%m-%d %H:%M:%S")
            # Convert to epoch
            created_ts = created_dt.timestamp()
            # Allow small clock skew (e.g. 60s), ensuring created AFTER task start
            if created_ts >= (task_start_ts - 60):
                score += 15
                timestamp_valid = True
                feedback.append("Success: Record creation timestamp is valid.")
            else:
                feedback.append(f"Fail: Record timestamp {created_str} is before task start.")
        else:
            feedback.append("Fail: No creation timestamp found.")
    except Exception as e:
        feedback.append(f"Warning: Could not parse timestamp '{created_str}': {e}")

    # 5. Metric: Count Increase (10 pts)
    if final_count > initial_count:
        score += 10
        feedback.append("Success: Total business unit count increased.")
    else:
        feedback.append("Fail: Total business unit count did not increase (did you overwrite an existing one?).")

    # 6. Exact Name Match (10 pts)
    # Case sensitive check
    if record_name == expected_name:
        score += 10
        feedback.append("Success: Name matches exactly.")
    else:
        feedback.append("Fail: Name casing or spacing mismatch.")

    # 7. VLM Verification (15 pts)
    # Check if the user interface actually shows the list with the new item
    # This proves they navigated there and didn't just curl the API (though difficult in this env)
    
    final_screenshot = get_final_screenshot(traj)
    if final_screenshot:
        prompt = f"""
        Analyze this screenshot of the Eramba GRC software.
        I am looking for a Business Unit named "{expected_name}" in a list or table.
        
        1. Is there a list or table visible?
        2. Do you see the text "{expected_name}"?
        3. Does it look like a valid saved entry (not an error message)?
        
        Answer yes/no for each and provide a brief reasoning.
        """
        
        vlm_resp = query_vlm(images=[final_screenshot], prompt=prompt)
        
        # Simple keyword heuristic on VLM response if structured parsing fails
        response_text = vlm_resp.get('response', '').lower()
        if "yes" in response_text and expected_name.lower() in response_text:
            score += 15
            feedback.append("Success: VLM confirms Business Unit is visible in the UI.")
        else:
            # Fallback point if VLM is unsure but DB is perfect
            if score >= 80: 
                score += 5 # Give partial credit if DB is solid
                feedback.append("Warning: VLM could not clearly see the entry, but DB confirms it.")
            else:
                feedback.append("Fail: VLM could not verify the entry visually.")
    else:
        feedback.append("Warning: No screenshot available for VLM verification.")

    # Final logic
    passed = (score >= 60) and (found > 0) and timestamp_valid

    return {
        "passed": passed,
        "score": score,
        "feedback": "\n".join(feedback)
    }