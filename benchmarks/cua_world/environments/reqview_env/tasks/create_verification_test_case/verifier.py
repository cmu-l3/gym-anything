#!/usr/bin/env python3
"""
Verifier for create_verification_test_case task.

Checks:
1. TESTS.json file was modified (anti-gaming).
2. A NEW object was created in TESTS.json (count > initial).
3. The new object contains the specific text "Verify SRS-3 functionality".
4. The new object has a traceability link to SRS-3.
"""

import json
import os
import re
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_verification_test_case(traj, env_info, task_info):
    # 1. Setup
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env not available"}

    metadata = task_info.get('metadata', {})
    target_text = metadata.get('target_text', 'Verify SRS-3 functionality')
    target_link_req = metadata.get('target_link_req_id', 'SRS-3') # e.g., SRS-3
    target_link_doc = metadata.get('target_link_doc_id', 'SRS')   # e.g., SRS

    # Extract target ID number (assuming format PREFIX-NUMBER)
    # If SRS-3, we look for id '3' in document 'SRS'
    target_id_num = target_link_req.split('-')[-1] if '-' in target_link_req else target_link_req

    # 2. Retrieve Files from Environment
    # We need: task_result.json, TESTS.json, initial_test_count.txt
    
    # Get task result metadata
    task_result = {}
    with tempfile.NamedTemporaryFile(delete=False, suffix='.json') as f:
        try:
            copy_from_env("/tmp/task_result.json", f.name)
            with open(f.name) as tr:
                task_result = json.load(tr)
        except Exception:
            return {"passed": False, "score": 0, "feedback": "Failed to retrieve task result metadata"}
        finally:
            os.unlink(f.name)

    # Check file modification timestamp
    if not task_result.get('tests_file_modified', False):
        return {"passed": False, "score": 0, "feedback": "Project was not saved (TESTS.json not modified)"}

    # Get initial count
    initial_count = 0
    with tempfile.NamedTemporaryFile(delete=False, suffix='.txt') as f:
        try:
            copy_from_env("/tmp/initial_test_count.txt", f.name)
            with open(f.name) as ic:
                initial_count = int(ic.read().strip())
        except Exception:
            logger.warning("Could not read initial count, assuming 0")
        finally:
            os.unlink(f.name)

    # Get TESTS.json content
    tests_json_path = task_result.get('tests_json_path')
    tests_data = {}
    with tempfile.NamedTemporaryFile(delete=False, suffix='.json') as f:
        try:
            copy_from_env(tests_json_path, f.name)
            with open(f.name) as td:
                tests_data = json.load(td)
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Failed to retrieve TESTS.json: {str(e)}"}
        finally:
            os.unlink(f.name)

    # 3. Verification Logic
    score = 0
    feedback = []

    # Flatten the document tree to a list of objects
    def flatten_objs(items):
        flat = []
        for item in items:
            flat.append(item)
            if 'children' in item:
                flat.extend(flatten_objs(item['children']))
        return flat

    all_tests = flatten_objs(tests_data.get('data', []))
    final_count = len(all_tests)

    # Criterion 1: Object Created (30 pts)
    if final_count > initial_count:
        score += 30
        feedback.append("New test object created")
    else:
        feedback.append(f"No new objects found (Count: {final_count} vs Initial: {initial_count})")

    # Helper to clean HTML from text
    def clean_text(t):
        return re.sub(r'<[^>]+>', '', str(t)).strip()

    # Find the target object
    target_obj = None
    for obj in all_tests:
        # Check text (clean HTML)
        obj_text = clean_text(obj.get('text', '') or obj.get('description', '') or '')
        if target_text.lower() in obj_text.lower():
            target_obj = obj
            break

    # Criterion 2: Description Match (30 pts)
    if target_obj:
        score += 30
        feedback.append(f"Found object with text '{target_text}'")
    else:
        feedback.append(f"No object found containing text '{target_text}'")
        return {"passed": False, "score": score, "feedback": ". ".join(feedback)}

    # Criterion 3: Traceability Link (30 pts)
    # We need a link where docId matches target_link_doc (SRS) and reqId matches target_id_num (3)
    links = target_obj.get('links', [])
    link_found = False
    
    for link in links:
        # ReqView links usually look like: {"srcId": "...", "destId": "...", "type": "..."} 
        # OR embedded in the requirement object as {"docId": "SRS", "reqId": "3"}
        
        # Check docId/reqId format (common in ReqView JSON exports)
        l_doc = link.get('docId', '')
        l_req = str(link.get('reqId', ''))
        
        # Check for absolute ID match or relative match
        # Sometimes docId is the UUID of the document, sometimes the prefix.
        # We'll check if the link *looks* like it points to SRS-3
        
        if (l_doc == target_link_doc or 'SRS' in l_doc) and (l_req == target_id_num):
            link_found = True
            break
            
    if link_found:
        score += 30
        feedback.append(f"Traceability link to {target_link_req} found")
    else:
        feedback.append(f"No link found to {target_link_req}. Found links: {links}")

    # Criterion 4: File Persisted (10 pts)
    # Already checked at start, just adding points
    score += 10
    feedback.append("Project saved successfully")

    return {
        "passed": score >= 90,
        "score": score,
        "feedback": ". ".join(feedback)
    }