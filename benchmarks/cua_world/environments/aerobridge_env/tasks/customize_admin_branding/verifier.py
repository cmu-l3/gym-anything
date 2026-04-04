#!/usr/bin/env python3
"""
Verifier for customize_admin_branding task.

Verifies that the Django admin interface has been customized with the correct
branding strings by checking the HTTP response from the running server.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_customize_admin_branding(traj, env_info, task_info):
    """
    Verify branding customization.
    
    Scoring:
    - Server Running & Accessible: 10 pts
    - Header "SkyGuard Operations": 30 pts
    - Title "SkyGuard Admin": 30 pts
    - Index Title "Fleet Command Center": 30 pts
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Copy result JSON
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
    feedback_parts = []
    
    # Criterion 1: Server Health (10 pts)
    server_running = result.get("server_running", False)
    http_status = result.get("http_status", "000")
    
    if server_running and http_status == "200":
        score += 10
        feedback_parts.append("✓ Server is running and accessible (+10)")
    else:
        feedback_parts.append(f"✗ Server issue (Running: {server_running}, HTTP: {http_status})")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}

    # Criterion 2: Site Header (30 pts)
    if result.get("found_header", False):
        score += 30
        feedback_parts.append("✓ Site Header 'SkyGuard Operations' found (+30)")
    else:
        feedback_parts.append("✗ Site Header 'SkyGuard Operations' NOT found")

    # Criterion 3: Site Title (30 pts)
    if result.get("found_title", False):
        score += 30
        feedback_parts.append("✓ Site Title 'SkyGuard Admin' found (+30)")
    else:
        feedback_parts.append("✗ Site Title 'SkyGuard Admin' NOT found")

    # Criterion 4: Index Title (30 pts)
    if result.get("found_index_title", False):
        score += 30
        feedback_parts.append("✓ Index Title 'Fleet Command Center' found (+30)")
    else:
        feedback_parts.append("✗ Index Title 'Fleet Command Center' NOT found")

    # Bonus/Debug info
    if result.get("file_modified", False):
        feedback_parts.append("(Code file modification detected)")

    passed = (score == 100)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }