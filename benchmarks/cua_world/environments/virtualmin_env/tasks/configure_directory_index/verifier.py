#!/usr/bin/env python3
import json
import os
import tempfile
import base64
import re
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_configure_directory_index(traj, env_info, task_info):
    """
    Verify that the agent correctly configured the directory index and disabled directory listing.
    """
    # 1. Setup: Retrieve result JSON from environment
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # ------------------------------------------------------------------
    # Criterion 1: Root URL serves promo.html (40 points)
    # ------------------------------------------------------------------
    root_ok = result.get('root_serves_promo', False)
    if root_ok:
        score += 40
        feedback_parts.append("Root URL correctly serves promo.html")
    else:
        feedback_parts.append("Root URL does NOT serve promo.html")

    # ------------------------------------------------------------------
    # Criterion 2: Directory Listing Disabled (40 points)
    # ------------------------------------------------------------------
    assets_forbidden = result.get('assets_forbidden', False)
    assets_shows_index = result.get('assets_shows_index', False)
    
    if assets_forbidden:
        score += 40
        feedback_parts.append("/assets/ correctly returns 403 Forbidden")
    elif assets_shows_index:
        feedback_parts.append("FAIL: /assets/ still shows directory listing")
    else:
        # returns something else (like 404 or 200 with wrong content), partial credit if not listing
        code = result.get('assets_http_code', 'unknown')
        feedback_parts.append(f"FAIL: /assets/ returned code {code} (expected 403)")

    # ------------------------------------------------------------------
    # Criterion 3: Config Inspection (Fallback/Priority check) (20 points)
    # ------------------------------------------------------------------
    # We need to check if index.php is still in the list (fallback requirement)
    # and confirm promo.html is first.
    config_b64 = result.get('config_content_b64', "")
    fallback_ok = False
    
    if config_b64:
        try:
            config_content = base64.b64decode(config_b64).decode('utf-8')
            
            # Regex to find DirectoryIndex directive
            # Matches: DirectoryIndex file1 file2 ...
            match = re.search(r'DirectoryIndex\s+(.+)', config_content, re.IGNORECASE)
            
            if match:
                files = match.group(1).split()
                if len(files) > 0:
                    if files[0] == "promo.html":
                        if "index.php" in files:
                            fallback_ok = True
                            score += 20
                            feedback_parts.append("Configuration correct: promo.html first, index.php retained")
                        else:
                            # Partial credit if they deleted index.php but set promo first? 
                            # Instruction said "keep index.php as fallback".
                            score += 10
                            feedback_parts.append("Configuration warning: promo.html is first, but index.php was removed")
                    else:
                        feedback_parts.append(f"Configuration error: promo.html is not first (Found: {files[0]})")
                else:
                    feedback_parts.append("Configuration error: Empty DirectoryIndex")
            else:
                feedback_parts.append("Configuration error: DirectoryIndex directive not found")
        except Exception as e:
            feedback_parts.append(f"Error parsing config: {str(e)}")
    
    # ------------------------------------------------------------------
    # Final Scoring
    # ------------------------------------------------------------------
    # Config file modified check (Anti-gaming)
    if not result.get('config_file_modified', False):
        feedback_parts.append("(Note: Config file timestamp indicates no modification)")
        # If score is high but file not modified, agent might have used .htaccess? 
        # If .htaccess was used, config_file_modified would be false but HTTP checks would pass.
        # We accept HTTP checks as truth, so we don't zero the score, just warn.

    return {
        "passed": score >= 80,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }