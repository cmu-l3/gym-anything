#!/usr/bin/env python3
import json
import os
import sys

def verify_compound_trigger(traj, env_info, task_info):
    """
    Verify the creation of a compound soft trigger.
    
    Criteria:
    1. At least 2 Event Rules exist for 'Report Incident' (softwareTrigger).
    2. Rule A matches Bookmark criteria (Duration ~60s, Tag 'Manual_Report').
    3. Rule B matches Recording criteria (Duration ~300s).
    4. Both rules target the 'Entrance Camera'.
    5. Both rules use the same Trigger Name (and effectively icon) to merge.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env not available"}

    # Load metadata
    metadata = task_info.get('metadata', {})
    target_camera_name = metadata.get('target_camera_name', 'Entrance Camera')
    trigger_name = metadata.get('trigger_name', 'Report Incident')
    expected_bookmark_tag = metadata.get('bookmark_tag', 'Manual_Report')
    expected_bookmark_dur = metadata.get('bookmark_duration_ms', 60000)
    expected_recording_dur = metadata.get('recording_duration_ms', 300000)

    # Copy files from env
    local_rules_path = "event_rules.json"
    local_devices_path = "devices.json"
    
    try:
        copy_from_env("/tmp/event_rules.json", local_rules_path)
        copy_from_env("/tmp/devices.json", local_devices_path)
        
        with open(local_rules_path, 'r') as f:
            rules = json.load(f)
        with open(local_devices_path, 'r') as f:
            devices = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task data: {str(e)}"}
    finally:
        # Cleanup
        if os.path.exists(local_rules_path): os.remove(local_rules_path)
        if os.path.exists(local_devices_path): os.remove(local_devices_path)

    # 1. Resolve Camera ID
    camera_id = None
    for d in devices:
        if d.get('name') == target_camera_name:
            camera_id = d.get('id')
            break
            
    if not camera_id:
        return {"passed": False, "score": 0, "feedback": f"Could not find camera '{target_camera_name}' in system."}

    # 2. Filter Rules for 'Report Incident' Soft Triggers
    target_rules = []
    
    for rule in rules:
        if rule.get('eventType') != 'softwareTrigger':
            continue
            
        # Extract caption/name from eventCondition
        # Note: API structure can vary, but params is usually where specific config lives
        condition = rule.get('eventCondition', {})
        params = condition.get('params', {})
        
        # Normalize params (sometimes stringified JSON, sometimes dict)
        if isinstance(params, str):
            try: params = json.loads(params)
            except: pass
            
        # Check caption
        if trigger_name in params.get('caption', ''):
            target_rules.append(rule)

    if not target_rules:
        return {"passed": False, "score": 0, "feedback": f"No Soft Trigger rules found with name '{trigger_name}'."}

    # 3. Analyze Actions
    has_bookmark_action = False
    has_recording_action = False
    correct_camera_target = True
    
    feedback_details = []
    
    for rule in target_rules:
        # Check resource targeting (Trigger must be ON the correct camera)
        # eventResourceIds should contain the camera ID
        event_resources = rule.get('eventResourceIds', [])
        if camera_id not in event_resources:
            correct_camera_target = False
            feedback_details.append(f"Rule {rule.get('id')} is not assigned to '{target_camera_name}'.")
            continue

        action_type = rule.get('actionType')
        action_params = rule.get('actionParams', {})
        if isinstance(action_params, str):
            try: action_params = json.loads(action_params)
            except: pass

        # Check for Bookmark Action
        if action_type in ['bookmark', 'bookmarkLog']:
            # Verify Duration
            duration = int(float(action_params.get('durationMs', 0)))
            # Verify Tag
            tags = action_params.get('tags', [])
            if isinstance(tags, str): tags = [tags] # sometimes single string
            
            # Allow 10% tolerance on duration
            dur_ok = abs(duration - expected_bookmark_dur) < 6000 
            tag_ok = any(expected_bookmark_tag in t for t in tags)
            
            if dur_ok and tag_ok:
                has_bookmark_action = True
                feedback_details.append("Found valid Bookmark action.")
            else:
                feedback_details.append(f"Bookmark action found but incorrect settings (Dur: {duration}, Tags: {tags}).")

        # Check for Recording Action
        elif action_type in ['recording', 'cameraRecording']:
            duration = int(float(action_params.get('durationMs', 0)))
            # Allow 10% tolerance
            if abs(duration - expected_recording_dur) < 30000:
                has_recording_action = True
                feedback_details.append("Found valid Recording action.")
            else:
                feedback_details.append(f"Recording action found but incorrect duration ({duration}ms).")

    # 4. Scoring
    score = 0
    
    # Base: Trigger exists
    if len(target_rules) > 0:
        score += 20
        
    # Correct Camera targeting
    if correct_camera_target:
        score += 20
    else:
        feedback_details.append("Triggers are not assigned to the correct camera.")

    # Bookmark Action Correct
    if has_bookmark_action:
        score += 30
    else:
        feedback_details.append("Missing or incorrect Bookmark action.")
        
    # Recording Action Correct
    if has_recording_action:
        score += 30
    else:
        feedback_details.append("Missing or incorrect Recording action.")
        
    # Check for merging (implicit: if both exist with same name filter, they merge)
    is_compound = has_bookmark_action and has_recording_action
    
    passed = is_compound and correct_camera_target
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_details)
    }