#!/usr/bin/env python3
"""
Verifier for configure_motion_detection task.
Validates that the agent correctly configured motion detection and recording schedules via API.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_configure_motion_detection(traj, env_info, task_info):
    """
    Verify the agent configured the specific cameras correctly.
    
    Criteria:
    1. Target cameras (Entrance, Server Room, Loading Dock) must have:
       - motionType: "software"
       - schedule tasks with recordingType: "motionOnly"
    2. Ignored cameras (Parking Lot, Lobby) must have:
       - motionType: "default"
       - schedule tasks with recordingType: "always" (or at least NOT "motionOnly")
    3. Agent must generate a valid JSON report reflecting the state.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Define targets
    TARGET_CAMERAS = ["Entrance Camera", "Server Room Camera", "Loading Dock Camera"]
    IGNORED_CAMERAS = ["Parking Lot Camera", "Lobby Camera"]

    score = 0
    feedback_parts = []
    
    # Files to retrieve
    system_state_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    agent_report_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    task_result_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')

    try:
        # 1. Load Task Result Summary
        copy_from_env("/tmp/task_result.json", task_result_file.name)
        with open(task_result_file.name, 'r') as f:
            task_result = json.load(f)

        # Check report existence (Anti-gaming: created during task)
        if task_result.get("report_exists") and task_result.get("report_created_during_task"):
            score += 5
            feedback_parts.append("Report file created during task")
        elif task_result.get("report_exists"):
            feedback_parts.append("Report file exists but timestamp is old")
        else:
            feedback_parts.append("Report file missing")

        # 2. Load System State (Actual Ground Truth)
        copy_from_env("/tmp/system_state.json", system_state_file.name)
        with open(system_state_file.name, 'r') as f:
            devices = json.load(f)
            
        # Map devices by name for easier checking
        device_map = {d.get('name'): d for d in devices}
        
        # Verify Target Cameras
        targets_configured = 0
        for name in TARGET_CAMERAS:
            cam = device_map.get(name)
            if not cam:
                feedback_parts.append(f"CRITICAL: Camera '{name}' not found in system")
                continue
                
            # Check motionType
            m_type = cam.get('motionType', '')
            if m_type == 'software':
                score += 10
                feedback_parts.append(f"✓ {name}: motionType is software")
            else:
                feedback_parts.append(f"✗ {name}: motionType is '{m_type}' (expected 'software')")
                
            # Check Schedule
            schedule = cam.get('schedule', {})
            tasks = schedule.get('tasks', [])
            if tasks and all(t.get('recordingType') == 'motionOnly' for t in tasks):
                score += 8
                feedback_parts.append(f"✓ {name}: schedule is motionOnly")
                targets_configured += 1
            else:
                # Check if mixed or incorrect
                types = set(t.get('recordingType') for t in tasks)
                feedback_parts.append(f"✗ {name}: schedule types are {types} (expected 'motionOnly')")

        # Verify Ignored Cameras (Should NOT change)
        ignored_preserved = 0
        for name in IGNORED_CAMERAS:
            cam = device_map.get(name)
            if not cam:
                continue
                
            m_type = cam.get('motionType', '')
            if m_type == 'default':
                score += 5
                feedback_parts.append(f"✓ {name} preserved (motionType: default)")
            else:
                feedback_parts.append(f"✗ {name} modified incorrectly (motionType: {m_type})")
                
            schedule = cam.get('schedule', {})
            tasks = schedule.get('tasks', [])
            # Should NOT be motionOnly (default was 'always')
            if tasks and not all(t.get('recordingType') == 'motionOnly' for t in tasks):
                score += 3
                ignored_preserved += 1
            else:
                feedback_parts.append(f"✗ {name} schedule modified to motionOnly (should be unchanged)")

        # 3. Verify Agent Report Content
        if task_result.get("report_exists"):
            try:
                copy_from_env("/tmp/agent_report.json", agent_report_file.name)
                with open(agent_report_file.name, 'r') as f:
                    report = json.load(f)
                
                if "cameras" in report and isinstance(report["cameras"], list):
                    score += 5
                    report_map = {c.get('name'): c for c in report['cameras']}
                    
                    # Check report accuracy against Ground Truth
                    accurate_entries = 0
                    total_checks = 0
                    
                    for name in TARGET_CAMERAS + IGNORED_CAMERAS:
                        total_checks += 1
                        entry = report_map.get(name)
                        actual = device_map.get(name)
                        
                        if entry and actual:
                            # Verify fields match actual state
                            entry_m_type = entry.get('motionType')
                            actual_m_type = actual.get('motionType')
                            
                            # Verify enabled flag
                            entry_enabled = entry.get('motionDetectionEnabled')
                            expected_enabled = (actual_m_type == 'software')
                            
                            if entry_m_type == actual_m_type and entry_enabled == expected_enabled:
                                accurate_entries += 1
                    
                    # Proportional score for report accuracy
                    if total_checks > 0:
                        accuracy_points = int((accurate_entries / total_checks) * 20)
                        score += accuracy_points
                        feedback_parts.append(f"Report accuracy: {accurate_entries}/{total_checks} cameras match system state")
                else:
                    feedback_parts.append("Report format incorrect (missing 'cameras' list)")
            except json.JSONDecodeError:
                feedback_parts.append("Report file is not valid JSON")
            except Exception as e:
                feedback_parts.append(f"Error reading report: {str(e)}")

    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Verification error: {str(e)}"}
    finally:
        # Cleanup
        for fname in [system_state_file.name, agent_report_file.name, task_result_file.name]:
            if os.path.exists(fname):
                os.unlink(fname)

    passed = score >= 60 and targets_configured >= 2
    
    return {
        "passed": passed,
        "score": score,
        "feedback": "\n".join(feedback_parts)
    }