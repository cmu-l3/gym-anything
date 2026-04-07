#!/usr/bin/env python3
"""
Verifier for add_task_fixed_cost@1.
Checks if the MSPDI XML file contains the correct FixedCost values for specific tasks.
"""

import json
import os
import sys
import tempfile
import logging
from lxml import etree

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# MSPDI Namespace usually used by ProjectLibre/MS Project
NAMESPACES = {
    "ms": "http://schemas.microsoft.com/project"
}

def verify_add_task_fixed_cost(traj, env_info, task_info):
    """
    Verifies that the agent added fixed costs to the correct tasks and exported the XML.
    """
    # 1. Setup: Get copy_from_env
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Environment error: copy_from_env missing"}

    metadata = task_info.get('metadata', {})
    expected_path = metadata.get('expected_output_path', '/home/ga/Projects/updated_project_with_costs.xml')
    tasks_to_check = metadata.get('tasks_to_modify', [])

    # 2. Retrieve Result JSON
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task result: {str(e)}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    # 3. Check Basic Criteria (File Existence & Timing)
    score = 0
    feedback = []
    
    if not result_data.get("output_exists"):
        return {"passed": False, "score": 0, "feedback": "Output XML file was not created."}
    
    if not result_data.get("file_created_during_task"):
        feedback.append("Warning: Output file timestamp is older than task start (potential pre-existing file).")
    else:
        score += 10 # Points for creating a new file
        feedback.append("New output file created.")

    if result_data.get("output_size_bytes", 0) < 1000:
        return {"passed": False, "score": score, "feedback": "Output file is too small to be a valid project XML."}
    
    score += 10 # Points for valid file size

    # 4. Retrieve and Parse XML Content
    temp_xml = tempfile.NamedTemporaryFile(delete=False, suffix='.xml')
    try:
        copy_from_env(expected_path, temp_xml.name)
        
        # Parse XML
        try:
            tree = etree.parse(temp_xml.name)
            root = tree.getroot()
        except Exception as e:
            return {"passed": False, "score": score, "feedback": f"Output file is not valid XML: {str(e)}"}

        # Handle Namespace (ProjectLibre usually uses the MS Project schema)
        # We try with namespace first, fallback to local-name if needed
        ns = NAMESPACES
        
        # Find all tasks
        # ProjectLibre XML structure: <Project><Tasks><Task>...</Task></Tasks></Project>
        xml_tasks = root.xpath(".//ms:Task", namespaces=ns)
        if not xml_tasks:
            # Try without namespace if strictly namespaced lookup fails
            xml_tasks = root.xpath(".//Task")
        
        if not xml_tasks:
             return {"passed": False, "score": score, "feedback": "Valid XML, but no <Task> elements found."}

        score += 10 # Points for valid MSPDI structure

        # 5. Verify Specific Task Costs
        tasks_verified = 0
        total_tasks = len(tasks_to_check)
        points_per_task = 35  # 70 points total for the two tasks

        for target in tasks_to_check:
            target_name = target['name']
            expected_cost = target['expected_fixed_cost']
            tolerance = target.get('tolerance', 0.1)
            
            found_task = False
            task_cost_correct = False
            actual_cost = 0.0

            for t in xml_tasks:
                # Extract Name
                # Try namespaced
                name_node = t.find("ms:Name", namespaces=ns)
                if name_node is None: name_node = t.find("Name")
                
                if name_node is not None and name_node.text == target_name:
                    found_task = True
                    
                    # Extract FixedCost
                    cost_node = t.find("ms:FixedCost", namespaces=ns)
                    if cost_node is None: cost_node = t.find("FixedCost")
                    
                    if cost_node is not None and cost_node.text:
                        try:
                            actual_cost = float(cost_node.text)
                            # Check value
                            if abs(actual_cost - expected_cost) <= (expected_cost * tolerance):
                                task_cost_correct = True
                        except ValueError:
                            pass
                    break
            
            if found_task:
                if task_cost_correct:
                    score += points_per_task
                    tasks_verified += 1
                    feedback.append(f"✓ Task '{target_name}': Fixed Cost matches {expected_cost}.")
                else:
                    feedback.append(f"✗ Task '{target_name}': Found cost {actual_cost}, expected {expected_cost}.")
            else:
                feedback.append(f"✗ Task '{target_name}': Task not found in output XML.")

    except Exception as e:
        feedback.append(f"Error during XML verification: {str(e)}")
    finally:
        if os.path.exists(temp_xml.name):
            os.unlink(temp_xml.name)

    # 6. Final Evaluation
    # Threshold: Must have valid file (30 pts base) + at least one correct cost (35 pts) = 65
    passed = (score >= 65) and (tasks_verified >= 1)

    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }