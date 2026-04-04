#!/usr/bin/env python3
"""
Verifier for apt_package_management_dfd task.
Checks for correct DFD structure, page count, shape types, and domain content.
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)

def verify_apt_package_management_dfd(traj, env_info, task_info):
    """
    Verify the APT Data Flow Diagram.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Retrieve result from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # --- Criterion 1: File Existence & Anti-Gaming (10 pts) ---
    if result.get('file_exists') and result.get('file_modified_after_start'):
        score += 10
        feedback_parts.append("File saved successfully")
    elif result.get('file_exists'):
        score += 5
        feedback_parts.append("File exists but not modified (stale?)")
    else:
        return {"passed": False, "score": 0, "feedback": "No output file found"}

    if result.get('file_size', 0) < 500:
        return {"passed": False, "score": score, "feedback": "File is empty/corrupt"}

    # --- Criterion 2: Multi-page Requirement (10 pts) ---
    num_pages = result.get('num_pages', 0)
    if num_pages >= 2:
        score += 10
        feedback_parts.append("Multi-page diagram detected")
    else:
        feedback_parts.append(f"Only {num_pages} page(s) found (requires 2)")

    # --- Criterion 3: Processes (Ellipses) (15 pts) ---
    # Expecting 5 subprocesses + 1 context process = 6 total ideally
    num_processes = result.get('num_processes', 0)
    if num_processes >= 4:
        score += 15
        feedback_parts.append(f"Processes: {num_processes} identified")
    elif num_processes >= 2:
        score += 7
        feedback_parts.append(f"Processes: {num_processes} (partial)")
    else:
        feedback_parts.append("Missing process shapes (ellipses)")

    # --- Criterion 4: Data Stores (Cylinders/Datastores) (12 pts) ---
    # Expecting 4 stores
    num_datastores = result.get('num_datastores', 0)
    if num_datastores >= 3:
        score += 12
        feedback_parts.append(f"Data Stores: {num_datastores} identified")
    elif num_datastores >= 1:
        score += 6
        feedback_parts.append("Data Stores: Few data stores found")
    else:
        feedback_parts.append("Missing data store shapes (cylinders)")

    # --- Criterion 5: External Entities (Rectangles) (8 pts) ---
    # Expecting 3 or 4
    num_entities = result.get('num_entities', 0)
    if num_entities >= 2:
        score += 8
        feedback_parts.append("External Entities present")
    else:
        feedback_parts.append("Few external entity shapes found")

    # --- Criterion 6: Connectivity (Edges) (12 pts) ---
    num_edges = result.get('num_edges', 0)
    if num_edges >= 12:
        score += 12
        feedback_parts.append(f"Good connectivity ({num_edges} edges)")
    elif num_edges >= 6:
        score += 5
        feedback_parts.append(f"Partial connectivity ({num_edges} edges)")
    else:
        feedback_parts.append("Sparse connectivity")

    # --- Criterion 7: Content Accuracy (Keywords) (23 pts) ---
    # Keywords: parse, fetch, resolve, download, verify, install, sources, list, cache, dpkg...
    found_keywords = result.get('keywords_found', [])
    unique_keywords = len(set(found_keywords))
    
    # Process verbs (Parse, Fetch, etc)
    process_kw = [k for k in found_keywords if k in ["parse", "fetch", "resolve", "download", "verify", "install"]]
    # Data nouns (Sources, List, Cache, Dpkg)
    data_kw = [k for k in found_keywords if k in ["sources", "list", "cache", "dpkg", "status"]]
    
    kw_score = 0
    if len(set(process_kw)) >= 4: kw_score += 8
    if len(set(data_kw)) >= 3: kw_score += 8
    if len(set(found_keywords)) >= 10: kw_score += 7
    
    score += kw_score
    feedback_parts.append(f"Content terms found: {unique_keywords}")

    # --- Criterion 8: PNG Export (10 pts) ---
    if result.get('png_exists') and result.get('png_size', 0) > 3000:
        score += 10
        feedback_parts.append("PNG exported")
    elif result.get('png_exists'):
        score += 5
        feedback_parts.append("PNG small/empty")
    else:
        feedback_parts.append("PNG export missing")

    # Final logic
    passed = score >= 55 and num_pages >= 2 and num_processes >= 1
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }