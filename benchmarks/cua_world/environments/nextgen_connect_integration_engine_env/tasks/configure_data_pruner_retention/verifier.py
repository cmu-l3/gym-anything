#!/usr/bin/env python3
"""Verifier for configure_data_pruner_retention task."""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_configure_data_pruner_retention(traj, env_info, task_info):
    """
    Verify Data Pruner extension and channel pruning settings.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    
    # Expected Global Settings
    exp_pruner_enabled = str(metadata.get('pruner_enabled', 'true')).lower()
    exp_pruner_hour = str(metadata.get('pruner_hour', '3'))
    exp_pruner_minute = str(metadata.get('pruner_minute', '0'))
    exp_pruner_block = str(metadata.get('pruner_block_size', '1000'))
    exp_pruner_archive = str(metadata.get('pruner_archive', 'true')).lower()
    exp_pruner_events_days = str(metadata.get('pruner_events_days', '31'))

    # Expected ADT Settings
    exp_adt_meta = str(metadata.get('adt_meta_days', '7'))
    exp_adt_content = str(metadata.get('adt_content_days', '3'))
    exp_adt_archive = str(metadata.get('adt_archive', 'true')).lower()

    # Expected Lab Settings
    exp_lab_meta = str(metadata.get('lab_meta_days', '90'))
    exp_lab_content = str(metadata.get('lab_content_days', '30'))
    exp_lab_archive = str(metadata.get('lab_archive', 'true')).lower()

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/configure_data_pruner_retention_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    pruner_config = result.get('pruner_config', {})
    channels = result.get('channels', {})
    
    score = 0
    feedback_parts = []

    # --- 1. Verify Global Data Pruner Settings (50 points) ---
    
    # Enabled
    act_enabled = str(pruner_config.get('enabled', 'false')).lower()
    if act_enabled == exp_pruner_enabled:
        score += 15
        feedback_parts.append("Data Pruner enabled")
    else:
        feedback_parts.append(f"Data Pruner NOT enabled (found: {act_enabled})")

    # Schedule
    act_hour = str(pruner_config.get('scheduler.pollingHour', '-1'))
    act_min = str(pruner_config.get('scheduler.pollingMinute', '-1'))
    if act_hour == exp_pruner_hour:
        score += 10
        feedback_parts.append(f"Schedule hour correct ({act_hour})")
    else:
        feedback_parts.append(f"Schedule hour mismatch (expected {exp_pruner_hour}, got {act_hour})")
        
    if act_min == exp_pruner_minute:
        score += 5
        feedback_parts.append(f"Schedule minute correct ({act_min})")

    # Archive & Block Size
    act_archive = str(pruner_config.get('archiveEnabled', 'false')).lower()
    act_block = str(pruner_config.get('pruningBlockSize', '0'))
    
    if act_archive == exp_pruner_archive:
        score += 10
        feedback_parts.append("Global archive enabled")
    
    if act_block == exp_pruner_block:
        score += 5
        feedback_parts.append(f"Block size correct ({act_block})")

    # Prune Events
    act_prune_events = str(pruner_config.get('pruneEvents', 'false')).lower()
    act_event_age = str(pruner_config.get('pruneEventAge', '0'))
    
    if act_prune_events == 'true' and act_event_age == exp_pruner_events_days:
        score += 5
        feedback_parts.append(f"Event pruning correct ({act_event_age} days)")

    # --- 2. Verify ADT Channel Settings (25 points) ---
    adt_config = channels.get('Regional_ADT_Feed', {})
    if not adt_config:
        feedback_parts.append("Regional_ADT_Feed channel settings not found")
    else:
        if str(adt_config.get('pruneMetaDataDays', '')) == exp_adt_meta:
            score += 12
            feedback_parts.append("ADT metadata days correct")
        else:
            feedback_parts.append(f"ADT metadata days mismatch (got {adt_config.get('pruneMetaDataDays')})")
            
        if str(adt_config.get('pruneContentDays', '')) == exp_adt_content:
            score += 8
            feedback_parts.append("ADT content days correct")
        else:
             feedback_parts.append(f"ADT content days mismatch (got {adt_config.get('pruneContentDays')})")
             
        if str(adt_config.get('archiveEnabled', 'false')).lower() == exp_adt_archive:
            score += 5
            feedback_parts.append("ADT archive enabled")

    # --- 3. Verify Lab Channel Settings (25 points) ---
    lab_config = channels.get('Lab_Orders_Interface', {})
    if not lab_config:
        feedback_parts.append("Lab_Orders_Interface channel settings not found")
    else:
        if str(lab_config.get('pruneMetaDataDays', '')) == exp_lab_meta:
            score += 12
            feedback_parts.append("Lab metadata days correct")
        else:
             feedback_parts.append(f"Lab metadata days mismatch (got {lab_config.get('pruneMetaDataDays')})")

        if str(lab_config.get('pruneContentDays', '')) == exp_lab_content:
            score += 8
            feedback_parts.append("Lab content days correct")
        else:
             feedback_parts.append(f"Lab content days mismatch (got {lab_config.get('pruneContentDays')})")

        if str(lab_config.get('archiveEnabled', 'false')).lower() == exp_lab_archive:
            score += 5
            feedback_parts.append("Lab archive enabled")

    # Pass logic
    # Must have enabled the pruner (15 pts) AND got at least one channel mostly right
    passed = score >= 70 and act_enabled == exp_pruner_enabled
    
    return {
        "passed": passed,
        "score": score,
        "feedback": "\n".join(feedback_parts)
    }