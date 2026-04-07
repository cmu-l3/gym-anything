#!/usr/bin/env python3
"""
Verifier for tag_documents task.
Verifies that specific tags were applied to 3 Nuxeo documents.
"""

import json
import os
import tempfile
import logging
from datetime import datetime

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_tag_documents(traj, env_info, task_info):
    """
    Verify the tagging task.
    """
    # 1. Setup and Load Data
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System Error: copy_from_env not available"}

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve result file: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    if 'error' in result:
        return {"passed": False, "score": 0, "feedback": f"Export script error: {result['error']}"}

    # 2. Define Expectations (from metadata)
    metadata = task_info.get('metadata', {}).get('documents', {})
    
    # Defaults if metadata missing
    defaults = {
        "Annual-Report-2023": ["annual-report", "finance", "2023"],
        "Project-Proposal": ["proposal", "project-planning"],
        "Q3-Status-Report": ["quarterly-report", "2023", "status"]
    }

    # 3. Scoring Logic
    score = 0
    max_score = 100
    feedback_lines = []
    
    # Points distribution
    # Total 100. Approx 33 pts per document.
    # Within doc: Existence (10%), Tags (90%)
    
    docs_data = result.get('documents', {})
    task_start = result.get('task_start', 0)
    
    # Iterate through each expected document
    docs_processed = 0
    
    for doc_key in ["Annual-Report-2023", "Project-Proposal", "Q3-Status-Report"]:
        expected_tags = metadata.get(doc_key, {}).get('expected_tags', defaults[doc_key])
        actual_data = docs_data.get(doc_key, {})
        
        if not actual_data.get('exists'):
            feedback_lines.append(f"[-] {doc_key}: Document NOT found or deleted.")
            continue

        docs_processed += 1
        
        # Verify timestamps (Anti-gaming)
        # Nuxeo timestamps are ISO8601 strings usually. 
        # We can loosely check if modified at all, or just rely on tag presence.
        # Strict timestamp parsing can be brittle with timezones, so we treat it as a secondary signal 
        # or verify it if possible. For now, we trust the tag presence mostly.
        
        actual_tags = [t.lower() for t in actual_data.get('tags', [])]
        expected_tags_lower = [t.lower() for t in expected_tags]
        
        # Check tags
        matched_tags = set(actual_tags).intersection(set(expected_tags_lower))
        missing_tags = set(expected_tags_lower) - set(actual_tags)
        
        # Scoring for this document
        # 3 documents, let's say 33 points each.
        # If all tags present: 33 pts.
        # Partial: proportional.
        
        doc_score = 0
        if len(expected_tags) > 0:
            match_ratio = len(matched_tags) / len(expected_tags)
            doc_score = 33.33 * match_ratio
        
        score += doc_score
        
        if len(missing_tags) == 0:
            feedback_lines.append(f"[+] {doc_key}: All tags correct {matched_tags}.")
        else:
            feedback_lines.append(f"[-] {doc_key}: Missing tags {missing_tags}. Found: {actual_tags}")

    # 4. Final Assessment
    score = min(round(score), 100)
    
    passed = False
    if score >= 60:
        passed = True
    
    feedback = "\n".join(feedback_lines)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": feedback
    }