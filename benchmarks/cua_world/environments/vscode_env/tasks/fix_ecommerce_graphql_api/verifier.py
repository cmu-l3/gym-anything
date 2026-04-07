#!/usr/bin/env python3
"""
Verifier for the fix_ecommerce_graphql_api task.

Checks whether the agent identified and fixed 5 critical bugs in the Node.js
Apollo GraphQL server. Uses pre-exported metrics gathered by running a 
hidden test suite against the local server. Also incorporates VLM verification 
to ensure the agent actively used the IDE workflow.

Scoring:
- Price Conversion: 16 points
- Null Handling: 16 points
- Missing Resolver: 16 points
- Input Validation: 16 points
- N+1 Optimization: 16 points
- VLM Trajectory Verification: 20 points
Total: 100 points
Pass Threshold: 60 points
"""

import os
import json
import logging
import tempfile

from gym_anything.vlm import sample_trajectory_frames

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

VLM_PROMPT = """You are verifying an AI agent's performance on a coding task in VS Code.
The agent was asked to fix bugs in a Node.js GraphQL API (JavaScript files and GraphQL schemas).

Review the provided screenshots from the agent's session.
1. Did the agent open and view/edit JavaScript or GraphQL files in VS Code?
2. Is there evidence that the agent actually interacted with the code (e.g., cursor moving, text selected, integrated terminal showing commands)?

Respond in JSON format:
{
    "edited_code": true/false,
    "confidence": "high/medium/low",
    "reasoning": "Brief explanation of what is shown in the frames"
}
"""

def verify_graphql_api(traj, env_info, task_info):
    """
    Verify the fix_ecommerce_graphql_api task.
    """
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Fetch task results from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        if not os.path.exists(temp_file.name) or os.path.getsize(temp_file.name) == 0:
            return {"passed": False, "score": 0, "feedback": "Result JSON not found or empty."}
            
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    feedback_parts = []
    score = 0
    max_score = 100
    
    # 2. Anti-Gaming Check: Was the code actually modified?
    file_modified = result.get('file_modified', False)
    if not file_modified:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Failed: Source files were not modified during the task. No work detected."
        }
        
    test_results = result.get('test_results', {})
    if 'error' in test_results:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Failed: API Server crashed or threw an unhandled error: {test_results['error']}"
        }

    # 3. Evaluate the 5 bugs (16 points each = 80 total)
    
    # Bug 1: Price Float
    if test_results.get('price_float'):
        score += 16
        feedback_parts.append("[+] Price correctly formatted as float (16/16)")
    else:
        feedback_parts.append("[-] Price resolver still returning raw integer cents (0/16)")

    # Bug 2: Null Description
    if test_results.get('null_description'):
        score += 16
        feedback_parts.append("[+] Null description gracefully handled with fallback (16/16)")
    else:
        feedback_parts.append("[-] Querying products with null description still crashes API (0/16)")

    # Bug 3: Missing Full Name
    if test_results.get('full_name'):
        score += 16
        feedback_parts.append("[+] User.fullName resolver correctly implemented (16/16)")
    else:
        feedback_parts.append("[-] User.fullName resolver is missing or incorrect (0/16)")

    # Bug 4: Input Validation
    if test_results.get('input_validation'):
        score += 16
        feedback_parts.append("[+] Mutation correctly rejects negative quantities with exact message (16/16)")
    else:
        feedback_parts.append("[-] Mutation lacks correct input validation for quantity (0/16)")

    # Bug 5: N+1 Optimization
    query_count = test_results.get('query_count', 999)
    if test_results.get('n_plus_one_fixed'):
        score += 16
        feedback_parts.append(f"[+] N+1 fixed! DataLoader used. Total DB queries: {query_count} (16/16)")
    else:
        feedback_parts.append(f"[-] N+1 bottleneck remains. Total DB queries: {query_count} (Expected <= 2) (0/16)")

    # 4. VLM Trajectory Verification (20 points)
    if query_vlm:
        frames = sample_trajectory_frames(traj, n=4)
        if frames:
            vlm_response = query_vlm(prompt=VLM_PROMPT, images=frames)
            
            if vlm_response.get("success"):
                parsed = vlm_response.get("parsed", {})
                if parsed.get("edited_code", False):
                    score += 20
                    feedback_parts.append("[+] VLM confirmed active coding inside VS Code (20/20)")
                else:
                    feedback_parts.append("[-] VLM did not clearly detect VS Code interaction (0/20)")
            else:
                feedback_parts.append("[?] VLM request failed, skipping visual verification score.")
    else:
        feedback_parts.append("[?] VLM not available. Visual verification skipped.")

    # 5. Final Assessment
    pass_threshold = 60
    passed = score >= pass_threshold
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }