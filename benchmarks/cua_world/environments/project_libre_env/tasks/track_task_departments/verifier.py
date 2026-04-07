#!/usr/bin/env python3
import json
import os
import tempfile
import xml.etree.ElementTree as ET

def verify_track_task_departments(traj, env_info, task_info):
    """
    Verifies that the user added the 'Text1' column and populated it 
    with specific department names for the first 5 tasks.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Environment copy function missing"}

    # 1. Retrieve Result JSON
    result_json_path = tempfile.mktemp(suffix=".json")
    try:
        copy_from_env("/tmp/task_result.json", result_json_path)
        with open(result_json_path, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {str(e)}"}
    finally:
        if os.path.exists(result_json_path):
            os.unlink(result_json_path)

    # 2. Basic Checks
    if not result_data.get("output_exists"):
        return {"passed": False, "score": 0, "feedback": "Output XML file not found at expected path."}
    
    if not result_data.get("file_valid_time"):
        return {"passed": False, "score": 0, "feedback": "Output file timestamp is too old (created before task start)."}

    # 3. Retrieve XML File
    xml_path = tempfile.mktemp(suffix=".xml")
    try:
        copy_from_env(result_data["output_path"], xml_path)
        tree = ET.parse(xml_path)
        root = tree.getroot()
    except ET.ParseError:
        return {"passed": False, "score": 10, "feedback": "Output file exists but is not valid XML."}
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve/read XML file: {str(e)}"}
    finally:
        if os.path.exists(xml_path):
            os.unlink(xml_path)

    # 4. XML Parsing Strategy
    # MSPDI Namespace usually: http://schemas.microsoft.com/project
    # We will try to handle namespaced and non-namespaced logic loosely or strict.
    # Usually standard python ET requires explicit namespace map if present.
    
    # Detect namespace
    ns = ""
    if root.tag.startswith("{"):
        ns = root.tag.split("}")[0] + "}"
    
    # Expected Data from Metadata
    expected_tags = task_info.get("metadata", {}).get("expected_tags", {
        "1": "Product",
        "2": "Engineering",
        "3": "Engineering",
        "4": "Design",
        "5": "Management"
    })

    score = 10 # Base score for valid XML
    feedback = ["File is valid XML."]
    
    # 5. Check Definition of Text1 (Optional but good for 20 points)
    # In MSPDI, Custom fields are defined in <ExtendedAttributes>
    # FieldID for Text1 is typically 188743731
    found_definition = False
    text1_field_id = None
    
    ext_attrs = root.find(f"{ns}ExtendedAttributes")
    if ext_attrs is not None:
        for attr in ext_attrs.findall(f"{ns}ExtendedAttribute"):
            field_id = attr.findtext(f"{ns}FieldID")
            alias = attr.findtext(f"{ns}Alias")
            # 188743731 is Text1. We check if it exists.
            if field_id == "188743731":
                found_definition = True
                text1_field_id = field_id
                score += 20
                feedback.append("Text1 custom field definition found.")
                break
    
    if not found_definition:
        feedback.append("Warning: Text1 field definition not explicitly found in ExtendedAttributes (might affect scoring if not using standard ID).")

    # 6. Check Task Values (70 points distributed)
    # We look for <Task> -> <ExtendedAttribute> -> <FieldID> == 188743731 -> <Value>
    
    tasks_root = root.find(f"{ns}Tasks")
    if tasks_root is None:
        return {"passed": False, "score": score, "feedback": "No tasks found in XML."}

    tasks_correct = 0
    total_tasks_to_check = len(expected_tags)
    points_per_task = 14 # 70 / 5
    
    # Map UID to Task Element
    tasks_map = {}
    for t in tasks_root.findall(f"{ns}Task"):
        uid = t.findtext(f"{ns}UID")
        tasks_map[uid] = t

    for uid, expected_val in expected_tags.items():
        task = tasks_map.get(uid)
        if task is None:
            feedback.append(f"Task UID {uid} not found.")
            continue
            
        # Find the extended attribute value
        actual_val = None
        for ea in task.findall(f"{ns}ExtendedAttribute"):
            fid = ea.findtext(f"{ns}FieldID")
            val = ea.findtext(f"{ns}Value")
            # We assume Text1 (188743731)
            if fid == "188743731":
                actual_val = val
                break
        
        if actual_val and actual_val.lower() == expected_val.lower():
            score += points_per_task
            tasks_correct += 1
        else:
            feedback.append(f"Task {uid}: Expected '{expected_val}', found '{actual_val}'.")

    feedback.append(f"Tasks tagged correctly: {tasks_correct}/{total_tasks_to_check}")

    # Final Verdict
    passed = (score >= 80)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }