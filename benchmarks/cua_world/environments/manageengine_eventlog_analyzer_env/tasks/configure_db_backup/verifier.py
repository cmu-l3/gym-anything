#!/usr/bin/env python3
"""
Verifier for configure_db_backup task in ManageEngine EventLog Analyzer.

Criteria:
1. Backup directory exists (filesystem check).
2. Database/Config reflects changes (DB query or file mod check).
3. Report file created by agent.
4. VLM verification of UI trajectory (navigated to settings, set daily schedule).
"""

import json
import tempfile
import os
import logging
import sys

# Add parent directory to path to import vlm_utils if needed, though we usually assume gym_anything structure
sys.path.append(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# VLM Prompt for trajectory verification
VLM_PROMPT = """
You are verifying if an agent successfully configured Database Backups in ManageEngine EventLog Analyzer.

Review the sequence of screenshots. The agent should:
1. Navigate to the 'Settings' or 'Admin' tab.
2. Locate 'Database Backup' or 'Database Settings'.
3. Enable 'Scheduled Backup'.
4. Set the Backup Directory to a path ending in '/backup'.
5. Set the Schedule to 'Daily'.
6. Click 'Save'.

Answer the following in JSON format:
{
  "settings_opened": boolean,
  "backup_config_visible": boolean,
  "daily_schedule_selected": boolean,
  "path_entered": boolean,
  "save_clicked": boolean,
  "error_dialog_present": boolean
}
"""

def verify_configure_db_backup(traj, env_info, task_info):
    """
    Verify the configure_db_backup task.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_path = metadata.get('expected_backup_path', '/opt/ManageEngine/EventLog/backup')
    
    # 1. Load Result JSON
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
    
    # --- CRITERION 1: Backup Directory Created (20 pts) ---
    backup_dir_exists = result.get('backup_dir_exists', False)
    if backup_dir_exists:
        score += 20
        feedback_parts.append("Backup directory created.")
    else:
        feedback_parts.append("Backup directory NOT found.")

    # --- CRITERION 2: Evidence of Configuration Change (30 pts) ---
    # We look for DB changes OR Config file modifications
    db_config = result.get('db_backup_config', '')
    mod_count = result.get('modified_config_count', 0)
    
    config_evidence = False
    
    # Check DB content for keywords
    if expected_path in db_config or "backup" in db_config.lower():
         config_evidence = True
         feedback_parts.append("DB config updated.")
    
    # Fallback/Additional: Check file modifications (ELA saves to xml/conf files often)
    if mod_count > 0:
        config_evidence = True
        feedback_parts.append(f"{mod_count} config files modified.")
        
    if config_evidence:
        score += 30
    else:
        feedback_parts.append("No configuration changes detected (DB or Files).")

    # --- CRITERION 3: Agent Report File (10 pts) ---
    if result.get('report_file_exists', False):
        score += 10
        feedback_parts.append("Report file created.")
    else:
        feedback_parts.append("Report file missing.")

    # --- CRITERION 4: VLM Trajectory Verification (40 pts) ---
    # We need to verify 'Daily' schedule and actual UI interaction which is hard to probe via DB
    from gym_anything.vlm import sample_trajectory_frames, query_vlm
    
    frames = sample_trajectory_frames(traj, n=6)
    vlm_result = query_vlm(images=frames, prompt=VLM_PROMPT)
    
    vlm_score = 0
    if vlm_result and vlm_result.get('success'):
        parsed = vlm_result.get('parsed', {})
        
        if parsed.get('settings_opened'): vlm_score += 5
        if parsed.get('backup_config_visible'): vlm_score += 10
        if parsed.get('daily_schedule_selected'): vlm_score += 10
        if parsed.get('path_entered'): vlm_score += 10
        if parsed.get('save_clicked'): vlm_score += 5
        
        # Penalty for errors
        if parsed.get('error_dialog_present'): vlm_score -= 10
        
        feedback_parts.append(f"VLM Analysis: {parsed}")
    else:
        feedback_parts.append("VLM verification failed to run.")
    
    # Clamp VLM score
    vlm_score = max(0, min(40, vlm_score))
    score += vlm_score

    # Anti-gaming check: If score is high but app not running or no config changes
    if score > 50 and not result.get('app_running', False):
        score = 0
        feedback_parts.append("FAIL: Application was not running at end of task.")

    passed = score >= 60 and backup_dir_exists and config_evidence

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }