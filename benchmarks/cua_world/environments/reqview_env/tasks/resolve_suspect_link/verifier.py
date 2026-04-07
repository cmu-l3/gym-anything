#!/usr/bin/env python3
"""
Verifier for resolve_suspect_link task.

Verifies that:
1. The traceability link still exists (was not deleted).
2. The link's synchronization timestamp matches the source requirement's timestamp (Suspect Cleared).
3. The source requirement text is still modified (Agent didn't revert the change).
"""

import json
import os
import sys
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_resolve_suspect_link(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Project paths in the container
    project_dir = "/home/ga/Documents/ReqView/suspect_link_project/documents"
    srs_path = f"{project_dir}/SRS.json"
    needs_path = f"{project_dir}/NEEDS.json"
    ids_path = "/tmp/suspect_ids.txt"

    # Temporary files for verification
    temp_srs = tempfile.NamedTemporaryFile(delete=False, suffix='.json').name
    temp_needs = tempfile.NamedTemporaryFile(delete=False, suffix='.json').name
    temp_ids = tempfile.NamedTemporaryFile(delete=False, suffix='.txt').name

    try:
        # Retrieve files
        try:
            copy_from_env(srs_path, temp_srs)
            copy_from_env(needs_path, temp_needs)
            copy_from_env(ids_path, temp_ids)
        except Exception as e:
            return {
                "passed": False, 
                "score": 0, 
                "feedback": f"Failed to retrieve project files (did you save the project?): {e}"
            }

        # Read IDs
        with open(temp_ids, 'r') as f:
            content = f.read().strip()
            if not content:
                return {"passed": False, "score": 0, "feedback": "Setup metadata missing"}
            srs_req_id, needs_req_id, target_doc_id = content.split(',')

        # Load JSONs
        with open(temp_srs, 'r') as f:
            srs_data = json.load(f)
        with open(temp_needs, 'r') as f:
            needs_data = json.load(f)

        score = 0
        feedback_parts = []

        # Helper to find requirement by ID
        def find_req(items, req_id):
            for item in items:
                if str(item.get('id')) == str(req_id):
                    return item
                if 'children' in item:
                    found = find_req(item['children'], req_id)
                    if found: return found
            return None

        # 1. Verify NEEDS modification persists (Anti-Gaming)
        # Agent shouldn't just revert the text to remove the flag
        needs_req = find_req(needs_data.get('children', []) or needs_data.get('data', []), needs_req_id)
        if not needs_req:
            return {"passed": False, "score": 0, "feedback": "Upstream requirement NEEDS-{} not found".format(needs_req_id)}
        
        needs_text = needs_req.get('text', '')
        if "(Updated by Stakeholder)" not in needs_text:
            return {
                "passed": False, 
                "score": 0, 
                "feedback": "FAILED: Upstream requirement text was reverted. You must accept the change, not undo it."
            }
        
        score += 20
        feedback_parts.append("Upstream change preserved")

        # 2. Find SRS requirement and Link
        srs_req = find_req(srs_data.get('children', []) or srs_data.get('data', []), srs_req_id)
        if not srs_req:
            return {"passed": False, "score": score, "feedback": "Downstream requirement SRS-{} not found".format(srs_req_id)}

        links = srs_req.get('links', [])
        target_link = None
        for link in links:
            # Check if this link points to our target NEEDS requirement
            l_doc = link.get('docId', '')
            l_src = str(link.get('srcId', ''))
            
            # Match strictly against what we recorded
            if l_doc == target_doc_id and l_src == str(needs_req_id):
                target_link = link
                break
        
        if not target_link:
             # The link was deleted!
             return {
                 "passed": False, 
                 "score": score, 
                 "feedback": "FAILED: The traceability link was deleted. You should clear the suspect flag, not delete the link."
             }
        
        score += 20 # Link exists
        feedback_parts.append("Link exists")

        # 3. Verify Suspect Status (Timestamp Match)
        # When suspect flag is cleared, ReqView updates the link's srcLastModified (or srcChangedOn)
        # to match the source requirement's lastModified (or changedOn).
        
        # Get source timestamp
        needs_ts = needs_req.get('lastModified') or needs_req.get('changedOn')
        
        # Get link timestamp
        link_ts = target_link.get('srcLastModified') or target_link.get('srcChangedOn') or target_link.get('srcHash')

        # In case ReqView uses hash, we check if they differ. 
        # But 'setup_task.sh' forced a timestamp update.
        # If suspect is active, link_ts will be OLDER than needs_ts (or different).
        # If suspect is cleared, link_ts will EQUAL needs_ts.

        logger.info(f"Source TS: {needs_ts}")
        logger.info(f"Link TS:   {link_ts}")

        if link_ts == needs_ts:
            score += 60
            feedback_parts.append("Suspect flag cleared successfully")
        else:
            feedback_parts.append("Suspect flag still active (timestamps mismatch)")

        passed = score >= 90
        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }

    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Verification error: {e}"}
    finally:
        # Cleanup
        for f in [temp_srs, temp_needs, temp_ids]:
            if os.path.exists(f):
                os.unlink(f)