#!/usr/bin/env python3
"""
Verifier for link_orphaned_opportunities_to_customers task.
"""

import json
import os
import tempfile
import logging
from datetime import datetime

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def parse_odoo_date(date_str):
    """Parse Odoo datetime string 'YYYY-MM-DD HH:MM:SS' to timestamp."""
    if not date_str:
        return 0
    try:
        # Odoo dates are typically UTC strings like "2023-10-25 10:00:00"
        # We can treat them as naive or assume UTC. 
        # The task_start timestamp is unix epoch.
        # Let's convert Odoo string to unix epoch.
        dt = datetime.strptime(date_str.split(".")[0], "%Y-%m-%d %H:%M:%S")
        return dt.timestamp()
    except Exception as e:
        logger.warning(f"Failed to parse date {date_str}: {e}")
        return 0

def verify_link_orphaned_opportunities_to_customers(traj, env_info, task_info):
    """
    Verify that the 3 orphaned opportunities were linked to the correct partners.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    targets = metadata.get('targets', [])
    
    # Define targets map for easy lookup
    target_map = {t['opp_name']: t for t in targets}

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

    task_start = result.get('task_start', 0)
    opportunities = result.get('opportunities', {})
    
    score = 0
    max_score = 0
    feedback_parts = []
    passed_count = 0

    for target in targets:
        name = target['opp_name']
        expected = target['expected_partner']
        points = target['points']
        max_score += points

        opp_data = opportunities.get(name)
        
        if not opp_data:
            feedback_parts.append(f"❌ Opportunity '{name}' not found")
            continue

        actual_partner = opp_data.get('partner_name')
        write_date_str = opp_data.get('write_date')
        write_time = parse_odoo_date(write_date_str)
        
        # Check 1: Correct partner
        if actual_partner == expected:
            # Check 2: Modified after start
            if write_time > task_start:
                score += points
                passed_count += 1
                feedback_parts.append(f"✅ '{name}' linked to '{expected}'")
            else:
                # Partial credit? No, anti-gaming requires action.
                # Actually, Odoo writes happen on DB level, if they didn't touch it, date won't update.
                # If they linked it correctly, write_date SHOULD update.
                feedback_parts.append(f"⚠️ '{name}' has correct partner but was not modified during task (stale data?)")
        else:
            if actual_partner:
                feedback_parts.append(f"❌ '{name}' linked to wrong partner '{actual_partner}' (expected '{expected}')")
            else:
                feedback_parts.append(f"❌ '{name}' still orphaned (no customer linked)")

    passed = (score == max_score)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }