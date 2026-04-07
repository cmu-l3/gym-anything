#!/usr/bin/env python3
"""
Verifier for update_published_document@1.
Checks if the 'HR-Intranet' section contains the version 2.0 proxy of the Remote Work Policy.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_update_published_document(traj, env_info, task_info):
    """
    Verify that the published document in HR-Intranet is Version 2.0.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Load Result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result data: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 2. Analyze Section Content
    children = result.get('section_children', [])
    source_version = result.get('source_doc_version', '2.0') # Expected 2.0+
    
    # Criteria
    has_policy = False
    correct_version = False
    is_proxy = False
    clean_state = True # No duplicates
    
    policy_docs = [d for d in children if "remote work policy" in d.get('title', '').lower() or "remoteworkpolicy" in d.get('title', '').lower()]
    
    if len(policy_docs) == 0:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "No 'Remote Work Policy' document found in the HR-Intranet section."
        }
    
    # Check for duplicates (obsolete versions)
    if len(policy_docs) > 1:
        clean_state = False
    
    # Analyze the best candidate (highest version)
    # If multiple exist, we check if AT LEAST ONE is correct.
    # Ideally, Nuxeo "Update" or "Republish" replaces the old proxy, but sometimes 
    # manual publishing creates a second proxy. The task description implies "Update".
    # We will score based on the presence of the correct one.
    
    target_doc = None
    # Find the 2.0 version
    for doc in policy_docs:
        v_label = doc.get('version_label', '0.0')
        if v_label == "2.0":
            target_doc = doc
            break
            
    if target_doc:
        has_policy = True
        correct_version = True
        is_proxy = target_doc.get('is_proxy', False)
    else:
        # If we didn't find 2.0, take the first one to report feedback
        target_doc = policy_docs[0]
        has_policy = True
        correct_version = False # It's likely 1.0
        is_proxy = target_doc.get('is_proxy', False)

    # 3. Calculate Score
    score = 0
    feedback_parts = []
    
    if has_policy:
        score += 20
        feedback_parts.append("Policy document found in section.")
    
    if correct_version:
        score += 40
        feedback_parts.append("Version 2.0 is published.")
    else:
        feedback_parts.append(f"Incorrect version found ({target_doc.get('version_label')}). Expected 2.0.")
        
    if is_proxy:
        score += 20
        feedback_parts.append("Document is a valid Proxy link.")
    else:
        feedback_parts.append("Document is NOT a proxy (did you upload a file instead of publishing?).")
        
    if clean_state and correct_version:
        score += 20
        feedback_parts.append("Old versions cleaned up.")
    elif not clean_state:
        feedback_parts.append("Multiple copies found (duplicates/obsolete versions).")

    # 4. Trajectory VLM Check (Optional Polish)
    # We can check if the agent visited the 'Publish' dialog
    
    passed = (score >= 80)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback_parts)
    }