#!/usr/bin/env python3
import json
import os
import tempfile
import xml.etree.ElementTree as ET
from datetime import datetime

def verify_add_task_hyperlinks(traj, env_info, task_info):
    """
    Verifies that the agent added the correct hyperlinks to specific tasks
    and saved the project as an XML file.
    """
    
    # 1. Setup and Environment Check
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Environment error: copy_from_env not available"}

    metadata = task_info.get('metadata', {})
    expected_output_path = metadata.get("expected_output_path", "/home/ga/Projects/linked_project.xml")
    
    # Define expected values from metadata
    task_2_uid = metadata.get("task_2_uid", "2")
    task_2_expected_title = metadata.get("task_2_title", "Design Spec v2")
    task_2_expected_url = metadata.get("task_2_url", "https://internal.corp/specs/sys_arch_v2.pdf")
    
    task_11_uid = metadata.get("task_11_uid", "11")
    task_11_expected_title = metadata.get("task_11_title", "EPA Permit")
    task_11_expected_url = metadata.get("task_11_url", "file:///home/ga/Documents/permits/epa_compliance_2025.pdf")

    # 2. Get Result JSON
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load verification data: {str(e)}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    # 3. Check File Existence and Creation
    if not result_data.get("output_exists"):
        return {"passed": False, "score": 0, "feedback": "Output XML file was not created."}
    
    if not result_data.get("file_created_during_task"):
        return {"passed": False, "score": 0, "feedback": "Output file exists but was not modified during the task (stale data)."}

    # 4. Parse XML Content
    score = 0
    feedback = []
    
    # Points breakdown:
    # - File validity/Export success: 20
    # - Task 2 Title: 20
    # - Task 2 URL: 20
    # - Task 11 Title: 20
    # - Task 11 Path: 20
    
    temp_xml = tempfile.NamedTemporaryFile(delete=False, suffix='.xml')
    try:
        copy_from_env(expected_output_path, temp_xml.name)
        
        # Parse XML
        # MSPDI XML usually has a default namespace. We need to handle that.
        # We'll use register_namespace to avoid 'ns0' prefixes in output if we were writing,
        # but for reading we just need to match it.
        try:
            tree = ET.parse(temp_xml.name)
            root = tree.getroot()
            
            # Extract namespace from root tag (e.g., {http://schemas.microsoft.com/project}Project)
            if '}' in root.tag:
                ns_url = root.tag.split('}')[0].strip('{')
                ns = {'p': ns_url}
            else:
                ns = {} # No namespace
                
            score += 20 # File is valid XML
            feedback.append("File exported successfully.")
            
            # Helper to find text safely
            def find_task_val(task_elem, tag_name):
                if ns:
                    elem = task_elem.find(f"p:{tag_name}", ns)
                else:
                    elem = task_elem.find(tag_name)
                return elem.text if elem is not None else None

            # Find tasks
            tasks_found = 0
            
            # Locate Tasks container
            tasks_container = root.find("p:Tasks", ns) if ns else root.find("Tasks")
            if tasks_container is None:
                feedback.append("Could not find Tasks element in XML.")
            else:
                for task in tasks_container:
                    uid = find_task_val(task, "UID")
                    
                    # Verify Task 2
                    if uid == task_2_uid:
                        tasks_found += 1
                        hl_title = find_task_val(task, "Hyperlink")
                        hl_addr = find_task_val(task, "HyperlinkAddress")
                        
                        if hl_title == task_2_expected_title:
                            score += 20
                            feedback.append(f"Task 2 Title correct: {hl_title}")
                        else:
                            feedback.append(f"Task 2 Title incorrect. Expected '{task_2_expected_title}', got '{hl_title}'")
                            
                        if hl_addr == task_2_expected_url:
                            score += 20
                            feedback.append(f"Task 2 URL correct.")
                        else:
                            feedback.append(f"Task 2 URL incorrect. Expected '{task_2_expected_url}', got '{hl_addr}'")

                    # Verify Task 11
                    if uid == task_11_uid:
                        tasks_found += 1
                        hl_title = find_task_val(task, "Hyperlink")
                        hl_addr = find_task_val(task, "HyperlinkAddress")
                        
                        if hl_title == task_11_expected_title:
                            score += 20
                            feedback.append(f"Task 11 Title correct: {hl_title}")
                        else:
                            feedback.append(f"Task 11 Title incorrect. Expected '{task_11_expected_title}', got '{hl_title}'")
                            
                        if hl_addr == task_11_expected_url:
                            score += 20
                            feedback.append(f"Task 11 Path correct.")
                        else:
                            feedback.append(f"Task 11 Path incorrect. Expected '{task_11_expected_url}', got '{hl_addr}'")

            if tasks_found < 2:
                feedback.append(f"WARNING: Only found {tasks_found}/2 target tasks in the exported file.")

        except ET.ParseError:
            feedback.append("Output file is not valid XML.")
            score = 0 # Fail if XML is invalid

    except Exception as e:
        feedback.append(f"Error analyzing XML file: {str(e)}")
    finally:
        if os.path.exists(temp_xml.name):
            os.unlink(temp_xml.name)

    passed = score >= 80
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }