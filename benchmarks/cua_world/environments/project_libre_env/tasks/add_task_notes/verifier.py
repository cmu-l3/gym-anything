#!/usr/bin/env python3
"""
Verifier for add_task_notes task.
Verifies that the user added the correct compliance notes to the correct task
and exported the file to the correct location.
"""

import json
import os
import tempfile
import logging
import xml.etree.ElementTree as ET
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_add_task_notes(traj, env_info, task_info):
    """
    Verify the add_task_notes task.
    
    Scoring:
    - 20 pts: Output file exists and created during task
    - 20 pts: Valid XML and contains 'Security Audit' task
    - 40 pts: Note content verification (keywords match)
    - 20 pts: VLM verification of UI interaction
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_path = metadata.get('output_path', '/home/ga/Projects/project_with_notes.xml')
    required_keywords = metadata.get('required_keywords', [])

    score = 0
    feedback_parts = []
    max_score = 100

    # 1. Check Task Result JSON
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {e}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    if not result_data.get("output_exists", False):
        return {"passed": False, "score": 0, "feedback": "Output XML file not found at expected path."}

    if not result_data.get("file_created_during_task", False):
        feedback_parts.append("Warning: Output file timestamp is older than task start.")
    else:
        score += 20
        feedback_parts.append("Output file created during task.")

    # 2. Analyze XML Content
    temp_xml = tempfile.NamedTemporaryFile(delete=False, suffix='.xml')
    try:
        copy_from_env(expected_path, temp_xml.name)
        tree = ET.parse(temp_xml.name)
        root = tree.getroot()
        
        # Handle Namespace (ProjectLibre usually uses Microsoft Project xmlns)
        # We'll search with and without namespace or use wildcard
        ns = {'p': 'http://schemas.microsoft.com/project'}
        
        # Try to find the specific task
        target_task_found = False
        notes_found = False
        notes_content = ""
        
        # Find all tasks
        tasks = root.findall(".//p:Task", ns)
        if not tasks:
            tasks = root.findall(".//Task") # Try without namespace
            
        for task in tasks:
            name_elem = task.find("p:Name", ns)
            if name_elem is None: name_elem = task.find("Name")
            
            if name_elem is not None and "Security Audit" in (name_elem.text or ""):
                target_task_found = True
                
                # Check notes
                note_elem = task.find("p:Notes", ns)
                if note_elem is None: note_elem = task.find("Notes")
                
                if note_elem is not None and note_elem.text:
                    notes_content = note_elem.text
                    notes_found = True
                break
        
        if target_task_found:
            score += 20
            feedback_parts.append("Target task 'Security Audit' found in XML.")
            
            if notes_found:
                # Check keywords
                matches = [kw for kw in required_keywords if kw.lower() in notes_content.lower()]
                match_count = len(matches)
                if match_count == len(required_keywords):
                    score += 40
                    feedback_parts.append("All required compliance note keywords found.")
                elif match_count > 0:
                    partial = int(40 * (match_count / len(required_keywords)))
                    score += partial
                    feedback_parts.append(f"Found {match_count}/{len(required_keywords)} keywords in notes.")
                else:
                    feedback_parts.append("Notes found but missing required keywords.")
            else:
                feedback_parts.append("Target task found, but 'Notes' field is empty.")
        else:
            feedback_parts.append("Target task 'Security Audit' NOT found in exported XML.")

    except ET.ParseError:
        feedback_parts.append("Output file exists but is not valid XML.")
    except Exception as e:
        feedback_parts.append(f"Error parsing XML: {str(e)}")
    finally:
        if os.path.exists(temp_xml.name):
            os.unlink(temp_xml.name)

    # 3. VLM Verification (Trajectory)
    # Check if the user actually opened the Task Information dialog
    frames = sample_trajectory_frames(traj, n=4)
    if frames:
        prompt = (
            "Review these screenshots of a user using ProjectLibre. "
            "Did the user open a 'Task Information' dialog box? "
            "Can you see a tab labeled 'Notes' or text being entered into a text area? "
            "Answer yes or no and explain."
        )
        vlm_res = query_vlm(prompt=prompt, images=frames)
        
        if vlm_res.get("success") and "yes" in vlm_res.get("response", "").lower():
            score += 20
            feedback_parts.append("VLM confirms Task Information/Notes interaction.")
        else:
            # Fallback points if XML was perfect, assuming they did it blindly/fast
            if score >= 80:
                score += 10 
                feedback_parts.append("VLM inconclusive, but output is perfect.")
            else:
                feedback_parts.append("VLM did not detect Task Information dialog interaction.")
    else:
        feedback_parts.append("No trajectory frames available for visual verification.")

    passed = score >= 70
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback_parts)
    }