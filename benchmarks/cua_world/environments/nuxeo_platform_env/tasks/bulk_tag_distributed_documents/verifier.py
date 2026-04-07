#!/usr/bin/env python3
"""
Verifier for bulk_tag_distributed_documents task.
Checks if specific Nuxeo documents have been tagged correctly.
"""

import json
import os
import tempfile
import logging
from datetime import datetime

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_bulk_tag_distributed_documents(traj, env_info, task_info):
    """
    Verify that 3 legacy documents have the 'to_archive' tag and
    the active document does NOT.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load metadata expectations
    metadata = task_info.get('metadata', {})
    target_tag = metadata.get('target_tag', 'to_archive').lower()

    # Load result file
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

    docs = result.get("documents", {})
    task_start = result.get("task_start", 0)

    # Define the mapping of keys in 'docs' to expected behavior
    # These keys match those exported in export_result.sh
    checks = [
        {"key": "legacy_project", "name": "Legacy Policy 2020", "should_tag": True},
        {"key": "legacy_template", "name": "Legacy Policy Template", "should_tag": True},
        {"key": "legacy_storage", "name": "Legacy Policy Draft", "should_tag": True},
        {"key": "active_policy", "name": "Active Policy 2024", "should_tag": False}
    ]

    score = 0
    max_score = 100
    points_per_doc = 25
    feedback_lines = []
    
    # helper to extract tags from Nuxeo doc JSON
    def get_tags(doc_data):
        if not doc_data or "properties" not in doc_data:
            return []
        
        # Tags are usually in 'nxtag:tags'. 
        # API returns list of objects: [{"label": "mytag", "username": "Administrator"}, ...]
        tags_raw = doc_data["properties"].get("nxtag:tags", [])
        tag_labels = []
        for t in tags_raw:
            if isinstance(t, dict):
                tag_labels.append(t.get("label", "").lower())
            elif isinstance(t, str):
                tag_labels.append(t.lower())
        return tag_labels

    # helper to check modification time (anti-gaming)
    def was_modified_during_task(doc_data):
        if not doc_data or "properties" not in doc_data:
            return False
        mod_str = doc_data["properties"].get("dc:modified") # ISO 8601 format e.g. 2023-10-27T10:00:00.00Z
        if not mod_str:
            return False
        try:
            # Simple parsing for ISO8601 subset often returned by Nuxeo
            # Python < 3.11 doesn't support 'Z' easily with fromisoformat, handle basics
            mod_str = mod_str.replace('Z', '+00:00')
            mod_ts = datetime.fromisoformat(mod_str).timestamp()
            return mod_ts > task_start
        except Exception:
            # If parsing fails, be lenient on timestamp check but strict on content
            return True

    all_passed = True

    for check in checks:
        key = check["key"]
        doc_data = docs.get(key)
        
        if not doc_data:
            feedback_lines.append(f"MISSING: Could not retrieve data for {check['name']}")
            all_passed = False
            continue

        tags = get_tags(doc_data)
        has_tag = target_tag in tags
        modified = was_modified_during_task(doc_data)

        if check["should_tag"]:
            if has_tag:
                # Full points if tagged. 
                # Ideally check modified timestamp too, but tagging might not update dc:modified in all Nuxeo versions/configs
                # We'll award points for presence of tag.
                score += points_per_doc
                feedback_lines.append(f"PASS: {check['name']} tagged correctly.")
            else:
                feedback_lines.append(f"FAIL: {check['name']} is missing tag '{target_tag}'.")
                all_passed = False
        else:
            # Distractor check
            if not has_tag:
                score += points_per_doc
                feedback_lines.append(f"PASS: {check['name']} (Distractor) correctly NOT tagged.")
            else:
                feedback_lines.append(f"FAIL: {check['name']} (Distractor) was INCORRECTLY tagged.")
                all_passed = False

    passed = (score == max_score)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": "\n".join(feedback_lines)
    }