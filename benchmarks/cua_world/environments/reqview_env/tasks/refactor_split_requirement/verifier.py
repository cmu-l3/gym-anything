#!/usr/bin/env python3
"""
Verifier for refactor_split_requirement task.

Checks:
1. SRS-6 text no longer contains the second clause ("transmit...").
2. SRS-6 text still contains the first clause ("encrypt...").
3. A NEW requirement exists containing the second clause.
4. The new requirement does NOT contain the first clause (no duplication).
5. (Bonus) The new requirement is immediately after SRS-6.
"""

import json
import os
import re
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Constants
SRS_REL_PATH = "documents/SRS.json"
PROJECT_BASE = "/home/ga/Documents/ReqView/refactor_split_req_project"

def _strip_html(text):
    """Remove HTML tags from text."""
    if not text: 
        return ""
    return re.sub(r'<[^>]+>', '', str(text)).strip()

def _find_req_by_id(items, target_id):
    """Recursively find item by ID."""
    for item in items:
        if str(item.get('id')) == str(target_id):
            return item
        if 'children' in item:
            found = _find_req_by_id(item['children'], target_id)
            if found:
                return found
    return None

def _find_req_by_text(items, search_text, exclude_id=None):
    """Find a requirement containing search_text, excluding a specific ID."""
    for item in items:
        # Check exclusion
        if exclude_id and str(item.get('id')) == str(exclude_id):
            pass # Skip checking this item
        else:
            text = _strip_html(item.get('text', ''))
            if search_text.lower() in text.lower():
                return item
        
        # Recurse
        if 'children' in item:
            found = _find_req_by_text(item['children'], search_text, exclude_id)
            if found:
                return found
    return None

def _check_adjacency(items, id1, id2):
    """Check if id2 immediately follows id1 in the same list."""
    # This requires traversing until we find the list containing id1
    for i in range(len(items)):
        item = items[i]
        # Check if this list contains id1
        if str(item.get('id')) == str(id1):
            # Found id1, check next sibling
            if i + 1 < len(items):
                if str(items[i+1].get('id')) == str(id2):
                    return True
            return False # id1 found but id2 not next
        
        # Recurse
        if 'children' in item:
            if _check_adjacency(item['children'], id1, id2):
                return True
    return False

def verify_refactor_split_requirement(traj, env_info, task_info):
    """Verify that SRS-6 was split into two requirements."""
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    target_id = metadata.get('target_id', '6')
    part1_marker = "AES-256"
    part2_marker = "TLS 1.3"
    
    # 1. Get result metadata (timestamps etc)
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            task_result = json.load(f)
    except Exception:
        task_result = {}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    # 2. Get the SRS document
    srs_full_path = os.path.join(PROJECT_BASE, SRS_REL_PATH)
    temp_srs = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env(srs_full_path, temp_srs.name)
        with open(temp_srs.name, 'r') as f:
            srs_doc = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve SRS document: {str(e)}"}
    finally:
        if os.path.exists(temp_srs.name):
            os.unlink(temp_srs.name)

    score = 0
    feedback_parts = []
    
    # Check File Modification (Antigaming) - 10 pts
    if task_result.get("file_modified_during_task"):
        score += 10
        feedback_parts.append("Project saved")
    else:
        feedback_parts.append("Project NOT saved (no file modification)")

    # 1. Verify SRS-6 (Original) Modified correctly
    req_srs6 = _find_req_by_id(srs_doc.get('data', []), target_id)
    
    if not req_srs6:
        return {
            "passed": False, 
            "score": score, 
            "feedback": f"SRS-{target_id} not found in document!"
        }
    
    srs6_text = _strip_html(req_srs6.get('text', ''))
    
    # Check if SRS-6 still has Part 1 (Encryption) - 15 pts
    if part1_marker.lower() in srs6_text.lower():
        score += 15
        feedback_parts.append(f"SRS-{target_id} retains encryption clause")
    else:
        feedback_parts.append(f"SRS-{target_id} MISSING encryption clause")
        
    # Check if SRS-6 removed Part 2 (Transmission) - 15 pts
    if part2_marker.lower() not in srs6_text.lower() and "transmit" not in srs6_text.lower():
        score += 15
        feedback_parts.append(f"SRS-{target_id} cleaned of transmission clause")
    else:
        feedback_parts.append(f"SRS-{target_id} STILL contains transmission clause")

    # 2. Verify New Requirement Created
    # Search for requirement containing Part 2 (TLS 1.3) but NOT ID 6
    new_req = _find_req_by_text(srs_doc.get('data', []), part2_marker, exclude_id=target_id)
    
    if new_req:
        score += 30
        new_id = new_req.get('id', 'unknown')
        new_text = _strip_html(new_req.get('text', ''))
        feedback_parts.append(f"New requirement found (SRS-{new_id}) with TLS clause")
        
        # 3. Verify Atomicity (No duplication) - 10 pts
        if part1_marker.lower() not in new_text.lower():
            score += 10
            feedback_parts.append("New requirement is atomic (no duplication)")
        else:
            feedback_parts.append("New requirement is a DUPLICATE (contains AES-256 clause)")
            
        # 4. Verify Adjacency - 20 pts
        # We need to find if new_req is the immediate next sibling of req_srs6
        if _check_adjacency(srs_doc.get('data', []), target_id, new_id):
            score += 20
            feedback_parts.append("New requirement correctly placed immediately after SRS-6")
        else:
            feedback_parts.append("New requirement is NOT immediately following SRS-6")
            
    else:
        feedback_parts.append("No new requirement found with 'TLS 1.3' clause")

    passed = score >= 80
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "details": {
            "srs6_text": srs6_text,
            "new_req_id": new_req.get('id') if new_req else None
        }
    }