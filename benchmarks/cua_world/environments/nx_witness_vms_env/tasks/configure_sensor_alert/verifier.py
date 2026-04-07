#!/usr/bin/env python3
"""
Verifier for configure_sensor_alert task.

Criteria:
1. Generic Event Rule exists with source "TempSensor_01" and caption "Overheat" (40 pts)
2. Rule Action is "bookmarkLog" pointing to correct camera (20 pts)
3. A Bookmark was actually created during the task (proving simulation worked) (30 pts)
4. Bookmark has correct tags (10 pts)
"""

import json
import os
import sys
import tempfile
import logging

# Set up logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_configure_sensor_alert(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load expected values from metadata
    metadata = task_info.get('metadata', {})
    expected_source = metadata.get('target_source', 'TempSensor_01')
    expected_caption = metadata.get('target_caption', 'Overheat')
    expected_tags = set(metadata.get('required_tags', ['environment', 'danger']))

    # Fetch result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    rules = data.get('rules', [])
    bookmarks = data.get('bookmarks', [])
    target_cam_id = data.get('target_camera_id', '')

    feedback = []
    score = 0

    # =========================================================
    # Check 1: Event Rule Configuration (60 pts total)
    # =========================================================
    found_rule = False
    correct_trigger = False
    correct_action = False
    
    # Nx Witness Event Types: 'undefinedEvent' is usually Generic Event
    # Check rule properties
    for rule in rules:
        # Check Trigger
        # Note: Depending on Nx version, trigger params are in 'eventCondition' or 'resourceName'/'caption'
        # We check broadly in the JSON dump of the rule
        rule_str = json.dumps(rule)
        
        is_generic = rule.get('eventType') == 'undefinedEvent' or 'undefinedEvent' in rule_str
        has_source = expected_source in rule_str
        has_caption = expected_caption in rule_str
        
        if is_generic and has_source and has_caption:
            correct_trigger = True
            
            # Check Action
            action_type = rule.get('actionType', '')
            # 'bookmarkLog' is the internal name for Create Bookmark
            if action_type == 'bookmarkLog':
                # Check if it targets our camera
                # targetResources usually contains the camera ID
                params = rule.get('actionParams', '')
                resources = rule.get('actionResourceIds', [])
                
                if target_cam_id in resources or target_cam_id in str(params):
                    correct_action = True
                    found_rule = True
                    break

    if correct_trigger:
        score += 40
        feedback.append("✅ Event Rule created with correct triggers (Source/Caption)")
    else:
        feedback.append("❌ Event Rule not found or missing correct Source/Caption triggers")

    if correct_action:
        score += 20
        feedback.append("✅ Event Rule triggers correct Bookmark action on Server Room Camera")
    elif correct_trigger:
        feedback.append("❌ Event Rule found but Action is incorrect (must be Bookmark on target camera)")

    # =========================================================
    # Check 2: Simulation Verification (Bookmark Created) (40 pts)
    # =========================================================
    found_bookmark = False
    bookmark_tags_correct = False
    
    # We already filtered bookmarks by startTime > task_start in export script
    if bookmarks:
        # Look for one that matches our tags
        for bm in bookmarks:
            # Check tags
            # Tags in API might be a list or comma-sep string
            bm_tags_raw = bm.get('tags', [])
            if isinstance(bm_tags_raw, str):
                bm_tags = set(t.strip() for t in bm_tags_raw.split(','))
            else:
                bm_tags = set(bm_tags_raw)
                
            # Check if expected tags are present
            if expected_tags.issubset(bm_tags):
                found_bookmark = True
                bookmark_tags_correct = True
                break
            # Relaxed check: just check if ANY bookmark was created via API (generic event)
            # Generic event bookmarks usually have description matching the event caption
            if expected_caption in bm.get('name', '') or expected_caption in bm.get('description', ''):
                found_bookmark = True
    
    if found_bookmark:
        score += 30
        feedback.append("✅ Simulation successful: Bookmark created via API trigger")
        if bookmark_tags_correct:
            score += 10
            feedback.append("✅ Bookmark contains correct tags")
        else:
            feedback.append("⚠️ Bookmark created but missing required tags")
    else:
        feedback.append("❌ No relevant bookmark found. Simulation via 'curl' may have failed.")

    return {
        "passed": score >= 70,
        "score": score,
        "feedback": " | ".join(feedback)
    }