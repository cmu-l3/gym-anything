#!/usr/bin/env python3
import json
import os
import sys
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_schedules(traj, env_info, task_info):
    """
    Verifies that the Nx Witness camera schedules match the detailed holiday requirements.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Define score components
    score = 0
    feedback_lines = []
    
    # Copy result artifacts
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    temp_devices = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result_data = json.load(f)
            
        # Check if API dump exists
        api_dump_path = result_data.get("api_devices_dump_path")
        if not api_dump_path:
            return {"passed": False, "score": 0, "feedback": "No API data captured."}
            
        copy_from_env(api_dump_path, temp_devices.name)
        with open(temp_devices.name, 'r') as f:
            devices = json.load(f)
            
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Error loading task data: {str(e)}"}
    finally:
        if os.path.exists(temp_result.name): os.unlink(temp_result.name)
        if os.path.exists(temp_devices.name): os.unlink(temp_devices.name)

    # --- VERIFICATION LOGIC ---

    # Map device names to objects for easy lookup
    camera_map = {d.get('name'): d for d in devices if d.get('name')}
    
    # 1. Verify Report File (10 points)
    if result_data.get('report_exists') and result_data.get('report_created_during_task'):
        score += 10
        feedback_lines.append("✓ Report file created successfully.")
    else:
        feedback_lines.append("✗ Report file missing or not created during task.")

    # Helper to check tasks
    def check_task_coverage(tasks, day, start, end, rec_type, fps, quality):
        """Returns True if a task exists covering this specific slot with correct params."""
        for t in tasks:
            # Check day
            if t.get('dayOfWeek') != day: continue
            
            # Check overlap/coverage: strict equality for simplicity or containment
            t_start = t.get('startTime', -1)
            t_end = t.get('endTime', -1)
            
            # Allow small tolerance (1s) for timestamps
            if abs(t_start - start) > 1 or abs(t_end - end) > 1: continue
            
            # Check params
            if t.get('recordingType') != rec_type: continue
            if abs(t.get('fps', 0) - fps) > 1: continue
            if t.get('streamQuality') != quality: continue
            
            return True
        return False

    # 2. Verify Schedules (90 points distributed)
    
    # GROUP A: High Traffic (Entrance, Lobby) - 24 points total (12 each)
    # Reqs: Mon-Sun (1-7), 0-86400, always, high, 25fps
    for cam_name in ["Entrance Camera", "Lobby Camera"]:
        cam = camera_map.get(cam_name)
        if not cam:
            feedback_lines.append(f"? {cam_name} not found in system (skipping).")
            continue
            
        schedule = cam.get('schedule', {})
        if not schedule.get('isEnabled'):
            feedback_lines.append(f"✗ {cam_name} schedule is disabled.")
            continue
            
        cam_score = 0
        tasks = schedule.get('tasks', [])
        
        # Check all 7 days
        days_correct = 0
        for d in range(1, 8):
            if check_task_coverage(tasks, d, 0, 86400, 'always', 25, 'high'):
                days_correct += 1
        
        if days_correct == 7:
            cam_score = 12
            feedback_lines.append(f"✓ {cam_name} configured correctly (24/7 High).")
        else:
            cam_score = int((days_correct / 7) * 12)
            feedback_lines.append(f"⚠ {cam_name} partially correct ({days_correct}/7 days).")
            
        score += cam_score

    # GROUP B: Perimeter (Parking Lot, Loading Dock) - 40 points total (20 each)
    # Reqs: 
    #   08:00(28800)-22:00(79200): always, high, 15fps
    #   22:00(79200)-24:00(86400): motionOnly, normal, 10fps
    #   00:00(0)-08:00(28800): motionOnly, normal, 10fps
    for cam_name in ["Parking Lot Camera", "Loading Dock Camera"]:
        cam = camera_map.get(cam_name)
        if not cam: continue
        
        schedule = cam.get('schedule', {})
        if not schedule.get('isEnabled'): continue
        
        tasks = schedule.get('tasks', [])
        days_correct = 0
        
        for d in range(1, 8):
            # Check 3 segments per day
            day_ok = check_task_coverage(tasks, d, 28800, 79200, 'always', 15, 'high')
            eve_ok = check_task_coverage(tasks, d, 79200, 86400, 'motionOnly', 10, 'normal')
            morn_ok = check_task_coverage(tasks, d, 0, 28800, 'motionOnly', 10, 'normal')
            
            if day_ok and eve_ok and morn_ok:
                days_correct += 1
                
        if days_correct == 7:
            score += 20
            feedback_lines.append(f"✓ {cam_name} configured correctly (Hybrid schedule).")
        else:
            partial = int((days_correct / 7) * 20)
            score += partial
            feedback_lines.append(f"⚠ {cam_name} partially correct ({days_correct}/7 days).")

    # GROUP C: Server Room - 16 points
    # Reqs:
    #   Mon-Fri (1-5): 0-86400, always, low, 5fps
    #   Sat-Sun (6-7): 0-86400, motionOnly, low, 5fps
    cam_name = "Server Room Camera"
    cam = camera_map.get(cam_name)
    if cam:
        schedule = cam.get('schedule', {})
        if schedule.get('isEnabled'):
            tasks = schedule.get('tasks', [])
            weekdays_ok = 0
            weekends_ok = 0
            
            for d in range(1, 6):
                if check_task_coverage(tasks, d, 0, 86400, 'always', 5, 'low'):
                    weekdays_ok += 1
            
            for d in range(6, 8):
                if check_task_coverage(tasks, d, 0, 86400, 'motionOnly', 5, 'low'):
                    weekends_ok += 1
            
            total_days = weekdays_ok + weekends_ok
            if total_days == 7:
                score += 16
                feedback_lines.append(f"✓ {cam_name} configured correctly (Weekday/Weekend).")
            else:
                partial = int((total_days / 7) * 16)
                score += partial
                feedback_lines.append(f"⚠ {cam_name} partially correct ({total_days}/7 days).")

    # 3. Global Enabled Check (10 points)
    # Ensure schedules are different (anti-gaming: check if user just pasted the same JSON to all)
    # We compare the 'tasks' list string representation of Entrance vs Parking
    ent_cam = camera_map.get("Entrance Camera", {})
    prk_cam = camera_map.get("Parking Lot Camera", {})
    
    ent_tasks = json.dumps(ent_cam.get('schedule', {}).get('tasks', []), sort_keys=True)
    prk_tasks = json.dumps(prk_cam.get('schedule', {}).get('tasks', []), sort_keys=True)
    
    if ent_tasks != prk_tasks and len(ent_tasks) > 5 and len(prk_tasks) > 5:
        score += 10
        feedback_lines.append("✓ Schedules are differentiated correctly.")
    else:
        feedback_lines.append("⚠ Schedules appear identical across different camera groups or are empty.")

    return {
        "passed": score >= 60,
        "score": score,
        "feedback": "\n".join(feedback_lines)
    }