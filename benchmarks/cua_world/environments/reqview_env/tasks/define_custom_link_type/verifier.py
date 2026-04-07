#!/usr/bin/env python3
"""
Verifier for define_custom_link_type task.

Criteria:
1. `project.json` contains a link type definition with id="mitigates".
2. `documents/RISKS.json` contains at least one link with type="mitigates".
3. Files were modified during the task execution.
"""

import json
import os
import tempfile
import logging
import time

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_define_custom_link_type(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    metadata = task_info.get('metadata', {})
    project_dir = metadata.get('project_dir', '/home/ga/Documents/ReqView/define_link_type_project')
    expected_id = metadata.get('expected_link_id', 'mitigates')
    expected_name = metadata.get('expected_link_name', 'Mitigates')

    project_json_path = os.path.join(project_dir, "project.json")
    risks_json_path = os.path.join(project_dir, "documents/RISKS.json")

    # Load task result metadata
    task_result = {}
    with tempfile.NamedTemporaryFile(delete=False, suffix='.json') as tmp:
        try:
            copy_from_env("/tmp/task_result.json", tmp.name)
            with open(tmp.name, 'r') as f:
                task_result = json.load(f)
        except Exception:
            pass # Task result might not exist if script failed, continue with checks
        finally:
            if os.path.exists(tmp.name):
                os.unlink(tmp.name)

    score = 0
    feedback_parts = []
    
    # 1. Verify Project Configuration (Link Type Definition)
    project_config_valid = False
    with tempfile.NamedTemporaryFile(delete=False, suffix='.json') as tmp:
        try:
            copy_from_env(project_json_path, tmp.name)
            with open(tmp.name, 'r') as f:
                project_data = json.load(f)
            
            link_types = project_data.get('linkTypes', [])
            target_link_type = next((lt for lt in link_types if lt.get('id') == expected_id), None)
            
            if target_link_type:
                score += 40
                feedback_parts.append(f"Link type ID '{expected_id}' defined correctly.")
                
                # Check Name
                if target_link_type.get('name') == expected_name:
                    score += 10
                    feedback_parts.append(f"Link type Name '{expected_name}' is correct.")
                else:
                    feedback_parts.append(f"Link type Name is '{target_link_type.get('name')}', expected '{expected_name}'.")
                
                project_config_valid = True
            else:
                feedback_parts.append(f"Link type ID '{expected_id}' NOT found in project configuration.")
                
        except Exception as e:
            feedback_parts.append(f"Failed to read project.json: {str(e)}")
        finally:
            if os.path.exists(tmp.name):
                os.unlink(tmp.name)

    # 2. Verify Link Usage in RISKS document
    link_created = False
    with tempfile.NamedTemporaryFile(delete=False, suffix='.json') as tmp:
        try:
            copy_from_env(risks_json_path, tmp.name)
            with open(tmp.name, 'r') as f:
                risks_data = json.load(f)
            
            # Helper to recursively find links
            def find_link_usage(nodes, link_id):
                count = 0
                for node in nodes:
                    links = node.get('links', [])
                    for link in links:
                        if link.get('type') == link_id:
                            count += 1
                    if 'children' in node:
                        count += find_link_usage(node['children'], link_id)
                return count

            usage_count = find_link_usage(risks_data.get('data', []), expected_id)
            
            if usage_count > 0:
                score += 40
                link_created = True
                feedback_parts.append(f"Found {usage_count} link(s) of type '{expected_id}' in RISKS document.")
            else:
                feedback_parts.append(f"No links of type '{expected_id}' found in RISKS document.")

        except Exception as e:
            feedback_parts.append(f"Failed to read RISKS.json: {str(e)}")
        finally:
            if os.path.exists(tmp.name):
                os.unlink(tmp.name)

    # 3. Verify modification timestamps
    if task_result.get('file_modified_during_task', False):
        score += 10
        feedback_parts.append("Project files modified during task.")
    else:
        feedback_parts.append("Warning: Files were not modified during the task window.")

    passed = (project_config_valid and link_created)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }