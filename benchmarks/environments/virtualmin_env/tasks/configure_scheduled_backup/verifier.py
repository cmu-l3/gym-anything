#!/usr/bin/env python3
"""
Verifier for configure_scheduled_backup task.

Verification Logic:
1. Parse exported Virtualmin backup config files.
2. Check if a config exists that matches:
   - Destination: /backup/nightly
   - Domains: Includes specific IDs, excludes others.
   - Schedule: Daily at 2:00 AM.
   - Enabled: Yes.
"""

import json
import os
import tempfile
import base64
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_scheduled_backup(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # -----------------------------------------------------------
    # Load Result JSON from Container
    # -----------------------------------------------------------
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

    # -----------------------------------------------------------
    # Parse Data
    # -----------------------------------------------------------
    backup_configs = result.get('backup_configs', [])
    domain_map = result.get('domain_map', {})
    
    # Target IDs
    acme_id = domain_map.get("acmecorp.test", "")
    nonprofit_id = domain_map.get("nonprofitaid.test", "")
    global_id = domain_map.get("globalshop.test", "")

    if not backup_configs:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "No scheduled backup configuration files found. Did you save the schedule?"
        }

    # -----------------------------------------------------------
    # Evaluate Configs
    # -----------------------------------------------------------
    # We look for *at least one* valid config. If multiple exist, we take the best score.
    best_score = 0
    feedback_lines = []

    for config in backup_configs:
        current_score = 0
        current_feedback = []
        
        # Decode content
        try:
            content_str = base64.b64decode(config['content_base64']).decode('utf-8', errors='ignore')
        except:
            continue

        # Parse Key-Value pairs (Virtualmin config format)
        conf = {}
        for line in content_str.splitlines():
            if '=' in line:
                key, val = line.split('=', 1)
                conf[key.strip()] = val.strip()

        # --- Criterion 1: Config exists (15 pts) ---
        current_score += 15
        current_feedback.append("Backup schedule created.")

        # --- Criterion 2: Destination (20 pts) ---
        # Virtualmin uses 'dest' or 'dest0'
        dest = conf.get('dest', conf.get('dest0', ''))
        if '/backup/nightly' in dest:
            current_score += 20
            current_feedback.append("Destination correct (/backup/nightly).")
        else:
            current_feedback.append(f"Incorrect destination: {dest}")

        # --- Criterion 3: Domains (30 pts) ---
        # 'doms' contains space-separated IDs. 'all' means all domains.
        doms = conf.get('doms', '').split()
        is_all = conf.get('all', '0') == '1'

        if is_all:
            # Task explicitly said NOT to select all domains
            current_feedback.append("Failed: 'All domains' selected (should select specific domains only).")
            # We penalize this heavily as it's a specific instruction
        else:
            # Check for acmecorp (15 pts)
            if acme_id and acme_id in doms:
                current_score += 15
                current_feedback.append("acmecorp.test included.")
            else:
                current_feedback.append("acmecorp.test MISSING.")

            # Check for nonprofitaid (15 pts)
            if nonprofit_id and nonprofit_id in doms:
                current_score += 15
                current_feedback.append("nonprofitaid.test included.")
            else:
                current_feedback.append("nonprofitaid.test MISSING.")

            # Check for globalshop (should NOT be there)
            if global_id and global_id in doms:
                current_score = max(0, current_score - 10) # Penalty
                current_feedback.append("Penalty: globalshop.test included (should be excluded).")

        # --- Criterion 4: Schedule (Daily at 2:00) (20 pts) ---
        # Virtualmin cron fields: hours, mins, days, weekdays, months
        # Empty or '*' usually implies 'every'
        
        # Hours (5 pts)
        hours = conf.get('hours', '')
        if hours == '2':
            current_score += 5
            current_feedback.append("Hour correct (2 AM).")
        else:
            current_feedback.append(f"Incorrect hour: {hours}")

        # Minutes (5 pts)
        mins = conf.get('mins', '')
        if mins == '0' or mins == '00':
            current_score += 5
            current_feedback.append("Minute correct (00).")
        else:
            current_feedback.append(f"Incorrect minute: {mins}")

        # Daily frequency (10 pts)
        # For daily, days/weekdays/months should be empty or *
        # If 'special' is set to 'daily', that also counts
        days = conf.get('days', '*')
        special = conf.get('special', '')
        
        is_daily = False
        if special == 'daily' or special == '@daily':
            is_daily = True
        elif (days == '*' or days == '') and (conf.get('weekdays', '*') in ['*', '']) and (conf.get('months', '*') in ['*', '']):
            is_daily = True
            
        if is_daily:
            current_score += 10
            current_feedback.append("Frequency correct (Daily).")
        else:
            current_feedback.append("Incorrect frequency (not daily).")

        # --- Criterion 5: Enabled (10 pts) ---
        # enabled=1 is default if missing? Usually explicitly set.
        enabled = conf.get('enabled', '1')
        if enabled == '1':
            current_score += 10
            current_feedback.append("Schedule enabled.")
        else:
            current_feedback.append("Schedule is disabled.")

        # Update best score
        if current_score > best_score:
            best_score = current_score
            feedback_lines = current_feedback

    # -----------------------------------------------------------
    # Final Result
    # -----------------------------------------------------------
    passed = best_score >= 60
    
    return {
        "passed": passed,
        "score": best_score,
        "feedback": " | ".join(feedback_lines)
    }