#!/usr/bin/env python3
"""
Verifier for compile_audit_report task.
Compares the user-generated JSON report against a ground truth generated at the end of the task.
"""

import json
import os
import tempfile
import logging
from datetime import datetime

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_compile_audit_report(traj, env_info, task_info):
    """
    Verify the compliance audit report.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Temp files for extraction
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json').name
    temp_user_report = tempfile.NamedTemporaryFile(delete=False, suffix='.json').name
    temp_ground_truth = tempfile.NamedTemporaryFile(delete=False, suffix='.json').name

    try:
        # 1. Get the Task Result Metadata
        copy_from_env("/tmp/task_result.json", temp_result)
        with open(temp_result, 'r') as f:
            result_meta = json.load(f)

        # Check basics
        if not result_meta.get("report_exists", False):
            return {
                "passed": False, 
                "score": 0, 
                "feedback": "❌ Report file not found at ~/Documents/compliance_report.json"
            }

        if not result_meta.get("report_valid_json", False):
            return {
                "passed": False, 
                "score": 10, 
                "feedback": "❌ Report file exists but contains invalid JSON"
            }

        # 2. Get the User Report and Ground Truth
        user_report_path = result_meta.get("user_report_path")
        ground_truth_path = result_meta.get("ground_truth_path")

        copy_from_env(user_report_path, temp_user_report)
        copy_from_env(ground_truth_path, temp_ground_truth)

        with open(temp_user_report, 'r') as f:
            user_data = json.load(f)
        
        with open(temp_ground_truth, 'r') as f:
            ground_truth = json.load(f)

        # Handle case where ground truth generation failed inside container
        if "error" in ground_truth:
            return {
                "passed": False,
                "score": 0,
                "feedback": f"System Error: Failed to generate ground truth: {ground_truth['error']}"
            }

        # 3. Scoring Logic
        score = 0
        feedback = []

        # Criterion: File Validity (already checked existence/json validity)
        score += 10
        feedback.append("✅ File exists and is valid JSON")

        # Criterion: Required Keys
        required_keys = [
            "system_name", "system_version", "server_count", "total_cameras", 
            "cameras", "total_users", "users", "total_layouts", 
            "total_event_rules", "report_generated_at", "compliance_summary"
        ]
        missing_keys = [k for k in required_keys if k not in user_data]
        
        if not missing_keys:
            score += 10
            feedback.append("✅ All top-level keys present")
        else:
            feedback.append(f"❌ Missing keys: {', '.join(missing_keys)}")

        # Helper for loose string comparison
        def loose_match(a, b):
            return str(a).strip().lower() == str(b).strip().lower()

        # Criterion: System Info
        if loose_match(user_data.get("system_name"), ground_truth.get("system_name")):
            score += 8
        else:
            feedback.append(f"⚠️ System Name mismatch: Expected '{ground_truth.get('system_name')}'")

        if loose_match(user_data.get("system_version"), ground_truth.get("system_version")):
            score += 7
        else:
            # Allow partial match for version (e.g. "5.1" vs "5.1.5.39242")
            uv = str(user_data.get("system_version", ""))
            gv = str(ground_truth.get("system_version", ""))
            if uv and gv and (uv in gv or gv in uv):
                score += 7
            else:
                feedback.append(f"⚠️ Version mismatch: Expected '{gv}'")

        # Criterion: Counts (Exact match preferred)
        counts_to_check = [
            ("server_count", 5),
            ("total_cameras", 10),
            ("total_users", 8),
            ("total_layouts", 5),
            ("total_event_rules", 5)
        ]

        for key, pts in counts_to_check:
            uv = user_data.get(key)
            gv = ground_truth.get(key)
            if uv == gv:
                score += pts
            else:
                feedback.append(f"❌ {key} mismatch: User {uv} != Actual {gv}")

        # Criterion: Camera List Accuracy
        # Check if IDs in user list exist in ground truth
        user_cams = user_data.get("cameras", [])
        gt_cam_ids = {c["id"] for c in ground_truth.get("cameras", [])}
        
        if isinstance(user_cams, list) and user_cams:
            matched_cams = sum(1 for c in user_cams if c.get("id") in gt_cam_ids)
            if len(user_cams) > 0 and len(gt_cam_ids) > 0:
                accuracy = matched_cams / len(gt_cam_ids) # Recall
                if accuracy >= 0.8:
                    score += 10
                elif accuracy > 0:
                    score += 5
                    feedback.append(f"⚠️ Camera list incomplete ({matched_cams}/{len(gt_cam_ids)})")
                else:
                    feedback.append("❌ Camera list IDs do not match system")
            elif len(gt_cam_ids) == 0 and len(user_cams) == 0:
                 score += 10 # Both empty
        else:
            feedback.append("❌ Camera list empty or invalid")

        # Criterion: User List Accuracy
        user_users = user_data.get("users", [])
        gt_user_names = {u["name"].lower() for u in ground_truth.get("users", [])}
        
        if isinstance(user_users, list) and user_users:
            matched_users = sum(1 for u in user_users if u.get("name", "").lower() in gt_user_names)
            if len(user_users) > 0 and len(gt_user_names) > 0:
                accuracy = matched_users / len(gt_user_names)
                if accuracy >= 0.8:
                    score += 8
                elif accuracy > 0:
                    score += 4
                    feedback.append(f"⚠️ User list incomplete")
                else:
                    feedback.append("❌ User list names do not match system")
        else:
            feedback.append("❌ User list empty or invalid")

        # Criterion: Compliance Summary
        user_summary = user_data.get("compliance_summary", {})
        gt_summary = ground_truth.get("compliance_summary", {})
        
        # Allow +/- 1 tolerance for dynamic states
        c_online_ok = abs(user_summary.get("cameras_online", -99) - gt_summary.get("cameras_online", 0)) <= 1
        u_enabled_ok = abs(user_summary.get("users_enabled", -99) - gt_summary.get("users_enabled", 0)) <= 1
        
        if c_online_ok and u_enabled_ok:
            score += 10
        else:
            feedback.append(f"❌ Compliance summary incorrect. Actual: {gt_summary}")

        # Criterion: Timestamp Validity & Anti-gaming
        # Check if report time is after task start
        task_start = result_meta.get("task_start", 0)
        file_mtime = result_meta.get("report_mtime", 0)
        
        time_valid = False
        if file_mtime > task_start:
            # Also check the internal timestamp string
            ts_str = user_data.get("report_generated_at", "")
            try:
                # Basic ISO check (broad)
                if "T" in ts_str and len(ts_str) > 10:
                    score += 4
                    time_valid = True
            except:
                pass
        
        if not time_valid:
            feedback.append("⚠️ Timestamp invalid or file not created during task")

        # Criterion: Anti-gaming (Empty lists?)
        if len(user_cams) < 2 or len(user_users) < 2:
            score = min(score, 50) # Cap score if lists are suspiciously short
            feedback.append("⚠️ Data lists surprisingly short - possible gaming")

        return {
            "passed": score >= 60,
            "score": score,
            "feedback": " | ".join(feedback)
        }

    except Exception as e:
        logger.exception("Verification failed")
        return {"passed": False, "score": 0, "feedback": f"Verification error: {str(e)}"}
    finally:
        # Cleanup
        for f in [temp_result, temp_user_report, temp_ground_truth]:
            if os.path.exists(f):
                os.unlink(f)