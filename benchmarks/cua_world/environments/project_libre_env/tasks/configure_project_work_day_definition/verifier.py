#!/usr/bin/env python3
"""
Verifier for configure_project_work_day_definition task.

Checks if the exported MSPDI XML file contains the correct project calendar settings:
- MinutesPerDay should be 600 (10 hours)
- MinutesPerWeek should be 2400 (40 hours)
"""

import json
import os
import tempfile
import xml.etree.ElementTree as ET
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_configure_project_work_day_definition(traj, env_info, task_info):
    """
    Verifies that the agent correctly updated the project work day definition.
    """
    # 1. Setup environment access
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: Copy function not available"}

    # 2. Load expected values from metadata
    metadata = task_info.get('metadata', {})
    expected_path = metadata.get('expected_output_path', '/home/ga/Projects/10h_day_project.xml')
    # 10 hours * 60 minutes = 600
    expected_minutes_day = metadata.get('expected_minutes_per_day', 600)
    # 40 hours * 60 minutes = 2400
    expected_minutes_week = metadata.get('expected_minutes_per_week', 2400)

    # 3. Retrieve result JSON
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task results: {str(e)}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    # 4. Check basic file criteria
    if not result_data.get('output_exists', False):
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "The output file '10h_day_project.xml' was not found in ~/Projects/."
        }

    if not result_data.get('file_created_during_task', False):
        return {
            "passed": False, 
            "score": 10, 
            "feedback": "A file was found, but it was not saved during the task execution time."
        }

    # 5. Retrieve and parse the XML file
    temp_xml = tempfile.NamedTemporaryFile(delete=False, suffix='.xml')
    score = 10
    feedback = []
    
    try:
        copy_from_env(expected_path, temp_xml.name)
        
        # Parse XML
        # MSPDI XML usually defines global settings under the root <Project> element
        tree = ET.parse(temp_xml.name)
        root = tree.getroot()
        
        # Handle namespaces if present (Microsoft Project XML often uses xmlns)
        # We'll try to find elements ignoring namespace if specific one fails, or use local-name
        ns = {}
        if 'schemas.microsoft.com' in root.tag:
            ns = {'p': root.tag.split('}')[0].strip('{')}
        
        # Helper to find text safely
        def find_val(elem_name):
            # Try direct child
            x = root.find(elem_name)
            if x is None and ns:
                x = root.find(f"p:{elem_name}", ns)
            if x is not None:
                return x.text
            # Fallback: iterate all children if namespace handling is tricky
            for child in root:
                if child.tag.endswith(f"}}{elem_name}") or child.tag == elem_name:
                    return child.text
            return None

        # Verify MinutesPerDay
        mins_per_day = find_val('MinutesPerDay')
        mins_per_week = find_val('MinutesPerWeek')
        
        # Verify Task Data Integrity (Anti-gaming)
        # Ensure tasks are still present
        tasks = root.find('Tasks')
        if tasks is None and ns:
            tasks = root.find('p:Tasks', ns)
        
        task_count = 0
        if tasks is not None:
            task_count = len(list(tasks))
            
        if task_count < 5:
            feedback.append("Project file appears empty or corrupted (too few tasks).")
        else:
            score += 20 # Points for preserving data integrity
            feedback.append(f"Project data preserved ({task_count} tasks).")

        # Evaluate MinutesPerDay
        if mins_per_day is not None:
            try:
                val = int(mins_per_day)
                if val == expected_minutes_day:
                    score += 50
                    feedback.append(f"SUCCESS: 'Hours per day' correctly set to 10 ({val} minutes).")
                else:
                    feedback.append(f"FAIL: 'Hours per day' is {val/60:.2f} hours (Expected: 10.00 hours).")
            except ValueError:
                feedback.append("FAIL: Invalid MinutesPerDay value in XML.")
        else:
            feedback.append("FAIL: Could not find 'MinutesPerDay' setting in XML.")

        # Evaluate MinutesPerWeek
        if mins_per_week is not None:
            try:
                val = int(mins_per_week)
                if val == expected_minutes_week:
                    score += 20
                    feedback.append(f"SUCCESS: 'Hours per week' correctly set/maintained at 40 ({val} minutes).")
                else:
                    feedback.append(f"FAIL: 'Hours per week' is {val/60:.2f} hours (Expected: 40.00 hours).")
            except ValueError:
                feedback.append("FAIL: Invalid MinutesPerWeek value in XML.")
        else:
            # If missing, it might default, but strictly we expect it present in MSPDI
            feedback.append("WARNING: Could not find 'MinutesPerWeek' setting.")

    except ET.ParseError:
        feedback.append("FATAL: Output file is not valid XML.")
    except Exception as e:
        feedback.append(f"FATAL: Error verifying XML content: {str(e)}")
    finally:
        if os.path.exists(temp_xml.name):
            os.unlink(temp_xml.name)

    passed = (score >= 70) # Threshold requires correct Day setting + integrity or Week setting
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }