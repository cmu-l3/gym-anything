#!/usr/bin/env python3
import json
import os
import tempfile
import xml.etree.ElementTree as ET
import logging

# Configure logging
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)

def verify_classify_resources_department(traj, env_info, task_info):
    """
    Verifies that resources were correctly classified into groups in the exported XML file.
    """
    
    # 1. Setup and Environment Check
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System Error: Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_path = metadata.get('expected_output_path', '/home/ga/Projects/categorized_resources.xml')
    target_assignments = metadata.get('target_assignments', {})
    untouched_sample = metadata.get('untouched_sample', 'David Brown')

    # 2. Retrieve Result JSON
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        if os.path.exists(temp_json.name): os.unlink(temp_json.name)
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task status: {str(e)}"}
    finally:
        if os.path.exists(temp_json.name): os.unlink(temp_json.name)

    # 3. Check Basic File Existence and Freshness
    if not result_data.get('output_exists'):
        return {"passed": False, "score": 0, "feedback": "Output XML file was not created."}
    
    if not result_data.get('output_fresh'):
        return {"passed": False, "score": 0, "feedback": "Output file exists but was not modified during the task (stale data)."}

    # 4. Retrieve and Parse XML File
    temp_xml = tempfile.NamedTemporaryFile(delete=False, suffix='.xml')
    try:
        copy_from_env(expected_path, temp_xml.name)
        
        # Parse XML
        # MSPDI XML usually defines a default namespace. We need to handle that.
        # ProjectLibre/MSPDI namespace is typically: http://schemas.microsoft.com/project
        
        # We'll use a safer parsing approach that ignores namespaces for simplicity 
        # or handles them if strictly necessary. 
        tree = ET.parse(temp_xml.name)
        root = tree.getroot()
        
        # Extract namespace if present
        ns = {}
        if root.tag.startswith('{'):
            uri = root.tag.split('}')[0].strip('{')
            ns = {'p': uri}
        
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Output file is not valid XML: {str(e)}"}
    finally:
        if os.path.exists(temp_xml.name): os.unlink(temp_xml.name)

    # 5. Verify Content
    # Score Breakdown:
    # - File Valid: 10 pts
    # - Each Correct Assignment (5 total): 15 pts each -> 75 pts
    # - Untouched Sample Check: 15 pts
    # Total: 100 pts
    
    score = 10
    feedback_details = []
    
    # Helper to find resource by name
    # We iterate manually to handle namespaced vs non-namespaced flexibility
    def find_resource_group(res_name):
        resources_tag = 'Resources' if not ns else 'p:Resources'
        resource_tag = 'Resource' if not ns else 'p:Resource'
        name_tag = 'Name' if not ns else 'p:Name'
        group_tag = 'Group' if not ns else 'p:Group'
        
        resources_node = root.find(resources_tag, ns)
        if resources_node is None:
            return None
            
        for res in resources_node.findall(resource_tag, ns):
            n = res.find(name_tag, ns)
            if n is not None and n.text == res_name:
                g = res.find(group_tag, ns)
                return g.text if g is not None else ""
        return None

    # Check Targets
    correct_count = 0
    for name, expected_group in target_assignments.items():
        actual_group = find_resource_group(name)
        
        if actual_group is None:
            feedback_details.append(f"Resource '{name}' not found in file.")
        elif actual_group == expected_group:
            correct_count += 1
            score += 15
        else:
            feedback_details.append(f"Incorrect group for '{name}': Expected '{expected_group}', Found '{actual_group}'.")

    # Check Negative (Untouched Resource)
    untouched_group = find_resource_group(untouched_sample)
    if untouched_group is None:
         # If the sample resource disappeared, that's bad, but maybe not 0 points bad
         feedback_details.append(f"Reference resource '{untouched_sample}' missing from file.")
    elif untouched_group == "" or untouched_group is None:
        score += 15
    else:
        # If they assigned a group to someone they shouldn't have
        feedback_details.append(f"Resource '{untouched_sample}' was incorrectly modified (Group set to '{untouched_group}').")

    # 6. Final Verdict
    passed = (score >= 85) # Allows for maybe one minor error or mess up but generally needs mostly correct
    
    feedback_str = "Verification Complete."
    if correct_count == len(target_assignments):
        feedback_str += " All target resources correctly classified."
    else:
        feedback_str += f" {correct_count}/{len(target_assignments)} resources correct."
        
    if feedback_details:
        feedback_str += " Issues: " + "; ".join(feedback_details)

    return {
        "passed": passed,
        "score": score,
        "feedback": feedback_str
    }