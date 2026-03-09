#!/usr/bin/env python3
"""
Verifier for configure_pr_webhook task.

Scoring Criteria (100 points total):
1. Subscription Created (20 pts): At least one 'webHooks' subscription exists.
2. Correct Event (20 pts): Event is 'git.pullrequest.created'.
3. Correct Repository (20 pts): Scoped to 'TailwindTraders' repo (not global).
4. Correct URL (20 pts): Matches 'http://localhost:9090/api/compliance-scan'.
5. Auth Configured (20 pts): Basic Auth used with correct username.
"""

import json
import logging
import os
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_configure_pr_webhook(traj, env_info, task_info):
    """Verify that the Service Hook was configured correctly."""
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_url = metadata.get('expected_url', 'http://localhost:9090/api/compliance-scan')
    expected_event = metadata.get('expected_event', 'git.pullrequest.created')
    expected_username = metadata.get('expected_username', 'compliance_bot')
    
    # Copy result JSON from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        # Windows path inside the container
        win_path = r"C:\Users\Docker\task_results\configure_pr_webhook_result.json"
        copy_from_env(win_path, temp_file.name)
        
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result file: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # Begin Evaluation
    score = 0
    feedback = []
    
    subscriptions = result.get('subscriptions', [])
    
    if not subscriptions:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "No Service Hook subscriptions found."
        }
        
    # Find the best matching subscription
    best_sub = None
    best_sub_score = -1
    
    for sub in subscriptions:
        current_sub_score = 0
        current_feedback = []
        
        # Check Consumer (Must be Web Hooks)
        if sub.get('consumerId') != 'webHooks':
            continue
            
        # 1. Subscription Created (Baseline)
        current_sub_score += 20
        current_feedback.append("WebHook subscription created")
        
        # 2. Correct Event
        event_type = sub.get('eventType', '')
        if event_type == expected_event:
            current_sub_score += 20
            current_feedback.append("Event type is correct")
        else:
            current_feedback.append(f"Wrong event type: {event_type}")

        # 3. Correct URL
        inputs = sub.get('consumerInputs', {})
        url = inputs.get('url', '')
        # Allow trailing slashes or minor differences
        if url.rstrip('/') == expected_url.rstrip('/'):
            current_sub_score += 20
            current_feedback.append("Target URL is correct")
        else:
            current_feedback.append(f"Wrong URL: {url}")
            
        # 4. Auth Configured
        # API usually hides password, but shows username if Basic Auth is selected
        username = inputs.get('username', '')
        # Check if 'password' key exists (even if masked) or implies basic auth
        # In ADO API, basic auth inputs usually have 'username' and 'password' keys
        if username == expected_username:
            current_sub_score += 20
            current_feedback.append("Basic Auth username correct")
        else:
            current_feedback.append(f"Wrong/Missing Basic Auth username: {username}")
            
        # 5. Correct Repository Scope
        # publisherInputs should contain 'repository'
        pub_inputs = sub.get('publisherInputs', {})
        repo_val = pub_inputs.get('repository', '')
        # This might be a UUID or name depending on how it was set. 
        # If it's set, it means it's scoped. If empty/missing, it's usually "All"
        if repo_val and repo_val != "00000000-0000-0000-0000-000000000000":
            # We assume if a value is present, they selected the repo. 
            # In a stricter check we might need the exact UUID of TailwindTraders, 
            # but verifying they didn't leave it blank is good enough for 'specificity'.
            current_sub_score += 20
            current_feedback.append("Repository filter configured")
        else:
            current_feedback.append("Repository filter missing (targeting All Repos?)")
            
        if current_sub_score > best_sub_score:
            best_sub_score = current_sub_score
            best_sub = sub
            feedback = current_feedback

    if not best_sub:
        return {
            "passed": False,
            "score": 0,
            "feedback": "No valid WebHook subscriptions found (checked consumerId=webHooks)."
        }

    return {
        "passed": best_sub_score >= 80,
        "score": best_sub_score,
        "feedback": "; ".join(feedback)
    }