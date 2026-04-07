#!/usr/bin/env python3
import json
import os
import tempfile
import xml.etree.ElementTree as ET
from datetime import datetime

def verify_reschedule_project_start(traj, env_info, task_info):
    """
    Verifies that the user updated the project start date and manager name
    and saved the result as an XML file.
    """
    
    # 1. Setup and Load Data
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_output_path = metadata.get('output_path', '/home/ga/Projects/updated_project.xml')
    expected_manager = metadata.get('expected_manager', 'Sarah Chen')
    expected_start_date_str = metadata.get('expected_start_date_str', '2025-02-03')
    
    score = 0
    feedback_parts = []
    
    # Temporary files for extraction
    temp_json_path = tempfile.mktemp(suffix='.json')
    temp_xml_path = tempfile.mktemp(suffix='.xml')
    
    try:
        # 2. Check Task Result JSON (Metadata)
        try:
            copy_from_env("/tmp/task_result.json", temp_json_path)
            with open(temp_json_path, 'r') as f:
                task_result = json.load(f)
        except Exception:
            return {"passed": False, "score": 0, "feedback": "Could not retrieve task execution metadata."}
            
        if not task_result.get('output_exists'):
            return {"passed": False, "score": 0, "feedback": "Output file not found at ~/Projects/updated_project.xml"}
            
        if not task_result.get('file_created_during_task'):
            feedback_parts.append("Warning: Output file timestamp is outside task window.")
        else:
            score += 5 # Points for saving a new file
            
        # 3. Analyze XML Content
        try:
            copy_from_env(expected_output_path, temp_xml_path)
            
            # Parse XML
            # MSPDI uses a namespace
            namespaces = {'p': 'http://schemas.microsoft.com/project'}
            tree = ET.parse(temp_xml_path)
            root = tree.getroot()
            
            # Check 1: Valid MSPDI format (Root is Project)
            if 'Project' not in root.tag:
                 return {"passed": False, "score": score, "feedback": "File is not a valid Project XML file."}
            score += 10 # Valid XML
            
            # Check 2: Manager Name
            manager_elem = root.find('p:Manager', namespaces)
            actual_manager = manager_elem.text if manager_elem is not None else ""
            
            if actual_manager == expected_manager:
                score += 20
                feedback_parts.append(f"Manager correctly updated to '{actual_manager}'.")
            else:
                feedback_parts.append(f"Incorrect Manager. Expected '{expected_manager}', found '{actual_manager}'.")

            # Check 3: Project Start Date
            # XML format usually: 2025-02-03T08:00:00
            start_date_elem = root.find('p:StartDate', namespaces)
            actual_start_date_raw = start_date_elem.text if start_date_elem is not None else ""
            
            # Simple string check for the date part
            if expected_start_date_str in actual_start_date_raw:
                score += 20
                feedback_parts.append(f"Project Start Date correctly updated to {expected_start_date_str}.")
            else:
                feedback_parts.append(f"Incorrect Start Date. Expected '{expected_start_date_str}', found '{actual_start_date_raw}'.")

            # Check 4: Schedule Cascade (Tasks shifted)
            # Find tasks and check their start dates
            # We look for ANY task that starts on or after the new start date
            tasks = root.findall('p:Tasks/p:Task', namespaces)
            if len(tasks) < metadata.get('min_task_count', 1):
                feedback_parts.append("Project file seems empty or corrupted (too few tasks).")
            else:
                score += 10 # Tasks preserved
                
                # Check for cascade effect
                tasks_shifted = False
                for task in tasks:
                    task_start = task.find('p:Start', namespaces)
                    if task_start is not None and task_start.text and expected_start_date_str in task_start.text:
                        tasks_shifted = True
                        break
                
                if tasks_shifted:
                    score += 15
                    feedback_parts.append("Schedule dates have cascaded correctly.")
                else:
                    feedback_parts.append("Tasks do not appear to have shifted to the new start date.")

        except ET.ParseError:
            return {"passed": False, "score": score, "feedback": "Output file exists but is not valid XML."}
        except Exception as e:
            return {"passed": False, "score": score, "feedback": f"Error analyzing project file: {str(e)}"}
            
        # 4. VLM Verification (Trajectory)
        # We look for the 'Project Information' dialog in the screenshot trajectory
        from gym_anything.vlm import sample_trajectory_frames, query_vlm
        frames = sample_trajectory_frames(traj, n=4)
        
        if frames:
            prompt = """
            Look at these screenshots from ProjectLibre.
            Did the user open a dialog box titled 'Project Information' or 'Project Properties'?
            This dialog usually contains fields for 'Start Date', 'Current Date', and 'Manager'.
            
            Return JSON:
            {"dialog_seen": true/false}
            """
            try:
                vlm_res = query_vlm(prompt=prompt, images=frames)
                if vlm_res.get('success') and vlm_res.get('parsed', {}).get('dialog_seen'):
                    score += 20
                    feedback_parts.append("Visual confirmation: Project Information dialog was used.")
                else:
                    feedback_parts.append("Visual confirmation: Could not clearly identify Project Information dialog usage.")
            except Exception:
                pass # VLM failure shouldn't fail the task hard if files are correct
        
    finally:
        # Cleanup
        if os.path.exists(temp_json_path):
            os.unlink(temp_json_path)
        if os.path.exists(temp_xml_path):
            os.unlink(temp_xml_path)

    passed = score >= 60 and "Sarah Chen" in feedback_parts[0] # Require critical success
    
    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " ".join(feedback_parts)
    }