#!/usr/bin/env python3
"""
Verifier for Generate Pipeline Checkout Snippet task.

Verifies that the agent generated a valid Jenkins Pipeline Git checkout snippet
with the specific requested configuration (Clean, Prune, Subdirectory).
"""

import sys
import os
import json
import logging
import base64
import tempfile
import re

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_generate_pipeline_checkout_snippet(traj, env_info, task_info):
    """
    Verify the generated Groovy snippet.

    Criteria:
    1. File exists and was created during the task.
    2. Repository URL matches.
    3. Branch matches.
    4. 'Clean before checkout' extension present.
    5. 'Prune stale branches' extension present.
    6. 'Check out to sub-directory' extension present with correct path.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Retrieve metadata
    metadata = task_info.get('metadata', {})
    expected_url = metadata.get('expected_url', 'https://github.com/spring-projects/spring-boot.git')
    expected_branch = metadata.get('expected_branch', '2.7.x')
    expected_subdir = metadata.get('expected_subdir', 'sources')

    try:
        # Load result JSON
        temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/task_result.json", temp_result.name)
            with open(temp_result.name, 'r') as f:
                result = json.load(f)
        finally:
            if os.path.exists(temp_result.name):
                os.unlink(temp_result.name)

        # Basic File Checks
        if not result.get('file_exists'):
            return {
                "passed": False,
                "score": 0,
                "feedback": "The output file '/home/ga/spring_checkout_snippet.groovy' was not found."
            }

        if not result.get('created_during_task'):
            return {
                "passed": False,
                "score": 0,
                "feedback": "The output file was not created or modified during the task execution."
            }

        # Decode content
        content_b64 = result.get('file_content_b64', '')
        if not content_b64:
             return {
                "passed": False,
                "score": 10,
                "feedback": "The output file is empty."
            }
        
        try:
            content = base64.b64decode(content_b64).decode('utf-8')
        except Exception:
            return {
                "passed": False,
                "score": 10,
                "feedback": "The output file contains invalid data (not UTF-8 text)."
            }

        score = 10
        feedback_parts = ["File created successfully"]
        
        # --- Content Verification ---
        # The generated snippet is Groovy code. We'll use flexible regex matching.

        # 1. Check Repo URL (20 pts)
        # Matches: url: '...' or url: "..."
        if expected_url in content:
            score += 20
            feedback_parts.append("Repository URL correct")
        else:
            feedback_parts.append(f"Repository URL missing or incorrect (expected {expected_url})")

        # 2. Check Branch (10 pts)
        # Matches: name: '2.7.x' or */2.7.x
        if expected_branch in content:
            score += 10
            feedback_parts.append("Branch correct")
        else:
            feedback_parts.append(f"Branch missing or incorrect (expected {expected_branch})")

        # 3. Check Extensions (20 pts each)
        # Note: Class names can be unqualified in some contexts, but usually full class in snippet generator
        
        # CleanBeforeCheckout
        if 'CleanBeforeCheckout' in content:
            score += 20
            feedback_parts.append("Clean extension found")
        else:
            feedback_parts.append("Clean before checkout extension missing")

        # PruneStaleBranch
        if 'PruneStaleBranch' in content:
            score += 20
            feedback_parts.append("Prune extension found")
        else:
            feedback_parts.append("Prune stale branches extension missing")

        # RelativeTargetDirectory + Path
        if 'RelativeTargetDirectory' in content:
            if expected_subdir in content:
                score += 20
                feedback_parts.append(f"Subdirectory '{expected_subdir}' configured correctly")
            else:
                score += 10 # Half points for extension present but wrong path
                feedback_parts.append(f"Subdirectory extension found but path '{expected_subdir}' missing")
        else:
            feedback_parts.append("Subdirectory checkout extension missing")

        passed = (score == 100)
        
        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }

    except Exception as e:
        logger.error(f"Verification failed with error: {e}")
        return {"passed": False, "score": 0, "feedback": f"Verification error: {str(e)}"}