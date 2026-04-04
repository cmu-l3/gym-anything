#!/usr/bin/env python3
"""
Verifier for fix_htaccess_syntax_error task.

SCORING CRITERIA:
1. Website loads (200 OK) - 40 pts
2. Redirect works (301 Moved) - 30 pts (Prevents deleting file)
3. Syntax corrected in .htaccess - 20 pts
4. File modified during task - 10 pts
"""

import json
import base64
import os
import tempfile
import re
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

def verify_fix_htaccess_syntax_error(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result from container
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
    feedback = []

    # 1. Verify Website Loads (HTTP 200)
    root_code = str(result.get("root_http_code", "0"))
    content_found = result.get("root_content_found", "")
    
    if root_code == "200" and "System Operational" in content_found:
        score += 40
        feedback.append("Website is online (200 OK).")
    else:
        feedback.append(f"Website is down (Status: {root_code}).")

    # 2. Verify Redirect Logic (HTTP 301)
    # This ensures they didn't just delete the .htaccess file to fix the 500 error.
    redirect_code = str(result.get("redirect_http_code", "0"))
    redirect_loc = result.get("redirect_location", "")
    
    # We accept 301 or 302, and check location
    if redirect_code in ["301", "302"] and "new-page.php" in redirect_loc:
        score += 30
        feedback.append("Redirect logic preserved.")
    else:
        feedback.append(f"Redirect broken (Status: {redirect_code}). Did you delete the file?")

    # 3. Verify File Syntax & Existence
    htaccess_exists = result.get("htaccess_exists", False)
    htaccess_b64 = result.get("htaccess_content_b64", "")
    file_modified = result.get("file_modified_during_task", False)
    
    if htaccess_exists and htaccess_b64:
        try:
            content = base64.b64decode(htaccess_b64).decode('utf-8')
            # Check for correct spelling "RewriteRule"
            if re.search(r'RewriteRule\s+\^old-page', content, re.IGNORECASE):
                score += 20
                feedback.append("Syntax error corrected in file.")
            elif "RewritRule" in content:
                feedback.append("Syntax error (RewritRule) still present.")
            else:
                feedback.append("Could not verify specific RewriteRule syntax.")
        except:
            feedback.append("Could not decode .htaccess content.")
    else:
        feedback.append(".htaccess file missing.")

    if file_modified:
        score += 10
        feedback.append("File modification detected.")

    # 4. VLM Verification (Optional but good for trajectory check)
    # Only if score is borderline or to confirm UI usage
    if score >= 60:
        frames = sample_trajectory_frames(traj, n=3)
        final = get_final_screenshot(traj)
        vlm_prompt = "Did the user use a file manager or text editor to fix a configuration file? Look for 'RewriteRule' or '.htaccess'."
        try:
            vlm_res = query_vlm(images=frames + [final], prompt=vlm_prompt)
            if vlm_res.get("success") and vlm_res.get("positive", False):
                # Bonus or confirmation, usually we just use programmatic score if reliable
                pass
        except:
            pass

    passed = (score >= 80)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }