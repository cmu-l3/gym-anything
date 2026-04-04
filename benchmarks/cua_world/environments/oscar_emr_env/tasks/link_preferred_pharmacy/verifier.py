#!/usr/bin/env python3
"""
Verifier for Link Preferred Pharmacy task in OSCAR EMR.

Verifies that the agent successfully linked 'Rexall Pharma Plus' to patient 'Maria Santos'.
Primary signal is the database record in `demographicPharmacy`.
"""

import json
import os
import tempfile
import logging
from datetime import datetime

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_link_preferred_pharmacy(traj, env_info, task_info):
    """
    Verify patient pharmacy link.
    
    Criteria:
    1. Database record exists linking the correct patient and pharmacy IDs.
    2. Link is active (not archived).
    3. Link was created/updated during the task session (anti-gaming).
    """
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
            
    # Extract data
    link_exists = result.get("link_exists", False)
    link_archived = result.get("link_archived", False)
    total_links = result.get("total_active_links", 0)
    creation_date_str = result.get("creation_date", "")
    task_start_ts = result.get("task_start_timestamp", 0)
    
    score = 0
    feedback_parts = []
    
    # CRITERION 1: Link Exists (60 points)
    if link_exists:
        score += 60
        feedback_parts.append("Pharmacy link found in database")
        
        # CRITERION 2: Link Active (20 points)
        if not link_archived:
            score += 20
            feedback_parts.append("Link is active")
        else:
            feedback_parts.append("Warning: Link is marked as archived/deleted")
            
        # CRITERION 3: Timing / Anti-gaming (20 points)
        # Check if creationDate is reasonable (after task start)
        # OSCAR stores dates like '2023-10-27 10:00:00'
        valid_timing = False
        if creation_date_str:
            try:
                # Handle potential format variations
                if '.' in creation_date_str:
                    creation_dt = datetime.strptime(creation_date_str.split('.')[0], "%Y-%m-%d %H:%M:%S")
                else:
                    creation_dt = datetime.strptime(creation_date_str, "%Y-%m-%d %H:%M:%S")
                    
                creation_ts = creation_dt.timestamp()
                
                # Allow a small buffer (e.g., clock skew), but generally creation > start
                if creation_ts >= (task_start_ts - 60):
                    valid_timing = True
            except ValueError:
                logger.warning(f"Could not parse creation date: {creation_date_str}")
                # Fallback: if it exists and we cleared it in setup, it must be new
                valid_timing = True
        
        if valid_timing:
            score += 20
            feedback_parts.append("Link created during task session")
        else:
            feedback_parts.append("Warning: Link creation time predates task start (stale data?)")
            
    else:
        feedback_parts.append("No link found between Maria Santos and Rexall Pharma Plus")
        if total_links > 0:
            feedback_parts.append(f"Found {total_links} other active pharmacy links (wrong pharmacy?)")
            
    # Success determination
    passed = (score >= 80)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }