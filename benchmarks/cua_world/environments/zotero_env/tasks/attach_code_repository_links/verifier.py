#!/usr/bin/env python3
"""
Verifier for attach_code_repository_links task.
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)

def verify_attach_code_repository_links(traj, env_info, task_info):
    """
    Verify that GitHub links were attached to the correct papers.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    targets = metadata.get('targets', [])

    # Load result
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    max_score = 100
    feedback_parts = []
    
    # Check each target
    for target in targets:
        title = target['title']
        expected_url = target['url']
        
        paper_data = result.get('papers', {}).get(title, {})
        
        if not paper_data.get('found'):
            feedback_parts.append(f"❌ Paper not found: '{title[:20]}...'")
            continue
            
        attachments = paper_data.get('attachments', [])
        found_link = False
        
        for att in attachments:
            # Normalize URLs (strip trailing slashes)
            att_url = att.get('url', '').strip().rstrip('/')
            exp_url_norm = expected_url.strip().rstrip('/')
            
            if att_url == exp_url_norm:
                found_link = True
                break
        
        if found_link:
            score += 30
            feedback_parts.append(f"✅ Link attached for '{title[:20]}...'")
        else:
            feedback_parts.append(f"❌ Missing/Wrong link for '{title[:20]}...'")

    # Check for clean state / no extra junk (10 points bonus/cleanup)
    # If we got all 3 right (90 pts), give the last 10.
    if score == 90:
        score += 10
        feedback_parts.append("✅ All links correct")
    
    # Pass threshold
    passed = score >= 70

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }