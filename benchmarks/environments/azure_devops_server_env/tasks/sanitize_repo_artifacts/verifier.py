#!/usr/bin/env python3
"""
Verifier for sanitize_repo_artifacts task.
"""

import json
import logging
import os
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_sanitize_repo_artifacts(traj, env_info, task_info):
    """
    Verify the repository cleanup task.
    
    Scoring Criteria (100 pts):
    - node_modules removed: 20 pts
    - dist removed: 20 pts
    - log file removed: 10 pts
    - .gitignore created: 20 pts
    - .gitignore contains correct rules: 20 pts
    - Source code preserved: 10 pts (Prerequisite for passing)
    
    Pass threshold: 70 points AND source code preserved.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Define paths
    result_path_win = r"C:\Users\Docker\task_results\sanitize_repo_artifacts_result.json"
    result_path_linux = "/tmp/sanitize_repo_artifacts_result.json" # Fallback
    
    # Attempt to copy result file
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        try:
            copy_from_env(result_path_win, temp_file.name)
        except Exception:
            # Try alternative path or fail
            logger.warning("Could not copy from Windows path, trying generic...")
            return {"passed": False, "score": 0, "feedback": "Result file not found in environment"}

        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to parse result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # 1. Check Source Preservation (Critical)
    has_src = result.get('has_src', False)
    has_package_json = result.get('has_package_json', False)
    
    if has_src and has_package_json:
        score += 10
        feedback_parts.append("Source code preserved")
    else:
        feedback_parts.append("CRITICAL: Source code was deleted!")
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "Task Failed: legitimate source code was deleted. " + " | ".join(feedback_parts)
        }

    # 2. Check Artifact Removal
    has_node_modules = result.get('has_node_modules', True)
    if not has_node_modules:
        score += 20
        feedback_parts.append("node_modules removed")
    else:
        feedback_parts.append("node_modules still present")

    has_dist = result.get('has_dist', True)
    if not has_dist:
        score += 20
        feedback_parts.append("dist removed")
    else:
        feedback_parts.append("dist still present")

    has_log_file = result.get('has_log_file', True)
    if not has_log_file:
        score += 10
        feedback_parts.append("log file removed")
    else:
        feedback_parts.append("log file still present")

    # 3. Check .gitignore
    has_gitignore = result.get('has_gitignore', False)
    gitignore_content = result.get('gitignore_content', "")
    
    if has_gitignore:
        score += 20
        feedback_parts.append(".gitignore created")
        
        # Check content
        content_lower = gitignore_content.lower()
        rules_found = 0
        required_patterns = ['node_modules', 'dist']
        
        # Simple check for patterns
        if 'node_modules' in content_lower:
            rules_found += 1
        if 'dist' in content_lower:
            rules_found += 1
        
        # Check for log pattern (*.log or npm-debug.log)
        if '.log' in content_lower or 'npm-debug' in content_lower:
            rules_found += 1
            
        if rules_found >= 3:
            score += 20
            feedback_parts.append(".gitignore rules correct")
        elif rules_found > 0:
            score += 10
            feedback_parts.append("Partial .gitignore rules")
        else:
            feedback_parts.append(".gitignore empty or missing rules")
            
    else:
        feedback_parts.append(".gitignore missing")

    # 4. Final Verification
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }