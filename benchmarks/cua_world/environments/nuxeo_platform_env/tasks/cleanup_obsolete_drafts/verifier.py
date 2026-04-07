#!/usr/bin/env python3
"""
Verifier for cleanup_obsolete_drafts task.

Criteria:
1. Obsolete documents (Draft v1, Draft v2) must be in 'deleted' state (trashed).
2. Active/Final documents (Final, Beta Draft, Reference) must NOT be in 'deleted' state.
3. Anti-gaming: State changes must have happened during the task window.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_cleanup_obsolete_drafts(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Define expectations
    # state: 'deleted' means trashed. 'project' means active (default lifecycle state)
    targets = {
        "Project-Alpha-Draft-v1": {"should_trash": True, "desc": "Obsolete Draft v1"},
        "Project-Alpha-Draft-v2": {"should_trash": True, "desc": "Obsolete Draft v2"},
        "Project-Alpha-Final":    {"should_trash": False, "desc": "Final Version"},
        "Project-Beta-Draft":     {"should_trash": False, "desc": "Active Draft (Beta)"},
        "Regulatory-Reference":   {"should_trash": False, "desc": "Reference Doc"}
    }

    # Load result from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result file: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    documents = result.get('documents', [])
    doc_map = {d['name']: d for d in documents}
    
    score = 0
    max_score = 100
    points_per_doc = 20
    feedback_lines = []
    
    # Verify each document
    for name, criteria in targets.items():
        doc_data = doc_map.get(name)
        desc = criteria['desc']
        
        if not doc_data:
            feedback_lines.append(f"❌ {desc}: Document not found in verification data.")
            continue
            
        # In Nuxeo, trashed documents have state='deleted' OR is_trashed=True
        is_trashed = (doc_data.get('state') == 'deleted') or (doc_data.get('is_trashed') is True)
        should_trash = criteria['should_trash']
        
        if should_trash:
            if is_trashed:
                score += points_per_doc
                feedback_lines.append(f"✅ {desc}: Correctly trashed.")
            else:
                feedback_lines.append(f"❌ {desc}: Should be trashed, but is currently active.")
        else:
            if not is_trashed:
                score += points_per_doc
                feedback_lines.append(f"✅ {desc}: Correctly kept active.")
            else:
                feedback_lines.append(f"❌ {desc}: Was incorrectly trashed (Critical Error).")

    passed = (score == max_score)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": "\n".join(feedback_lines)
    }