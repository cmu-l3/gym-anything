#!/usr/bin/env python3
"""
Verifier for create_location_tag task.

Evaluates:
1. Did the agent create the 'Telehealth Endpoint' tag?
2. Does the tag have the correct description?
3. Is the 'Registration Desk' location associated with this tag?
4. Was the work done during the task window (anti-gaming)?
"""

import json
import os
import tempfile
import logging
from datetime import datetime

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def parse_iso8601(date_str):
    """Parse OpenMRS ISO8601 timestamp (e.g., '2023-10-27T10:00:00.000+0000')."""
    try:
        # Python 3.7+ handles typical ISO format, but might struggle with +0000 depending on locale
        # Simple approach: remove the timezone for comparison if needed, or use dateutil
        # Since we just need rough "after start" check, simplified parsing:
        dt_str = date_str.split('.')[0] # drop milliseconds and timezone for basic strptime
        return datetime.strptime(dt_str, "%Y-%m-%dT%H:%M:%S")
    except Exception as e:
        logger.warning(f"Failed to parse date {date_str}: {e}")
        return None

def verify_create_location_tag(traj, env_info, task_info):
    """
    Verify that the 'Telehealth Endpoint' tag was created and applied to 'Registration Desk'.
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
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # Extract data
    task_start_ts = result.get('task_start_timestamp', 0)
    tag_found = result.get('tag_found', False)
    tag_data = result.get('tag_data', {})
    location_tags = result.get('location_tags', [])

    score = 0
    feedback_parts = []
    
    # Criterion 1: Tag Created (30 pts)
    if tag_found and tag_data:
        score += 30
        feedback_parts.append("Tag 'Telehealth Endpoint' created.")
        
        # Criterion 2: Tag Description (10 pts)
        desc = tag_data.get('description', '')
        expected_desc_keywords = ["remote", "video", "consultation"]
        # Case insensitive partial match
        if any(k in desc.lower() for k in expected_desc_keywords):
            score += 10
            feedback_parts.append("Tag description correct.")
        else:
            feedback_parts.append(f"Tag description mismatch. Got: '{desc}'")

        # Criterion 3: Anti-gaming / Timestamp check (20 pts)
        # Check auditInfo if available, otherwise rely on the fact we purged it in setup
        created_date_str = tag_data.get('auditInfo', {}).get('dateCreated')
        if created_date_str:
            created_dt = parse_iso8601(created_date_str)
            if created_dt and created_dt.timestamp() > task_start_ts:
                score += 20
                feedback_parts.append("Tag created during task window.")
            else:
                feedback_parts.append("Tag creation timestamp predates task (stale data).")
        else:
            # Fallback if auditInfo missing but we know we purged it
            score += 20
            feedback_parts.append("Tag verified (assumed new as previous was purged).")

    else:
        feedback_parts.append("Tag 'Telehealth Endpoint' NOT found.")

    # Criterion 4: Linked to Location (40 pts)
    link_found = False
    for tag in location_tags:
        # Check by display name
        if "Telehealth Endpoint" in tag.get('display', ''):
            link_found = True
            break
            
    if link_found:
        score += 40
        feedback_parts.append("'Registration Desk' linked to tag.")
    else:
        feedback_parts.append("'Registration Desk' does NOT have the tag.")

    # Final tally
    passed = (score >= 90) # Requires creation (30) + link (40) + timestamp (20) = 90 min

    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback_parts)
    }