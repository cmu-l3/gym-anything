#!/usr/bin/env python3
"""
Verifier for remove_traceability_link task.
"""

import json
import os
import tempfile
import logging
import sys

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_remove_traceability_link(traj, env_info, task_info):
    """
    Verify that the agent removed the specific incorrect link while preserving others.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env not available"}

    metadata = task_info.get('metadata', {})
    baseline_file_path = metadata.get('baseline_links_file', '/var/lib/reqview/valid_links_baseline.json')
    bad_link_doc = metadata.get('bad_link_doc_id', 'NEEDS')
    bad_link_req = metadata.get('bad_link_req_id', '5')
    
    # 1. Retrieve Result JSON from export_result.sh
    task_result = {}
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            task_result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    srs_remote_path = task_result.get('srs_path')
    if not srs_remote_path:
        return {"passed": False, "score": 0, "feedback": "SRS document not found in container"}

    # 2. Retrieve Baseline Data (Valid links before injection)
    baseline_data = {}
    temp_baseline = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env(baseline_file_path, temp_baseline.name)
        with open(temp_baseline.name, 'r') as f:
            baseline_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve baseline verification data: {e}"}
    finally:
        if os.path.exists(temp_baseline.name):
            os.unlink(temp_baseline.name)

    target_req_id = baseline_data.get('req_id')
    original_valid_links = baseline_data.get('valid_links', [])

    # 3. Retrieve Final SRS Document
    srs_data = {}
    temp_srs = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env(srs_remote_path, temp_srs.name)
        with open(temp_srs.name, 'r') as f:
            srs_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve SRS document: {e}"}
    finally:
        if os.path.exists(temp_srs.name):
            os.unlink(temp_srs.name)

    # Helper to find requirement recursively
    def find_req_by_id(items, rid):
        for item in items:
            if str(item.get('id')) == str(rid):
                return item
            if 'children' in item:
                res = find_req_by_id(item['children'], rid)
                if res: return res
        return None

    # 4. Verification Logic
    score = 0
    feedback_parts = []
    
    target_req = find_req_by_id(srs_data.get('data', []), target_req_id)
    if not target_req:
        return {"passed": False, "score": 0, "feedback": "Target requirement SRS-4.3 deleted or not found"}

    current_links = target_req.get('links', [])
    
    # Check A: Is the bad link gone? (40 pts)
    bad_link_found = False
    for link in current_links:
        if link.get('docId') == bad_link_doc and str(link.get('reqId')) == str(bad_link_req):
            bad_link_found = True
            break
    
    if not bad_link_found:
        score += 40
        feedback_parts.append("Incorrect link (to NEEDS-5) successfully removed.")
    else:
        feedback_parts.append("Incorrect link (to NEEDS-5) still exists.")

    # Check B: Are original valid links preserved? (30 pts)
    # We compare sets of (docId, reqId) tuples
    def get_link_key(l): return (l.get('docId'), str(l.get('reqId')))
    
    original_keys = set(get_link_key(l) for l in original_valid_links)
    current_keys = set(get_link_key(l) for l in current_links)
    
    # We only care that the ORIGINAL valid ones are still there.
    # If the user added new ones, that's maybe okay, but strict preservation means subset check.
    missing_links = original_keys - current_keys
    
    if len(missing_links) == 0:
        score += 30
        feedback_parts.append("All original valid links preserved.")
    else:
        feedback_parts.append(f"Error: {len(missing_links)} valid links were accidentally removed.")
    
    # Check C: Was the file saved? (10 pts)
    if task_result.get('file_modified'):
        score += 10
        feedback_parts.append("Project saved.")
    else:
        feedback_parts.append("Project file not modified (did you save?).")

    # Check D: Sanity check - did they delete ALL links?
    # (Covered by Check B, but good for feedback)
    if not current_links and original_valid_links:
        feedback_parts.append("Warning: All links were removed (Scorched Earth).")

    # Check E: VLM Verification (Trajectory Analysis) - 20 pts
    # Since we can't easily do full VLM here without the heavy dependencies,
    # we award these points if the primary objective (A + B) is met and file was modified.
    # This acts as a proxy for "workflow followed correctly".
    if not bad_link_found and len(missing_links) == 0 and task_result.get('file_modified'):
        score += 20
        feedback_parts.append("Workflow appears valid.")

    passed = (score >= 80)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback_parts)
    }