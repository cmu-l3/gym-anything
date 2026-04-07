#!/usr/bin/env python3
import json
import base64
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_recording_policy(traj, env_info, task_info):
    """
    Verifies that the agent configured the recording schedules correctly according to the tiers
    and generated a valid compliance report.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: Copy function not available"}

    # Define the Policy Requirements (Ground Truth)
    TIERS = {
        "Entrance Camera":      {"fps": 25, "bitrate": 4096, "quality": "high"},
        "Parking Lot Camera":   {"fps": 15, "bitrate": 2048, "quality": "normal"},
        "Lobby Camera":         {"fps": 15, "bitrate": 2048, "quality": "normal"},
        "Server Room Camera":   {"fps": 10, "bitrate": 1024, "quality": "low"}
    }
    
    # Expected total daily storage (GB)
    # Sum of (bitrate_kbps * 86400 / 8 / 1024 / 1024)
    # 4096: ~42.18 GB
    # 2048: ~21.09 GB
    # 2048: ~21.09 GB
    # 1024: ~10.54 GB
    # Total: ~94.9 GB
    EXPECTED_TOTAL_GB = 0
    for cam, specs in TIERS.items():
        daily_gb = (specs["bitrate"] * 86400) / (8 * 1024 * 1024)
        EXPECTED_TOTAL_GB += daily_gb

    score = 0
    max_score = 100
    feedback_parts = []
    
    # 1. Retrieve Data from Container
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    temp_devices = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    
    try:
        # Get the main result file
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            task_result = json.load(f)
            
        # Get the devices config dump
        copy_from_env("/tmp/final_devices_config.json", temp_devices.name)
        with open(temp_devices.name, 'r') as f:
            devices_list = json.load(f)
            
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve verification data: {str(e)}"}
    finally:
        if os.path.exists(temp_result.name): os.unlink(temp_result.name)
        if os.path.exists(temp_devices.name): os.unlink(temp_devices.name)

    # 2. Verify Camera Configurations (API Check)
    # Convert list to dict for easier lookup
    cameras_map = {d.get('name'): d for d in devices_list}
    
    cameras_configured_correctly = 0
    total_cameras_checked = 0
    
    for cam_name, specs in TIERS.items():
        if cam_name not in cameras_map:
            feedback_parts.append(f"Camera '{cam_name}' not found in system.")
            continue
            
        cam_data = cameras_map[cam_name]
        schedule = cam_data.get('schedule', {})
        tasks = schedule.get('tasks', [])
        
        # Check 1: Schedule Enabled (10 pts split across cams)
        if not schedule.get('isEnabled'):
            feedback_parts.append(f"{cam_name}: Recording NOT enabled.")
            continue
            
        # Check 2: Task Parameters (FPS, Bitrate, Quality)
        # We expect tasks to cover the whole week. Usually this is 1 task spanning days, or multiple.
        # We'll check if at least one task matches the specs.
        match_found = False
        days_covered = 0
        
        for task in tasks:
            # Check params
            fps_match = task.get('fps') == specs['fps']
            bitrate_match = task.get('bitrateKbps') == specs['bitrate']
            quality_match = task.get('streamQuality') == specs['quality']
            
            if fps_match and bitrate_match and quality_match:
                match_found = True
                # Rough check for coverage (Nx uses 1=Mon ... 7=Sun)
                # If startTime is 0 and endTime is 86400, it covers the day
                if task.get('startTime') == 0 and task.get('endTime') == 86400:
                    # dayOfWeek can be a single int
                    days_covered += 1
        
        # Scoring per camera (Total 60 pts for config)
        # 15 pts per camera
        cam_score = 0
        if match_found:
            cam_score += 10 # Parameter match
            if days_covered >= 1: # Basic coverage check
                cam_score += 5
            cameras_configured_correctly += 1
            feedback_parts.append(f"{cam_name}: Configured correctly.")
        else:
            feedback_parts.append(f"{cam_name}: Incorrect parameters (Expected {specs['fps']}fps, {specs['bitrate']}kbps, {specs['quality']}).")
            
        score += cam_score
        total_cameras_checked += 1

    # 3. Verify Report File (Total 40 pts)
    report_exists = task_result.get('report_exists', False)
    report_fresh = task_result.get('report_created_during_task', False)
    
    if report_exists and report_fresh:
        score += 10
        feedback_parts.append("Report file created.")
        
        # Decode content
        try:
            content_b64 = task_result.get('report_content_b64', "")
            content = base64.b64decode(content_b64).decode('utf-8', errors='ignore')
            
            # Check for camera names in report (10 pts)
            names_found = 0
            for name in TIERS.keys():
                if name in content:
                    names_found += 1
            
            if names_found >= 3:
                score += 10
                feedback_parts.append("Report lists cameras.")
            else:
                feedback_parts.append("Report missing camera names.")
            
            # Check for storage calculation (20 pts)
            # Look for a number close to the expected total
            import re
            numbers = re.findall(r"[-+]?\d*\.\d+|\d+", content)
            found_calculation = False
            for num in numbers:
                try:
                    val = float(num)
                    # Tolerance +/- 5 GB
                    if abs(val - EXPECTED_TOTAL_GB) < 5.0:
                        found_calculation = True
                        break
                except:
                    continue
            
            if found_calculation:
                score += 20
                feedback_parts.append(f"Storage estimate correct (~{EXPECTED_TOTAL_GB:.2f} GB).")
            else:
                feedback_parts.append(f"Storage estimate incorrect or missing (Expected ~{EXPECTED_TOTAL_GB:.2f} GB).")
                
        except Exception as e:
            feedback_parts.append(f"Error parsing report: {str(e)}")
    else:
        feedback_parts.append("Report file missing or stale.")

    # 4. Final Result
    passed = (score >= 60) and (cameras_configured_correctly >= 3)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback_parts)
    }