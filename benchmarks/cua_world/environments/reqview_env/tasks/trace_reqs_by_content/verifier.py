#!/usr/bin/env python3
"""
Verifier for trace_reqs_by_content task.

Verifies that the agent created the correct traceability links based on content analysis.
- SRS-901 (AES-256) -> NEEDS-801 (Privacy)
- SRS-902 (200ms) -> NEEDS-802 (Performance)
- SRS-903 (WCAG) -> NEEDS-803 (Inclusivity)
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def find_item_by_id(data, target_id):
    """Recursively search for an item with the given ID in the ReqView data structure."""
    if isinstance(data, list):
        for item in data:
            result = find_item_by_id(item, target_id)
            if result:
                return result
    elif isinstance(data, dict):
        if str(data.get("id", "")) == str(target_id):
            return data
        if "children" in data:
            result = find_item_by_id(data["children"], target_id)
            if result:
                return result
    return None

def check_link(srs_item, target_doc_prefix, target_req_id):
    """
    Check if srs_item has a link to target_req_id in target_doc.
    ReqView stores links like: {"docId": "NEEDS", "reqId": "801", "type": "satisfies"}
    """
    links = srs_item.get("links", [])
    for link in links:
        # docId might be the prefix (e.g., "NEEDS") or a UUID depending on version,
        # but in these single-file JSONs it's usually the document ID prefix.
        # reqId matches the target ID.
        link_doc = str(link.get("docId", ""))
        link_req = str(link.get("reqId", ""))
        
        # Check doc ID (allow exact match or if it's the prefix)
        doc_match = (link_doc == target_doc_prefix)
        
        # Check req ID
        req_match = (link_req == str(target_req_id))
        
        if doc_match and req_match:
            return True
            
    return False

def verify_trace_reqs_by_content(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    srs_path = metadata.get('srs_path', "/home/ga/Documents/ReqView/trace_content_project/documents/SRS.json")
    
    # Define expectations
    # SRS ID -> Expected NEED ID
    expectations = {
        "901": "801", # Encryption -> Privacy
        "902": "802", # Latency -> Performance
        "903": "803"  # WCAG -> Inclusivity
    }
    
    # Temporary file for SRS
    temp_srs = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env(srs_path, temp_srs.name)
        with open(temp_srs.name, 'r') as f:
            srs_data = json.load(f).get("data", [])
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load SRS document: {str(e)}"}
    finally:
        if os.path.exists(temp_srs.name):
            os.unlink(temp_srs.name)

    score = 0
    feedback_parts = []
    
    # Check each pair
    correct_links = 0
    incorrect_links = 0
    
    for srs_id, need_id in expectations.items():
        item = find_item_by_id(srs_data, srs_id)
        
        if not item:
            feedback_parts.append(f"SRS-{srs_id} not found (setup error?)")
            continue
            
        # Check if the correct link exists
        has_correct = check_link(item, "NEEDS", need_id)
        
        # Check for incorrect links (Anti-gaming: linking to everything)
        # We count total links. If > 1, and one is correct, we still penalize strictness slightly
        # or we check if it links to OTHER needs in the expectation list.
        
        links = item.get("links", [])
        linked_ids = [str(l.get("reqId")) for l in links]
        
        if has_correct:
            score += 30
            correct_links += 1
            feedback_parts.append(f"SRS-{srs_id} correctly linked to NEEDS-{need_id}")
        else:
            feedback_parts.append(f"SRS-{srs_id} NOT linked to NEEDS-{need_id}")
            
        # Check for false positives (links to other target IDs in our list)
        for other_need_id in expectations.values():
            if other_need_id != need_id and other_need_id in linked_ids:
                incorrect_links += 1
                feedback_parts.append(f"Incorrect link: SRS-{srs_id} -> NEEDS-{other_need_id}")

    # Bonus points for clean work (no extra links)
    if correct_links == 3 and incorrect_links == 0:
        score += 10
        feedback_parts.append("Perfect precision (no incorrect links)")
    elif incorrect_links > 0:
        score = max(0, score - (incorrect_links * 10))
        feedback_parts.append(f"Penalty for {incorrect_links} incorrect links")

    return {
        "passed": score >= 90,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "details": {
            "correct_links": correct_links,
            "incorrect_links": incorrect_links
        }
    }