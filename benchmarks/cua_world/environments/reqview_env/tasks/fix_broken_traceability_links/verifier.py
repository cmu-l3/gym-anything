#!/usr/bin/env python3
"""Verifier for fix_broken_traceability_links task.

Verifies that:
1. No links to 'LEGACY' document exist in the SRS.
2. The requirements that held those links still exist (weren't deleted).
3. Valid links (not to LEGACY) still exist (didn't delete all links).
4. The file was actually saved/modified.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

SRS_PATH = "/home/ga/Documents/ReqView/fix_broken_links_project/documents/SRS.json"
BROKEN_PREFIX = "LEGACY"


def get_all_requirements(items, req_list=None):
    """Recursively flatten requirement hierarchy."""
    if req_list is None:
        req_list = []
    
    for item in items:
        req_list.append(item)
        if 'children' in item:
            get_all_requirements(item['children'], req_list)
    return req_list


def verify_fix_broken_traceability_links(traj, env_info, task_info):
    """Verify removal of broken links."""
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    # Load result metadata
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name) as f:
            task_result = json.load(f)
    except Exception:
        task_result = {}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    # Load SRS JSON
    temp_srs = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env(SRS_PATH, temp_srs.name)
        with open(temp_srs.name) as f:
            srs_data = json.load(f)
    except Exception as e:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": f"Failed to load SRS.json for verification: {e}"
        }
    finally:
        if os.path.exists(temp_srs.name):
            os.unlink(temp_srs.name)

    score = 0
    feedback_parts = []
    
    # Flatten requirements
    all_reqs = get_all_requirements(srs_data.get('data', []))
    total_req_count = len(all_reqs)
    
    # 1. Check for Broken Links (Primary Goal) - 50 points
    broken_links_found = 0
    broken_link_details = []
    
    for req in all_reqs:
        links = req.get('links', [])
        for link in links:
            doc_id = str(link.get('docId', ''))
            req_id = str(link.get('reqId', ''))
            if BROKEN_PREFIX in doc_id or BROKEN_PREFIX in req_id:
                broken_links_found += 1
                broken_link_details.append(f"{req.get('id')}->{doc_id}-{req_id}")

    if broken_links_found == 0:
        score += 50
        feedback_parts.append("All broken links removed successfully")
    else:
        feedback_parts.append(f"Found {broken_links_found} broken links remaining: {', '.join(broken_link_details[:3])}...")

    # 2. Check for Valid Links (Preservation) - 20 points
    # Ensure we didn't just delete ALL links
    valid_links_count = 0
    for req in all_reqs:
        links = req.get('links', [])
        for link in links:
            doc_id = str(link.get('docId', ''))
            if BROKEN_PREFIX not in doc_id:
                valid_links_count += 1

    if valid_links_count > 0:
        score += 20
        feedback_parts.append(f"Preserved {valid_links_count} valid links")
    else:
        feedback_parts.append("WARNING: No valid links found (did you delete all links?)")

    # 3. Check Requirement Count (Preservation) - 20 points
    # Setup script heuristic targets 5th and 15th item.
    # We expect roughly the same number of requirements as standard example project (~50-100)
    # If count is < 10, agent likely deleted requirements instead of links.
    if total_req_count > 20:
        score += 20
        feedback_parts.append(f"Requirement structure intact ({total_req_count} items)")
    else:
        feedback_parts.append(f"WARNING: Low requirement count ({total_req_count}). Did you delete requirements?")

    # 4. Anti-Gaming: File Modification - 10 points
    if task_result.get("file_modified_during_task", False):
        score += 10
        feedback_parts.append("Project saved successfully")
    else:
        feedback_parts.append("Project file not modified (did you save?)")

    passed = (score >= 90) and (broken_links_found == 0)

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "details": {
            "broken_links_remaining": broken_links_found,
            "valid_links_remaining": valid_links_count,
            "total_requirements": total_req_count
        }
    }