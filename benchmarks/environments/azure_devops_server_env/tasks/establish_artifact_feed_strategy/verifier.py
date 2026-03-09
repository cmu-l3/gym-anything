#!/usr/bin/env python3
"""
Verifier for Establish Artifact Feed Strategy task.
"""

import json
import logging
import os
import tempfile
from datetime import datetime

logger = logging.getLogger(__name__)

def verify_establish_artifact_feed_strategy(traj, env_info, task_info):
    """
    Verify the creation and configuration of the Azure Artifacts feed.
    """
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    # Define paths (Windows path in VM, converted for copy usage)
    remote_path = r"C:\Users\Docker\task_results\establish_artifact_feed_result.json"
    
    # Create temp file for the result
    tmp = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
    tmp.close()
    
    try:
        copy_from_env(remote_path, tmp.name)
        with open(tmp.name, "r") as f:
            result = json.load(f)
    except Exception as e:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": f"Failed to retrieve or parse task result file: {str(e)}"
        }
    finally:
        if os.path.exists(tmp.name):
            os.unlink(tmp.name)

    # Initialize scoring
    score = 0
    feedback_parts = []
    
    # Criterion 1: Feed Existence (30 pts)
    if result.get("feed_exists"):
        score += 30
        feedback_parts.append("Feed 'Tailwind-Universal' created.")
    else:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Feed 'Tailwind-Universal' was not found."
        }

    # Criterion 2: Retention Policy (30 pts)
    # Expected: 15
    actual_limit = result.get("retention_limit")
    if actual_limit == 15:
        score += 30
        feedback_parts.append("Retention limit correctly set to 15.")
    else:
        feedback_parts.append(f"Retention limit incorrect. Expected 15, got {actual_limit if actual_limit is not None else 'None'}.")

    # Criterion 3: Upstream Sources (40 pts split)
    # Expected: NuGet and npm
    upstreams = result.get("upstream_sources", [])
    has_nuget = False
    has_npm = False
    
    for source in upstreams:
        name = source.get("name", "").lower()
        protocol = source.get("protocol", "").lower()
        location = source.get("location", "").lower()
        
        # Check for NuGet
        if "nuget" in name or "nuget" in protocol or "nuget" in location:
            has_nuget = True
            
        # Check for npm
        if "npm" in name or "npm" in protocol or "npmjs" in location:
            has_npm = True

    if has_nuget:
        score += 20
        feedback_parts.append("NuGet upstream source verified.")
    else:
        feedback_parts.append("Missing NuGet upstream source.")

    if has_npm:
        score += 20
        feedback_parts.append("npm upstream source verified.")
    else:
        feedback_parts.append("Missing npm upstream source.")

    # Anti-gaming: Check creation time vs task start
    # Note: If necessary, parse ISO dates. For now, we assume if the feed didn't exist 
    # at start (handled by setup script deletion) and exists now, it's valid.
    
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback_parts)
    }