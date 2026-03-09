#!/usr/bin/env python3
"""
Verifier for configure_notification_channels task.
"""

import json
import os
import tempfile
import logging
import re

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_notification_channels(traj, env_info, task_info):
    """
    Verifies that:
    1. Flight-critical channels are ENABLED.
    2. Non-essential channels are DISABLED.
    3. The agent created a config file documenting the state.
    4. The system state actually changed (anti-gaming).
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy function not available"}

    # Load metadata keywords
    metadata = task_info.get('metadata', {})
    critical_keywords = metadata.get('critical_keywords', ["flight", "alert", "status", "chat", "message"])
    
    # 1. Retrieve Result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/sdcard/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task result: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # Parse System State (Actual Ground Truth)
    # Format typically: "  Channel{id=pkg:uid:channel_id, name=Channel Name, importance=3, ...}"
    # Importance: 0=NONE (Disabled), 1=MIN, 2=LOW, 3=DEFAULT, 4=HIGH, 5=MAX
    system_raw = result.get('system_state_raw', '')
    initial_raw = result.get('initial_state_raw', '')
    
    channels = []
    # Regex to extract name and importance
    # Matches strings like: name=Flight Alerts importance=3
    # Note: Regex needs to be robust to variations in dumpsys output
    pattern = re.compile(r'name=([^,]+).*?importance=([0-9]+)')
    
    for match in pattern.finditer(system_raw):
        name = match.group(1).strip()
        importance = int(match.group(2))
        channels.append({'name': name, 'enabled': importance > 0})

    if not channels:
        return {"passed": False, "score": 0, "feedback": "Failed to parse notification channels from system state. App may not have registered channels."}

    # 2. Score: Did State Change? (Anti-gaming) (20 pts)
    # Simple check: string comparison of raw outputs
    if system_raw.strip() != initial_raw.strip():
        score += 20
        feedback_parts.append("✅ System notification state changed")
    else:
        feedback_parts.append("❌ No changes made to system settings")

    # 3. Score: Check Channel Configurations (40 pts)
    # - Critical should be ENABLED
    # - Non-critical should be DISABLED
    
    correct_configs = 0
    total_checks = 0
    
    for ch in channels:
        is_critical = any(k.lower() in ch['name'].lower() for k in critical_keywords)
        
        if is_critical:
            total_checks += 1
            if ch['enabled']:
                correct_configs += 1
            else:
                feedback_parts.append(f"⚠️ Critical channel '{ch['name']}' was disabled")
        else:
            # Assume non-critical
            total_checks += 1
            if not ch['enabled']:
                correct_configs += 1
            else:
                feedback_parts.append(f"⚠️ Non-essential channel '{ch['name']}' left enabled")

    if total_checks > 0:
        config_score = (correct_configs / total_checks) * 40
        score += config_score
        feedback_parts.append(f"✅ Channel configuration accuracy: {int((correct_configs/total_checks)*100)}%")
    else:
        # Fallback if keywords don't match anything (unlikely)
        feedback_parts.append("⚠️ No channels matched keyword criteria")

    # 4. Score: Check Output File (30 pts)
    file_exists = result.get('file_exists', False)
    file_created = result.get('file_created_during_task', False)
    file_content = result.get('file_content', '')
    
    if file_exists and file_created:
        score += 10
        feedback_parts.append("✅ Config file created")
        
        # Check content accuracy
        # Does the file list channels and states?
        lines = file_content.split('\n')
        valid_lines = 0
        matches_reality = 0
        
        for line in lines:
            if ':' in line:
                valid_lines += 1
                parts = line.split(':')
                fname = parts[0].strip()
                fstate = parts[1].strip().lower()
                
                # Check against reality
                real_ch = next((c for c in channels if c['name'].lower() == fname.lower()), None)
                if real_ch:
                    real_state_str = "enabled" if real_ch['enabled'] else "disabled"
                    if real_state_str in fstate:
                        matches_reality += 1
        
        if valid_lines >= len(channels) - 1: # Allow slight mismatch
            score += 10
            feedback_parts.append("✅ File format correct")
        
        if valid_lines > 0 and (matches_reality / valid_lines) > 0.8:
            score += 10
            feedback_parts.append("✅ File content matches system state")
    else:
        feedback_parts.append("❌ Config file missing or not created during task")

    # 5. Score: Navigation/UI (10 pts)
    # Implicitly checked if settings changed, but we assume if they changed settings, 
    # they navigated there.
    if score > 20: 
        score += 10

    # Final Result
    passed = score >= 55 and (correct_configs > 0)
    
    return {
        "passed": passed,
        "score": min(100, int(score)),
        "feedback": " | ".join(feedback_parts)
    }