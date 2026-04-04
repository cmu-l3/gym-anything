import json
import os
import tempfile
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

def verify_configure_facility_details(traj, env_info, task_info):
    """
    Verifies that the agent correctly updated the facility details in LibreHealth EHR.
    
    Verification Logic:
    1. Programmatic: Checks database values exported from the container against expected values.
    2. Anti-gaming: Ensures database state actually changed during the task.
    3. Visual (VLM): Verifies the agent accessed the administration menu and facility editor.
    """
    
    # 1. Setup and retrieve data from environment
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env not available"}

    # Copy the result JSON file from the container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task results: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 2. Define Expected Values (from task metadata or defaults)
    metadata = task_info.get('metadata', {})
    expected = {
        'name': metadata.get('expected_name', "LibreHealth Medical Center"),
        'ein': metadata.get('expected_ein', "12-3456789"),
        'email': metadata.get('expected_email', "admin@librehealth.org"),
        'website': metadata.get('expected_website', "https://www.librehealth.org"),
        'phone': metadata.get('expected_phone', "555-0199"),
        'billing': str(metadata.get('expected_billing_location', 1))
    }

    actual = result_data.get('facility_data', {})
    db_changed = result_data.get('db_changed', False)
    
    score = 0
    feedback = []

    # 3. Programmatic Verification (70 points total)
    
    # Criterion 1: Facility Name (20 pts)
    # Allow case-insensitive match for name
    if actual.get('name', '').strip().lower() == expected['name'].lower():
        score += 20
        feedback.append("Facility name updated correctly.")
    else:
        feedback.append(f"Incorrect facility name: found '{actual.get('name')}', expected '{expected['name']}'.")

    # Criterion 2: Federal EIN (20 pts)
    if actual.get('ein', '').strip() == expected['ein']:
        score += 20
        feedback.append("Federal EIN updated correctly.")
    else:
        feedback.append(f"Incorrect EIN: found '{actual.get('ein')}', expected '{expected['ein']}'.")

    # Criterion 3: Contact Info (Email, Website, Phone) (20 pts)
    contact_score = 0
    if actual.get('email', '').strip() == expected['email']: contact_score += 7
    # Allow website with or without trailing slash
    act_web = actual.get('website', '').strip().rstrip('/')
    exp_web = expected['website'].rstrip('/')
    if act_web == exp_web: contact_score += 7
    if actual.get('phone', '').strip() == expected['phone']: contact_score += 6
    
    score += contact_score
    if contact_score == 20:
        feedback.append("All contact details updated correctly.")
    elif contact_score > 0:
        feedback.append("Some contact details updated.")
    else:
        feedback.append("Contact details (Email/Website/Phone) incorrect.")

    # Criterion 4: Billing Location Flag (10 pts)
    # DB usually returns '1' for true
    if str(actual.get('billing_location', '0')) == expected['billing']:
        score += 10
        feedback.append("Billing location flag set correctly.")
    else:
        feedback.append("Billing location flag not set.")

    # Anti-Gaming Check
    if not db_changed:
        return {"passed": False, "score": 0, "feedback": "No changes detected in database. Task failed."}

    # 4. Visual Verification via VLM (30 points)
    # We use trajectory frames to confirm the workflow was actually performed
    
    frames = sample_trajectory_frames(traj, n=4)
    final_frame = get_final_screenshot(traj)
    all_images = frames + [final_frame] if final_frame else frames
    
    vlm_prompt = (
        "Analyze these screenshots of a user interacting with LibreHealth EHR. "
        "I am looking for evidence that the user navigated to the Administration/Facilities settings. "
        "1. Do you see a menu navigation to 'Administration' or 'Facilities'? "
        "2. Do you see a form for editing a facility (fields like Name, EIN, Phone)? "
        "3. Did the user input 'LibreHealth Medical Center' or '12-3456789'? "
        "Answer with a JSON object: {'navigated_admin': bool, 'seen_facility_form': bool, 'seen_correct_input': bool}"
    )
    
    vlm_result = query_vlm(images=all_images, prompt=vlm_prompt)
    
    vlm_score = 0
    if vlm_result and 'parsed' in vlm_result:
        parsed = vlm_result['parsed']
        if parsed.get('navigated_admin', False): vlm_score += 10
        if parsed.get('seen_facility_form', False): vlm_score += 10
        if parsed.get('seen_correct_input', False): vlm_score += 10
        
    score += vlm_score
    feedback.append(f"VLM verification score: {vlm_score}/30")

    # 5. Final Result
    # Pass threshold: 70 points. Must have Name and EIN correct implies at least 40 pts from data, 
    # plus likely contact info. 70 ensures meaningful completion.
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }