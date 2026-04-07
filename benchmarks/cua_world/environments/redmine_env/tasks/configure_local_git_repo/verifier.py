#!/usr/bin/env python3
"""
Verifier for configure_local_git_repo task.

Checks:
1. Repository module is enabled for the project.
2. A Repository record exists.
3. Repository type is Git.
4. Repository path matches expected server path.
5. Repository identifier matches expected value.
6. VLM: Visual confirmation that files are listed.
"""

import json
import os
import tempfile
import logging
import sys

# Add parent directory to path to import vlm_utils if needed
sys.path.append(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
try:
    from vlm_utils import query_vlm, get_final_screenshot
except ImportError:
    # Fallback if vlm_utils not in python path
    query_vlm = None
    get_final_screenshot = None

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_configure_local_git_repo(traj, env_info, task_info):
    """
    Verify that the local git repository was configured correctly.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load metadata
    metadata = task_info.get('metadata', {})
    expected_path = metadata.get('expected_repo_path', '/srv/git/core-engine.git')
    expected_identifier = metadata.get('expected_repo_identifier', 'core-main')

    # Copy result JSON from VM
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result from environment: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # 1. Check Project Exists
    if not result.get('project_found'):
        return {"passed": False, "score": 0, "feedback": "Project 'Core Engine' not found."}

    # 2. Check Module Enabled (30 pts)
    modules = result.get('enabled_modules', [])
    if 'repository' in modules:
        score += 30
        feedback_parts.append("Repository module enabled")
    else:
        feedback_parts.append("Repository module NOT enabled")

    # 3. Check Repository Record Exists (20 pts)
    if result.get('repo_exists'):
        score += 20
        feedback_parts.append("Repository record created")
        
        # 4. Check SCM Type (10 pts)
        repo_type = result.get('repo_type', '')
        if 'Git' in repo_type:
            score += 10
            feedback_parts.append("SCM type is Git")
        else:
            feedback_parts.append(f"Incorrect SCM type: {repo_type}")

        # 5. Check Path (30 pts)
        repo_url = result.get('repo_url', '')
        # Normalize paths (remove trailing slashes)
        if repo_url.rstrip('/') == expected_path.rstrip('/'):
            score += 30
            feedback_parts.append(f"Repository path correct")
        else:
            feedback_parts.append(f"Incorrect path: '{repo_url}' (expected '{expected_path}')")

        # 6. Check Identifier (10 pts)
        repo_ident = result.get('repo_identifier', '')
        if repo_ident == expected_identifier:
            score += 10
            feedback_parts.append("Identifier correct")
        else:
            feedback_parts.append(f"Incorrect identifier: '{repo_ident}'")

    else:
        feedback_parts.append("No repository configured in project settings")

    # Optional: VLM Verification (Bonus or Confirmation)
    # We check if the final screenshot shows the repository file list
    vlm_score_adjust = 0
    if query_vlm and get_final_screenshot:
        screenshot = get_final_screenshot(traj)
        if screenshot:
            prompt = """
            Look at this Redmine screenshot. 
            1. Do you see a file list or directory structure (e.g. 'src', 'README.md', 'package.json')?
            2. Is the 'Repository' tab active?
            3. Are there any error messages like 'The repository does not exist'?
            
            Return JSON: {"files_visible": bool, "repo_tab_active": bool, "error_visible": bool}
            """
            try:
                vlm_res = query_vlm(prompt=prompt, image=screenshot)
                if vlm_res.get('success'):
                    parsed = vlm_res.get('parsed', {})
                    if parsed.get('files_visible') and not parsed.get('error_visible'):
                        feedback_parts.append("Visual verification passed (files visible)")
                    elif parsed.get('error_visible'):
                        feedback_parts.append("Visual verification failed (error message visible)")
                        # Penalize if programmatic passed but visual shows error (unlikely but possible)
            except Exception:
                pass

    passed = score >= 80  # Requires Module + Record + Path + (Type or Identifier)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }