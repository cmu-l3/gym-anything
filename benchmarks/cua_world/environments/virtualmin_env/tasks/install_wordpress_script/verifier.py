#!/usr/bin/env python3
"""
Verifier for install_wordpress_script task.

Scoring Rubric (100 pts total):
1. WordPress is registered in Virtualmin (20 pts)
2. wp-config.php exists (10 pts)
   - Created during task (Anti-gaming) (+5 pts)
   - At correct path /blog (+10 pts)
3. Database populated (>5 tables) (15 pts)
4. Site Title matches 'ACME Corp Blog' (15 pts)
5. Admin User 'wpadmin' exists (15 pts)
6. Site URL path is /blog (10 pts)
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_install_wordpress_script(traj, env_info, task_info):
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
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # 1. Virtualmin Registration (20 pts)
    if result.get('is_registered_in_virtualmin', False):
        score += 20
        feedback_parts.append("WordPress registered in Virtualmin (+20)")
    else:
        feedback_parts.append("WordPress NOT registered in Virtualmin")

    # 2. File Existence & Location (25 pts total)
    file_exists = result.get('file_exists', False)
    file_path = result.get('file_path', '')
    
    if file_exists:
        score += 10
        feedback_parts.append("wp-config.php found (+10)")
        
        # Check path
        if '/blog/' in file_path:
            score += 10
            feedback_parts.append("Correct install path /blog (+10)")
        else:
            feedback_parts.append(f"Incorrect path: {file_path}")
            
        # Check timestamp (anti-gaming)
        if result.get('file_created_during_task', False):
            score += 5
            feedback_parts.append("File created during task (+5)")
        else:
            feedback_parts.append("File timestamp predates task (Anti-Gaming fail)")
    else:
        feedback_parts.append("wp-config.php not found")

    # 3. Database Validity (15 pts)
    if result.get('db_valid', False):
        score += 15
        feedback_parts.append(f"Database populated ({result.get('table_count')} tables) (+15)")
    else:
        feedback_parts.append("Database empty or missing")

    # 4. Content Checks (40 pts total)
    # Site Title (15 pts)
    actual_title = result.get('wp_title', '')
    if 'ACME Corp Blog' in actual_title:
        score += 15
        feedback_parts.append("Site title matches (+15)")
    else:
        feedback_parts.append(f"Title mismatch: '{actual_title}'")

    # Admin User (15 pts)
    if result.get('wp_admin_found', False):
        score += 15
        feedback_parts.append("Admin user 'wpadmin' found (+15)")
    else:
        feedback_parts.append("Admin user 'wpadmin' NOT found")

    # Site URL Path (10 pts)
    site_url = result.get('wp_siteurl', '')
    if '/blog' in site_url:
        score += 10
        feedback_parts.append("Site URL correct (+10)")
    elif file_exists and '/blog/' in file_path:
        # Fallback if DB check failed but file path was right, we don't double penalize too hard,
        # but technically DB must match.
        pass
    else:
        feedback_parts.append(f"Site URL mismatch: '{site_url}'")

    # Pass logic
    # Must have files, DB, and at least some content correctness
    passed = score >= 60 and file_exists and result.get('db_valid', False)

    return {
        "passed": passed,
        "score": score,
        "feedback": "; ".join(feedback_parts)
    }