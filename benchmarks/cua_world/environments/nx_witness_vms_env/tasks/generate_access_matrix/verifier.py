#!/usr/bin/env python3
"""
Verifier for generate_access_matrix task.
Verifies the JSON report against the actual system state captured at task end.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_access_matrix(traj, env_info, task_info):
    """
    Verify the generated access matrix report.
    
    Criteria:
    1. File exists and valid JSON (10 pts)
    2. File created during task (10 pts)
    3. Correct System Name and counts (20 pts)
    4. Access Matrix structure correctness (30 pts)
    5. Camera Coverage correctness (30 pts)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    score = 0
    max_score = 100
    feedback_parts = []
    
    # Helper to get file from env
    def get_json_from_env(remote_path):
        temp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        temp.close()
        try:
            copy_from_env(remote_path, temp.name)
            with open(temp.name, 'r') as f:
                return json.load(f)
        except Exception:
            return None
        finally:
            if os.path.exists(temp.name):
                os.unlink(temp.name)

    # 1. Get Task Result
    task_result = get_json_from_env("/tmp/task_result.json")
    if not task_result:
        return {"passed": False, "score": 0, "feedback": "Failed to retrieve task execution metadata"}

    # 2. Get Report
    report = get_json_from_env("/home/ga/access_matrix_report.json")
    
    # 3. Get Ground Truth Data
    gt_users = get_json_from_env("/tmp/ground_truth_users.json") or []
    gt_layouts = get_json_from_env("/tmp/ground_truth_layouts.json") or []
    gt_devices = get_json_from_env("/tmp/ground_truth_devices.json") or []
    gt_system = get_json_from_env("/tmp/ground_truth_system.json") or {}

    # --- CRITERION 1 & 2: File Status ---
    if not report:
        return {"passed": False, "score": 0, "feedback": "Report file missing or invalid JSON"}
    
    score += 10 # Valid JSON
    feedback_parts.append("Valid JSON report")

    if task_result.get("file_created_during_task", False):
        score += 10
        feedback_parts.append("File created during task")
    else:
        feedback_parts.append("File timestamp invalid (pre-dated)")

    # --- CRITERION 3: Basic Metadata & Counts ---
    # System Name
    actual_name = gt_system.get("systemName", "")
    report_name = report.get("systemName", "")
    if actual_name and report_name == actual_name:
        score += 5
        feedback_parts.append("System Name Correct")
    
    # Counts
    user_match = report.get("totalUsers") == len(gt_users)
    layout_match = report.get("totalLayouts") == len(gt_layouts)
    cam_match = report.get("totalCameras") == len(gt_devices)
    
    if user_match and layout_match and cam_match:
        score += 15
        feedback_parts.append("All counts correct")
    else:
        # Partial credit
        if user_match: score += 5
        if cam_match: score += 5
        feedback_parts.append(f"Counts: Users({user_match}), Layouts({layout_match}), Cams({cam_match})")

    # --- Compute Ground Truth Mappings ---
    # Map ID -> Name
    user_map = {u['id']: u['name'] for u in gt_users}
    cam_map = {d['id']: d['name'] for d in gt_devices}
    
    # Build GT Access Matrix: User -> Layouts -> Cameras
    gt_matrix = {}
    
    for layout in gt_layouts:
        parent_id = layout.get('parentId')
        if not parent_id or parent_id not in user_map:
            continue
            
        user_name = user_map[parent_id]
        if user_name not in gt_matrix:
            gt_matrix[user_name] = {}
            
        layout_name = layout.get('name', 'Unknown')
        
        # Get cameras in this layout
        cams_in_layout = []
        for item in layout.get('items', []):
            res_id = item.get('resourceId')
            if res_id in cam_map:
                cams_in_layout.append(cam_map[res_id])
        
        gt_matrix[user_name][layout_name] = sorted(cams_in_layout)

    # --- CRITERION 4: Verify Access Matrix Content ---
    report_matrix = report.get("accessMatrix", [])
    matrix_correct = 0
    matrix_entries = 0
    
    for entry in report_matrix:
        u_name = entry.get("userName")
        if not u_name: continue
        
        # Check if user exists in GT
        if u_name not in user_map.values():
            continue
            
        # Check layouts
        # If user has no layouts in GT, expect empty or missing layout list
        if u_name not in gt_matrix:
             if not entry.get("layouts"):
                 matrix_correct += 1
             matrix_entries += 1
             continue

        gt_user_layouts = gt_matrix[u_name]
        report_layouts = entry.get("layouts", [])
        
        # Simple check: Does report contain at least one correct layout with correct cameras?
        # We won't demand perfection on every single attribute to allow for format variations,
        # but we check if the DATA is correct.
        
        user_data_good = True
        found_gt_layouts = 0
        
        for r_layout in report_layouts:
            l_name = r_layout.get("layoutName")
            r_cams = [c.get("cameraName") for c in r_layout.get("cameras", [])]
            
            if l_name in gt_user_layouts:
                found_gt_layouts += 1
                if sorted(r_cams) != gt_user_layouts[l_name]:
                    user_data_good = False # Camera mismatch
            else:
                pass # Extra layout reported? 

        if user_data_good and found_gt_layouts > 0:
            matrix_correct += 1
        matrix_entries += 1

    # Score Matrix
    # We expect at least the operators created in setup to have layouts
    if matrix_entries > 0:
        matrix_score = min(30, int((matrix_correct / matrix_entries) * 30))
        score += matrix_score
        feedback_parts.append(f"Matrix Accuracy: {matrix_correct}/{matrix_entries} users correct")
    elif len(gt_matrix) == 0:
        # Edge case: no layouts exist
        score += 30
        feedback_parts.append("Matrix empty (correct)")
    else:
        feedback_parts.append("Matrix empty or invalid")

    # --- CRITERION 5: Camera Coverage Section ---
    report_coverage = report.get("cameraCoverage", [])
    coverage_correct = 0
    total_cams = len(gt_devices)
    
    # Re-map GT: Camera Name -> List of Users
    gt_coverage = {name: set() for name in cam_map.values()}
    
    for u_name, layouts in gt_matrix.items():
        for l_name, cam_names in layouts.items():
            for c_name in cam_names:
                gt_coverage[c_name].add(u_name)
    
    for entry in report_coverage:
        c_name = entry.get("cameraName")
        if c_name in gt_coverage:
            r_users = set(entry.get("accessibleByUsers", []))
            if r_users == gt_coverage[c_name]:
                coverage_correct += 1
    
    if total_cams > 0:
        cov_score = min(30, int((coverage_correct / total_cams) * 30))
        score += cov_score
        feedback_parts.append(f"Coverage Accuracy: {coverage_correct}/{total_cams} cams correct")
    
    # Calculate Final
    return {
        "passed": score >= 60,
        "score": score,
        "feedback": "; ".join(feedback_parts)
    }