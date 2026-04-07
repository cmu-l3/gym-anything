#!/usr/bin/env python3
import json
import os
import re
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_wiki_embedded_dashboard(traj, env_info, task_info):
    """
    Verify the creation of a Wiki page with an embedded work packages table.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load metadata
    metadata = task_info.get('metadata', {})
    expected_header = metadata.get('expected_header', 'Current Active Tasks')
    
    # Retrieve result from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result file: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []
    
    # 1. Check Project and Page Existence
    if not result.get('project_found'):
        return {"passed": False, "score": 0, "feedback": "Target project 'DevOps Automation' not found."}

    if result.get('page_found'):
        score += 30
        feedback.append("Wiki page 'Live Incident Board' created.")
    else:
        return {"passed": False, "score": 0, "feedback": "Wiki page 'Live Incident Board' was not found."}

    content = result.get('content_text', '')
    status_id = result.get('status_id_in_progress')

    # 2. Check Header
    # Case insensitive check for the header
    if re.search(re.escape(expected_header), content, re.IGNORECASE):
        score += 10
        feedback.append(f"Header '{expected_header}' found.")
    else:
        feedback.append(f"Header '{expected_header}' missing.")

    # 3. Check Macro Presence
    # OpenProject macros look like {{work_packages(...)}}
    if '{{work_packages' in content:
        score += 30
        feedback.append("Work packages macro found.")
        
        # 4. Check Macro Filter Configuration
        # The macro usually looks like: {{work_packages(query_props: "...")}}
        # The props are JSON-like or URL encoded. We look for the status ID.
        # Example pattern: "f":[{"n":"status","o":"=","v":["1"]}]
        # We'll check if the status ID is present in the macro string.
        
        if status_id:
            # We look for the status ID quoted or as a raw number nearby "status" or within the macro
            # This is a heuristic since the serialization format can vary (JSON in string, etc.)
            # A robust check is seeing if the ID appears in the macro block.
            
            macro_block = content[content.find('{{work_packages'):]
            closing = macro_block.find('}}')
            if closing != -1:
                macro_block = macro_block[:closing+2]
            
            # Check for Status ID in the macro configuration
            # It typically appears as "v": ["<ID>"] or similar for filters
            if str(status_id) in macro_block:
                score += 30
                feedback.append(f"Macro appears to filter by status ID {status_id} ('In progress').")
            else:
                feedback.append(f"Macro found, but could not confirm filter for status ID {status_id}.")
        else:
            feedback.append("Could not verify filter: Status ID for 'In progress' unknown.")
            # Grant partial points if we can't verify strictness but macro is there
            score += 10 
    else:
        feedback.append("Work packages macro ({{work_packages...}}) not found in page content.")

    passed = score >= 60  # Pass if page created + macro used
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }