#!/usr/bin/env python3
"""
Verifier for camera_coverage_gap_analysis task.

Verifies:
1. JSON Report existence and structure.
2. Accuracy of identified gaps compared to actual system state (Ground Truth).
3. Anti-gaming (file creation time).
"""

import json
import os
import tempfile
import logging
from datetime import datetime

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_coverage_gap_analysis(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    score = 0
    feedback_parts = []
    
    # ---------------------------------------------------------
    # 1. Load Data from Container
    # ---------------------------------------------------------
    files_to_fetch = {
        "result": "/tmp/task_result.json",
        "agent_report": "/tmp/agent_report.json",
        "ground_truth": "/tmp/ground_truth_state.json"
    }
    
    data = {}
    
    for key, path in files_to_fetch.items():
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env(path, temp_file.name)
            with open(temp_file.name, 'r') as f:
                content = f.read().strip()
                if content:
                    data[key] = json.loads(content)
                else:
                    data[key] = {}
        except Exception as e:
            logger.error(f"Failed to copy/read {key}: {e}")
            data[key] = {}
        finally:
            if os.path.exists(temp_file.name):
                os.unlink(temp_file.name)

    result = data.get("result", {})
    agent_report = data.get("agent_report", {})
    ground_truth = data.get("ground_truth", {})

    # ---------------------------------------------------------
    # 2. Verify File Existence & Timing (20 pts)
    # ---------------------------------------------------------
    if result.get("output_exists") and result.get("file_created_during_task"):
        score += 20
        feedback_parts.append("✅ Report file created during task")
    elif result.get("output_exists"):
        score += 5
        feedback_parts.append("⚠️ Report file exists but timestamp is old")
    else:
        return {"passed": False, "score": 0, "feedback": "❌ Report file not found"}

    # ---------------------------------------------------------
    # 3. Verify Structure (10 pts)
    # ---------------------------------------------------------
    required_keys = ["system_name", "gaps", "summary"]
    required_gap_keys = ["cameras_not_recording", "cameras_not_in_any_layout", "users_without_layouts"]
    
    structure_valid = True
    if not all(k in agent_report for k in required_keys):
        structure_valid = False
    if "gaps" in agent_report and not all(k in agent_report["gaps"] for k in required_gap_keys):
        structure_valid = False
        
    if structure_valid:
        score += 10
        feedback_parts.append("✅ Report structure valid")
    else:
        feedback_parts.append("❌ Report structure missing required keys")

    # ---------------------------------------------------------
    # 4. Compute Ground Truth Gaps
    # ---------------------------------------------------------
    gt_cameras = ground_truth.get("cameras", [])
    gt_layouts = ground_truth.get("layouts", [])
    gt_users = ground_truth.get("users", [])

    # Gap A: Cameras Not Recording
    # Logic: schedule.isEnabled is false OR schedule.tasks is empty
    gt_gap_recording = []
    for cam in gt_cameras:
        schedule = cam.get("schedule", {})
        is_enabled = schedule.get("isEnabled", False)
        tasks = schedule.get("tasks", [])
        if not is_enabled or not tasks:
            gt_gap_recording.append(cam["id"])

    # Gap B: Cameras Not In Any Layout
    # Logic: Collect all item resourceIds from all layouts
    cameras_in_layouts = set()
    for layout in gt_layouts:
        items = layout.get("items", [])
        for item in items:
            rid = item.get("resourceId")
            if rid:
                cameras_in_layouts.add(rid)
    
    gt_gap_layouts = []
    for cam in gt_cameras:
        if cam["id"] not in cameras_in_layouts:
            gt_gap_layouts.append(cam["id"])

    # Gap C: Users Without Layouts
    # Logic: User ID is not the "parentId" of any layout
    # Note: Layouts have a 'parentId' which is the User ID of the owner
    users_with_layouts = set()
    for layout in gt_layouts:
        owner_id = layout.get("parentId")
        if owner_id:
            users_with_layouts.add(owner_id)
            
    gt_gap_users = []
    for user in gt_users:
        # Exclude special system users if necessary, but usually standard users list is fine
        # Cloud users might behave differently, but we are using local users.
        if user["id"] not in users_with_layouts and user.get("name") != "admin": # Admin often implicit, but let's see
             gt_gap_users.append(user["id"])
    
    # Note: admin usually owns layouts. If our setup created layouts as admin, admin is safe.
    # The setup script creates 'nightshift_operator' without layouts.

    # ---------------------------------------------------------
    # 5. Verify Content Accuracy (70 pts total)
    # ---------------------------------------------------------
    
    def check_overlap(agent_list, gt_list_ids, label):
        """Returns score_inc, msg"""
        agent_ids = [item.get("id") for item in agent_list if isinstance(item, dict)]
        
        # Precision/Recall check
        # We'll just check if the sets of IDs match reasonably well
        agent_set = set(agent_ids)
        gt_set = set(gt_list_ids)
        
        if not gt_set:
            # If no gaps expected
            if not agent_set:
                return 20, f"✅ {label}: Correctly identified no gaps"
            else:
                return 0, f"❌ {label}: Reported gaps where none exist"
        
        intersection = agent_set.intersection(gt_set)
        
        if agent_set == gt_set:
            return 20, f"✅ {label}: Perfect match ({len(agent_set)} items)"
        elif len(intersection) > 0:
            # Partial credit
            return 10, f"⚠️ {label}: Partial match ({len(intersection)}/{len(gt_set)} found)"
        else:
            return 0, f"❌ {label}: Failed to identify gaps"

    # Check Recording Gaps (20 pts)
    agent_rec = agent_report.get("gaps", {}).get("cameras_not_recording", [])
    pts_rec, msg_rec = check_overlap(agent_rec, gt_gap_recording, "Recording Gaps")
    score += pts_rec
    feedback_parts.append(msg_rec)

    # Check Layout Gaps (25 pts) - weighted slightly higher
    agent_lay = agent_report.get("gaps", {}).get("cameras_not_in_any_layout", [])
    pts_lay, msg_lay = check_overlap(agent_lay, gt_gap_layouts, "Unmonitored Cameras")
    score += pts_lay + (5 if pts_lay == 20 else 0) # Bonus 5 for perfect layout check
    feedback_parts.append(msg_lay)

    # Check User Gaps (25 pts)
    agent_user = agent_report.get("gaps", {}).get("users_without_layouts", [])
    pts_user, msg_user = check_overlap(agent_user, gt_gap_users, "Empty Users")
    score += pts_user + (5 if pts_user == 20 else 0) # Bonus 5 for perfect user check
    feedback_parts.append(msg_user)

    # ---------------------------------------------------------
    # Final Verdict
    # ---------------------------------------------------------
    passed = score >= 60
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }