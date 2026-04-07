#!/usr/bin/env python3
"""
Verifier for implement_safety_mitigation task.

Verifies:
1. User Need created with correct text.
2. System Requirement created with correct text and Type=Functional.
3. Test Case created with correct text.
4. Traceability: SRS -> NEEDS (satisfaction).
5. Traceability: SRS -> RISK-6 (mitigation).
6. Traceability: TESTS -> SRS (verification).

Uses copy_from_env to inspect the ReqView JSON document storage.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

DOCS_DIR = "/home/ga/Documents/ReqView/safety_mitigation_project/documents"

def _load_json_from_env(copy_func, filename):
    """Helper to copy and load a JSON file from the environment."""
    local_tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    remote_path = f"{DOCS_DIR}/{filename}"
    try:
        copy_func(remote_path, local_tmp.name)
        with open(local_tmp.name, 'r') as f:
            return json.load(f)
    except Exception as e:
        logger.warning(f"Could not load {filename}: {e}")
        return None
    finally:
        if os.path.exists(local_tmp.name):
            os.unlink(local_tmp.name)

def _find_item_by_text_content(items, text_fragment):
    """Recursively search for an item containing text_fragment."""
    if not items:
        return None
    for item in items:
        # Check text (HTML) and description
        # ReqView often stores text in "text" (HTML) or "description"
        content = (item.get('text', '') or '') + (item.get('description', '') or '')
        if text_fragment.lower() in content.lower():
            return item
        if 'children' in item:
            found = _find_item_by_text_content(item['children'], text_fragment)
            if found:
                return found
    return None

def _check_link(source_item, target_doc_id, target_req_id, expected_type=None):
    """Check if source_item has a link to target."""
    if not source_item or 'links' not in source_item:
        return False
    
    # Target req ID might be "RISK-6" or just "6" depending on how stored
    # Standardize to just the number if possible, or check both
    target_id_str = str(target_req_id)
    target_id_num = target_id_str.split('-')[-1] if '-' in target_id_str else target_id_str

    for link in source_item['links']:
        # docId check (case insensitive)
        link_doc = link.get('docId', '')
        # reqId check
        link_req = str(link.get('reqId', ''))
        
        doc_match = (link_doc.lower() == target_doc_id.lower())
        id_match = (link_req == target_id_str or link_req == target_id_num)
        
        if doc_match and id_match:
            # Type check if specified
            if expected_type:
                # Link type might be stored as "satisfies", "mitigates", etc.
                # OR key-based. We do a loose check.
                link_type = link.get('type', '').lower()
                if expected_type.lower() in link_type:
                    return True
            else:
                return True
    return False

def verify_safety_mitigation(traj, env_info, task_info):
    """Verify the safety mitigation implementation."""
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    
    # Load documents
    needs_doc = _load_json_from_env(copy_from_env, "NEEDS.json")
    srs_doc = _load_json_from_env(copy_from_env, "SRS.json")
    tests_doc = _load_json_from_env(copy_from_env, "TESTS.json")
    
    if not (needs_doc and srs_doc and tests_doc):
        return {"passed": False, "score": 0, "feedback": "Failed to read project documents (NEEDS, SRS, or TESTS missing)."}

    score = 0
    feedback = []

    # 1. Verify User Need
    need_text = metadata.get('need_text', 'exceeds safe limits')
    need_item = _find_item_by_text_content(needs_doc.get('data', []), need_text)
    
    if need_item:
        score += 15
        feedback.append(f"User Need created ({need_item.get('id')})")
    else:
        feedback.append("User Need not found")

    # 2. Verify SRS Requirement
    srs_text = metadata.get('srs_text', 'flashing red temperature icon')
    srs_item = _find_item_by_text_content(srs_doc.get('data', []), srs_text)
    
    if srs_item:
        score += 15
        feedback.append(f"SRS Requirement created ({srs_item.get('id')})")
        
        # Check Attribute
        req_type = srs_item.get('type', '') # Or wherever attribute 'Type' is stored. 
        # In ReqView standard template, 'type' is often a top-level key or inside values.
        # We will assume top level key or loose match.
        if metadata.get('srs_type', 'Functional').lower() in str(req_type).lower():
            score += 5
            feedback.append("SRS Type set to Functional")
        else:
            feedback.append(f"SRS Type incorrect (found '{req_type}')")
    else:
        feedback.append("SRS Requirement not found")

    # 3. Verify Test Case
    test_text = metadata.get('test_text', 'verify the red icon flashes')
    test_item = _find_item_by_text_content(tests_doc.get('data', []), test_text)
    
    if test_item:
        score += 15
        feedback.append(f"Test Case created ({test_item.get('id')})")
    else:
        feedback.append("Test Case not found")

    # 4. Verify Links
    # Only proceed if items were found
    
    # SRS -> NEEDS (Satisfaction)
    if srs_item and need_item:
        if _check_link(srs_item, "NEEDS", need_item.get('id'), "satisfaction"):
            score += 15
            feedback.append("Link: SRS -> NEEDS (Satisfaction) confirmed")
        else:
            feedback.append("Link: SRS -> NEEDS missing or wrong type")

    # SRS -> RISK (Mitigation)
    risk_id = metadata.get('risk_id', 'RISK-6')
    if srs_item:
        if _check_link(srs_item, "RISKS", risk_id, "mitigation"):
            score += 20
            feedback.append(f"Link: SRS -> {risk_id} (Mitigation) confirmed")
        else:
            feedback.append(f"Link: SRS -> {risk_id} missing or wrong type")
            
    # TESTS -> SRS (Verification)
    if test_item and srs_item:
        if _check_link(test_item, "SRS", srs_item.get('id'), "verification"):
            score += 15
            feedback.append("Link: TESTS -> SRS (Verification) confirmed")
        else:
            feedback.append("Link: TESTS -> SRS missing or wrong type")

    # Calculate Pass/Fail
    passed = score >= 75
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback),
        "details": {
            "need_id": need_item.get('id') if need_item else None,
            "srs_id": srs_item.get('id') if srs_item else None,
            "test_id": test_item.get('id') if test_item else None
        }
    }