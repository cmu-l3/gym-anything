#!/usr/bin/env python3
import json
import os
import sys
import tempfile
import xml.etree.ElementTree as ET

def verify_update_project_metadata(traj, env_info, task_info):
    """
    Verifies that the user updated the project metadata (Title, Manager, Company)
    and saved the file correctly as XML.
    """
    # 1. Setup - Helper to copy files from environment
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System Error: Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_title = metadata.get('expected_title', "Enterprise Software Rev B")
    expected_manager = metadata.get('expected_manager', "Sarah Connor")
    expected_company = metadata.get('expected_company', "Cyberdyne Systems")
    min_task_count = metadata.get('min_task_count', 10)

    # 2. Retrieve Execution Result JSON
    task_result = {}
    temp_result_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result_file.name)
        with open(temp_result_file.name, 'r') as f:
            task_result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Could not retrieve task result: {str(e)}"}
    finally:
        if os.path.exists(temp_result_file.name):
            os.unlink(temp_result_file.name)

    # 3. Check Basic Criteria
    if not task_result.get("output_exists", False):
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "Target file ~/Projects/compliant_project.xml was not found."
        }
    
    if not task_result.get("file_created_during_task", False):
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "The output file exists but was not modified during the task session (Anti-gaming check failed)."
        }

    # 4. Retrieve and Parse the Output XML File
    score = 20 # Base score for valid file existence + timestamp check
    feedback_details = []
    
    temp_xml_file = tempfile.NamedTemporaryFile(delete=False, suffix='.xml')
    try:
        # Copy the XML file from the environment
        copy_from_env(task_result["output_path"], temp_xml_file.name)
        
        # Parse XML
        tree = ET.parse(temp_xml_file.name)
        root = tree.getroot()
        
        # Handle XML Namespaces (MSPDI usually uses http://schemas.microsoft.com/project)
        # We'll strip namespaces for easier tag searching to be robust
        for elem in root.iter():
            if '}' in elem.tag:
                elem.tag = elem.tag.split('}', 1)[1]
        
        # Helper to get text safely
        def get_val(tag_name):
            el = root.find(tag_name)
            return el.text if el is not None else None

        # Verify Title (25 pts)
        actual_title = get_val("Title")
        if actual_title == expected_title:
            score += 25
            feedback_details.append("Title updated correctly.")
        else:
            feedback_details.append(f"Title incorrect. Expected '{expected_title}', found '{actual_title}'.")

        # Verify Manager (25 pts)
        actual_manager = get_val("Manager")
        if actual_manager == expected_manager:
            score += 25
            feedback_details.append("Manager updated correctly.")
        else:
            feedback_details.append(f"Manager incorrect. Expected '{expected_manager}', found '{actual_manager}'.")

        # Verify Company (25 pts)
        actual_company = get_val("Company")
        if actual_company == expected_company:
            score += 25
            feedback_details.append("Company updated correctly.")
        else:
            feedback_details.append(f"Company incorrect. Expected '{expected_company}', found '{actual_company}'.")

        # Verify Integrity (Task count) (5 pts)
        # Ensure the user didn't just save an empty project with metadata
        tasks_found = len(root.findall(".//Task"))
        if tasks_found >= min_task_count:
            score += 5
            feedback_details.append(f"Project integrity check passed ({tasks_found} tasks).")
        else:
            feedback_details.append(f"Project integrity check warning: Only {tasks_found} tasks found (expected >{min_task_count}).")

    except ET.ParseError:
        return {"passed": False, "score": 20, "feedback": "Output file exists but is not valid XML."}
    except Exception as e:
        return {"passed": False, "score": 20, "feedback": f"Error parsing output file: {str(e)}"}
    finally:
        if os.path.exists(temp_xml_file.name):
            os.unlink(temp_xml_file.name)

    # 5. Final Evaluation
    # Pass threshold: 80 points (Allows for one metadata field being wrong, or missing integrity check, but mostly correct)
    passed = score >= 80
    feedback_str = " | ".join(feedback_details)

    return {
        "passed": passed,
        "score": score,
        "feedback": feedback_str
    }