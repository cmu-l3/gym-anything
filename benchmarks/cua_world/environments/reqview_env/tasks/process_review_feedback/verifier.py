#!/usr/bin/env python3
"""
Verifier for Process Review Feedback task.

Criteria:
1. SRS-15: Text must contain '500 ms' (requested change from 200 ms).
2. SRS-22: Text must contain 'shall' and NOT 'must' (compliance fix).
3. SRS-42: Text must contain 'AES-256' (specificity fix).
4. Project must be saved (file modification time check).
"""

import json
import os
import re
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def strip_html(text):
    """Remove HTML tags from ReqView text fields."""
    if not text:
        return ""
    clean = re.compile('<.*?>')
    return re.sub(clean, '', text)

def find_node_by_id_suffix(nodes, suffix):
    """Recursively find a node where ID ends with suffix."""
    for node in nodes:
        nid = str(node.get('id', ''))
        if nid == suffix or nid.endswith("-" + suffix):
            return node
        
        if 'children' in node:
            found = find_node_by_id_suffix(node['children'], suffix)
            if found:
                return found
    return None

def verify_process_review_feedback(traj, env_info, task_info):
    """
    Verify that the requirements text has been updated according to
    instructions found in the comments.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load Metadata
    metadata = task_info.get('metadata', {})
    project_file_path = metadata.get('project_file_path', '/home/ga/Documents/ReqView/review_feedback_project/documents/SRS.json')
    checks = metadata.get('checks', {})

    # Copy SRS.json from env
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env(project_file_path, temp_file.name)
        with open(temp_file.name, 'r') as f:
            srs_data = json.load(f)
    except Exception as e:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": f"Failed to retrieve or parse SRS.json: {str(e)}"
        }
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # Copy task result for timestamps
    task_result = {}
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            task_result = json.load(f)
    except:
        pass # Optional, mainly for timestamp check
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    # Begin Scoring
    score = 0
    feedback = []
    
    # Check 0: File Modification (Anti-gaming: did they save?)
    if task_result.get('file_modified', False):
        score += 10
        feedback.append("Project saved successfully.")
    else:
        feedback.append("Warning: Project file not modified (did you save?).")

    # Access the node structure
    # ReqView SRS structure usually has 'data' or 'children' at root
    nodes = srs_data.get('data', srs_data.get('children', []))
    
    # Check 1, 2, 3: Specific Requirements
    for req_suffix, criteria in checks.items():
        node = find_node_by_id_suffix(nodes, req_suffix)
        
        if not node:
            feedback.append(f"SRS-{req_suffix}: Not found in document.")
            continue
            
        raw_text = node.get('text', '')
        clean_text = strip_html(raw_text).lower()
        
        # Check 'contains'
        req_contains = criteria.get('contains', '').lower()
        if req_contains in clean_text:
            score += 30
            feedback.append(f"SRS-{req_suffix}: Correctly updated (found '{criteria['contains']}').")
        else:
            feedback.append(f"SRS-{req_suffix}: FAILED. Expected text to contain '{criteria['contains']}'.")

        # Check 'forbidden' (if applicable)
        req_forbidden = criteria.get('forbidden', '').lower()
        if req_forbidden and req_forbidden in clean_text:
            score -= 15 # Penalty for leaving old text
            score = max(0, score) # No negative total
            feedback.append(f"SRS-{req_suffix}: FAILED. Text still contains forbidden '{criteria['forbidden']}'.")
    
    # Final Result
    # Total possible: 10 + 30 + 30 + 30 = 100
    passed = score >= 90
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback),
        "details": {
            "checks": checks,
            "file_modified": task_result.get('file_modified')
        }
    }