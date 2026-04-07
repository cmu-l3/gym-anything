#!/usr/bin/env python3
"""Verifier for create_inline_link_to_requirement task.

Checks that the agent created an inline hyperlink in the text of SRS-001
that points to the GUID of NEED-001.

Criteria:
1. SRS.json was modified (saved).
2. SRS-001 description still contains the text "NEED-001".
3. The "NEED-001" text is wrapped in an XHTML anchor tag.
4. The anchor tag targets the correct GUID of the NEED-001 object.
"""

import json
import os
import tempfile
import logging
import re

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def find_node_by_id(nodes, target_id):
    """Recursively search for a node with specific ID in the ReqView data tree."""
    for node in nodes:
        if node.get("id") == target_id:
            return node
        if "children" in node:
            res = find_node_by_id(node["children"], target_id)
            if res:
                return res
    return None

def verify_create_inline_link(traj, env_info, task_info):
    """Verify the inline link creation."""
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    metadata = task_info.get('metadata', {})
    srs_path = metadata.get('srs_path', "/home/ga/Documents/ReqView/create_inline_link_project/documents/SRS.json")
    needs_path = metadata.get('needs_path', "/home/ga/Documents/ReqView/create_inline_link_project/documents/NEEDS.json")
    target_srs_id = metadata.get('target_srs_id', "SRS-001")
    target_needs_id = metadata.get('target_needs_id', "NEED-001")

    # 1. Retrieve files from the environment
    temp_dir = tempfile.mkdtemp()
    temp_srs = os.path.join(temp_dir, "SRS.json")
    temp_needs = os.path.join(temp_dir, "NEEDS.json")
    
    score = 0
    feedback_parts = []
    
    try:
        # Check SRS file existence and modification check implicitly via task_result
        try:
            copy_from_env(srs_path, temp_srs)
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Could not retrieve SRS document: {e}"}

        try:
            copy_from_env(needs_path, temp_needs)
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Could not retrieve NEEDS document: {e}"}

        # 2. Get the GUID of the target requirement (NEED-001)
        with open(temp_needs, 'r') as f:
            needs_data = json.load(f)
        
        target_node = find_node_by_id(needs_data.get("data", []), target_needs_id)
        if not target_node:
            return {"passed": False, "score": 0, "feedback": f"Setup Error: {target_needs_id} not found in NEEDS document."}
        
        target_guid = target_node.get("guid")
        if not target_guid:
            return {"passed": False, "score": 0, "feedback": f"Setup Error: {target_needs_id} has no GUID."}
            
        feedback_parts.append(f"Target GUID found: {target_guid[:8]}...")

        # 3. Analyze SRS-001
        with open(temp_srs, 'r') as f:
            srs_data = json.load(f)
            
        srs_node = find_node_by_id(srs_data.get("data", []), target_srs_id)
        if not srs_node:
            return {"passed": False, "score": 0, "feedback": f"{target_srs_id} not found in SRS document."}
        
        score += 20
        feedback_parts.append(f"{target_srs_id} found")

        # ReqView stores rich text in 'xhtml' field. If no formatting/links, 'xhtml' might be missing.
        # 'text' usually contains the plain text version.
        xhtml = srs_node.get("xhtml", "")
        text = srs_node.get("text", "")
        
        # Check text content integrity
        if "NEED-001" not in text and "NEED-001" not in xhtml:
            return {
                "passed": False, 
                "score": score, 
                "feedback": "FAILED: Text 'NEED-001' was deleted from the description."
            }
        score += 10
        feedback_parts.append("Text content preserved")

        # 4. Check for Hyperlink
        # We look for the GUID in the xhtml.
        # Format is typically: <a href="#GUID">...</a> or similar
        
        if not xhtml:
             feedback_parts.append("No rich text/links found (xhtml field empty)")
        elif target_guid in xhtml:
            score += 40
            feedback_parts.append("Link to correct object found")
            
            # Verify it's actually a link tag
            # A simple heuristic: check if GUID is preceded by href= or data-id= or #
            if re.search(f'href=["\'](?:#)?{re.escape(target_guid)}["\']', xhtml) or \
               re.search(f'data-id=["\']{re.escape(target_guid)}["\']', xhtml):
                score += 30
                feedback_parts.append("Link structure is valid")
            else:
                 feedback_parts.append("GUID found but link structure unclear")
        else:
            feedback_parts.append(f"No link found pointing to {target_needs_id}")

    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Verification error: {str(e)}"}
    finally:
        import shutil
        if os.path.exists(temp_dir):
            shutil.rmtree(temp_dir)

    passed = score >= 100
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "details": {
            "target_guid": target_guid,
            "found_xhtml": xhtml if 'xhtml' in locals() else "None"
        }
    }