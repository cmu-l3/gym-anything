#!/usr/bin/env python3
import json
import os
import tempfile
import xml.etree.ElementTree as ET
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_customize_wbs_code_structure(traj, env_info, task_info):
    """
    Verify that the ProjectLibre project was saved with the correct WBS code structure.
    
    Requirements:
    1. File /home/ga/Projects/custom_coded_project.xml exists.
    2. WBS codes for top-level tasks use "Phase [Letter]" format.
    3. Specifically checks "Requirements Gathering" -> "Phase A".
    """
    
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_output_path = metadata.get('expected_output_path', '/home/ga/Projects/custom_coded_project.xml')
    checks = metadata.get('checks', [])

    # Step 1: Get the result metadata
    task_result = {}
    with tempfile.NamedTemporaryFile(delete=False, suffix='.json') as f:
        temp_json_path = f.name
    
    try:
        copy_from_env("/tmp/task_result.json", temp_json_path)
        with open(temp_json_path, 'r') as f:
            task_result = json.load(f)
    except Exception as e:
        logger.warning(f"Could not read task result JSON: {e}")
    finally:
        if os.path.exists(temp_json_path):
            os.unlink(temp_json_path)

    if not task_result.get('output_exists', False):
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "Output file 'custom_coded_project.xml' was not found."
        }

    if not task_result.get('file_created_during_task', False):
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "Output file exists but was not created/modified during the task session."
        }

    # Step 2: Analyze the XML content
    score = 10 # Start with 10 points for creating the file
    feedback = ["File created successfully."]
    passed = False
    
    with tempfile.NamedTemporaryFile(delete=False, suffix='.xml') as f:
        temp_xml_path = f.name
        
    try:
        # Copy the actual XML output from the environment
        copy_from_env(expected_output_path, temp_xml_path)
        
        # Parse XML
        # MSPDI XML usually uses a namespace
        # e.g. xmlns="http://schemas.microsoft.com/project"
        try:
            tree = ET.parse(temp_xml_path)
            root = tree.getroot()
            
            # Handle XML namespace
            ns = ""
            if '}' in root.tag:
                ns = root.tag.split('}')[0] + '}'
            
            # Find tasks
            tasks_root = root.find(f"{ns}Tasks")
            if tasks_root is None:
                return {"passed": False, "score": score, "feedback": "Invalid XML: No <Tasks> element found."}
                
            tasks = tasks_root.findall(f"{ns}Task")
            
            # Map task names to WBS codes
            task_wbs_map = {}
            for t in tasks:
                name = t.findtext(f"{ns}Name")
                wbs = t.findtext(f"{ns}WBS")
                if name and wbs:
                    task_wbs_map[name] = wbs

            # Verify specific requirements
            wbs_correct_count = 0
            
            # Default checks if metadata is missing
            if not checks:
                checks = [
                    {"task_name": "Requirements Gathering", "expected_wbs": "Phase A"},
                    {"task_name": "System Architecture Design", "expected_wbs": "Phase B"}
                ]

            for check in checks:
                t_name = check["task_name"]
                e_wbs = check["expected_wbs"]
                
                actual_wbs = task_wbs_map.get(t_name, "Not Found")
                
                # Loose matching for "Phase A" (ProjectLibre might output "Phase A" or "Phase A." depending on settings)
                # We expect strict match based on description, but allow minor variations if clear
                if actual_wbs == e_wbs:
                    wbs_correct_count += 1
                    feedback.append(f"✓ Task '{t_name}' has correct WBS: {actual_wbs}")
                elif actual_wbs.startswith(e_wbs):
                    # Partial credit for "Phase A.1" if we expected "Phase A"? No, these are summary tasks.
                    # But maybe "Phase A" vs "Phase A."
                    if actual_wbs.strip('.') == e_wbs:
                        wbs_correct_count += 1
                        feedback.append(f"✓ Task '{t_name}' has correct WBS: {actual_wbs}")
                    else:
                        feedback.append(f"✗ Task '{t_name}' has WBS '{actual_wbs}', expected '{e_wbs}'")
                else:
                    feedback.append(f"✗ Task '{t_name}' has WBS '{actual_wbs}', expected '{e_wbs}'")

            # Calculate score based on matches
            if len(checks) > 0:
                score += int((wbs_correct_count / len(checks)) * 90)
            
            if wbs_correct_count == len(checks):
                passed = True
            
            # General sanity check for the pattern "Phase "
            phase_count = sum(1 for wbs in task_wbs_map.values() if str(wbs).startswith("Phase "))
            if phase_count > 5:
                feedback.append(f"General check: Found {phase_count} tasks with 'Phase' prefix.")
            else:
                feedback.append("General check: Few or no tasks start with 'Phase '.")
                if passed:
                    passed = False
                    feedback.append("Failed general pattern check despite specific matches.")

        except ET.ParseError:
            return {"passed": False, "score": score, "feedback": "Failed to parse exported XML file."}

    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Error verifying XML content: {str(e)}"}
    finally:
        if os.path.exists(temp_xml_path):
            os.unlink(temp_xml_path)

    return {
        "passed": passed,
        "score": score,
        "feedback": "\n".join(feedback)
    }