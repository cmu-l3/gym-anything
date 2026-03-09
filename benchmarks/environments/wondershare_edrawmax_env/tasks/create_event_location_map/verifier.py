#!/usr/bin/env python3
import json
import os
import tempfile
import zipfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_event_location_map(traj, env_info, task_info):
    """
    Verifies the creation of a directional event map in EdrawMax.
    
    Criteria:
    1. .eddx file exists, is valid ZIP, and was created during task.
    2. .png file exists and was created during task.
    3. .eddx XML content contains required text labels:
       - "Main Street", "Oak Avenue"
       - "Convention Center" (fuzzy match for "Grand Convention Center")
       - "Parking", "Entrance"
    """
    
    # 1. Setup
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env not available"}

    metadata = task_info.get('metadata', {})
    required_text = metadata.get('required_text', ["Main Street", "Oak Avenue", "Convention Center"])
    
    # 2. Get Result JSON from container
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task result: {e}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    score = 0
    feedback = []
    
    # 3. Check File Existence & Timestamp (40 points)
    # EDDX Check
    if result_data.get('eddx_exists') and result_data.get('eddx_created_during_task'):
        score += 20
        feedback.append("Editable map file (.eddx) created successfully.")
    elif result_data.get('eddx_exists'):
        score += 10
        feedback.append("Editable map file exists but timestamp is invalid (pre-existing?).")
    else:
        feedback.append("Editable map file (.eddx) not found.")

    # PNG Check
    if result_data.get('png_exists') and result_data.get('png_created_during_task'):
        score += 20
        feedback.append("Map image (.png) exported successfully.")
    else:
        feedback.append("Map image (.png) not found or not exported.")

    # 4. Content Verification (60 points)
    # We copy the .eddx file and inspect its XML contents
    eddx_path_in_container = "/home/ga/Documents/event_map.eddx"
    temp_eddx = tempfile.NamedTemporaryFile(delete=False, suffix='.eddx')
    
    content_score = 0
    found_labels = []
    missing_labels = []
    
    try:
        if result_data.get('eddx_exists'):
            copy_from_env(eddx_path_in_container, temp_eddx.name)
            
            # EdrawMax .eddx files are ZIP archives containing XMLs
            if zipfile.is_zipfile(temp_eddx.name):
                with zipfile.ZipFile(temp_eddx.name, 'r') as zf:
                    # Extract all text from all XML files in the archive
                    full_text_content = ""
                    for filename in zf.namelist():
                        if filename.endswith(".xml"):
                            try:
                                full_text_content += zf.read(filename).decode('utf-8', errors='ignore')
                            except:
                                pass
                    
                    # Check for required labels (case insensitive)
                    full_text_lower = full_text_content.lower()
                    
                    # Weight per label (60 points total / 5 labels = 12 pts each)
                    for label in required_text:
                        # Split label to allow partial matches if needed, but strict is better for names
                        # We use simple substring search
                        if label.lower() in full_text_lower:
                            content_score += 12
                            found_labels.append(label)
                        else:
                            missing_labels.append(label)
            else:
                feedback.append("The .eddx file is not a valid ZIP archive.")
    except Exception as e:
        feedback.append(f"Error inspecting file content: {str(e)}")
    finally:
        if os.path.exists(temp_eddx.name):
            os.unlink(temp_eddx.name)

    score += content_score
    
    if found_labels:
        feedback.append(f"Found labels: {', '.join(found_labels)}")
    if missing_labels:
        feedback.append(f"Missing labels: {', '.join(missing_labels)}")

    # 5. Finalize
    passed = score >= 80  # Requires files + most text correct
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }