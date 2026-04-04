#!/usr/bin/env python3
"""Verifier for create_traceability_link task.

Checks that the agent created a traceability link from SRS-245 to NEEDS-82.

Verification criteria:
1. SRS-245 exists in the SRS document
2. SRS-245 has a link entry with docId='NEEDS' and reqId=82 (or '82')
3. Link type is 'satisfies', 'implements', or equivalent
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

SRS_PATH = "/home/ga/Documents/ReqView/traceability_link_project/documents/SRS.json"


def _find_id(items, target_id):
    """Recursively search for an item by string or integer ID."""
    for item in items:
        item_id = item.get('id')
        if str(item_id) == str(target_id):
            return item
        if 'children' in item:
            result = _find_id(item['children'], target_id)
            if result:
                return result
    return None


def verify_create_traceability_link(traj, env_info, task_info):
    """Verify a traceability link was created from SRS-245 to NEEDS-82."""
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    metadata = task_info.get('metadata', {})
    source_req = metadata.get('source_req_id', 'SRS-245')
    target_req = metadata.get('target_req_id', 'NEEDS-82')

    # Parse source and target IDs (e.g. 'SRS-245' → '245', 'NEEDS-82' → '82')
    source_id = source_req.split('-')[-1] if '-' in source_req else source_req
    target_doc = target_req.split('-')[0] if '-' in target_req else 'NEEDS'
    target_id = target_req.split('-')[-1] if '-' in target_req else target_req

    # Copy SRS.json from VM
    tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env(SRS_PATH, tmp.name)
        with open(tmp.name) as f:
            srs = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read SRS.json: {e}"}
    finally:
        if os.path.exists(tmp.name):
            os.unlink(tmp.name)

    score = 0
    feedback_parts = []

    # Check 1: SRS-245 exists (30 points)
    s245 = _find_id(srs.get('data', []), source_id)
    if not s245:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"{source_req} not found in SRS document"
        }
    score += 30
    feedback_parts.append(f"{source_req} found")

    # Check 2: SRS-245 has any links (20 points)
    links = s245.get('links', [])
    if not links:
        feedback_parts.append(f"{source_req} has no traceability links")
        return {"passed": False, "score": score, "feedback": " | ".join(feedback_parts)}

    score += 20
    feedback_parts.append(f"{source_req} has {len(links)} link(s)")

    # Check 3: A link to NEEDS-82 exists (50 points)
    # Match on docId='NEEDS' and reqId=82 or '82' or 'NEEDS-82'
    matching_link = None
    for link in links:
        link_doc = str(link.get('docId', '')).upper()
        link_req = str(link.get('reqId', ''))
        if link_doc == target_doc.upper() and link_req == str(target_id):
            matching_link = link
            break
        # Also accept full form 'NEEDS-82'
        if link_req == target_req:
            matching_link = link
            break

    if matching_link:
        score += 50
        feedback_parts.append(
            f"Link to {target_req} found (type='{matching_link.get('type', 'unknown')}')"
        )
    else:
        actual_targets = [
            f"{l.get('docId', '')}-{l.get('reqId', '')}" for l in links
        ]
        feedback_parts.append(
            f"No link to {target_req} found. Existing links: {actual_targets}"
        )

    passed = score >= 100
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "details": {
            "source_req": source_req,
            "target_req": target_req,
            "link_count": len(links),
            "matching_link": matching_link,
        }
    }
