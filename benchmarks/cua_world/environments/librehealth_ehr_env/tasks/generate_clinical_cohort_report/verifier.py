#!/usr/bin/env python3
import json
import os
import tempfile
import csv
from gym_anything.vlm import sample_trajectory_frames, query_vlm

def verify_cohort_report(traj, env_info, task_info):
    """
    Verifies that the agent generated a CSV report containing the correct patient cohort.
    
    Criteria:
    1. File exists and was created during the task.
    2. File contains the names of the 3 target patients (injected with the diagnosis).
    3. File does NOT contain the names of the 2 control patients.
    4. VLM verification of the workflow.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Define paths
    container_result_path = "/tmp/task_result.json"
    container_output_path = "/home/ga/Documents/cohort_report.csv"
    container_gt_targets = "/var/lib/app/ground_truth/expected_targets.txt"
    container_gt_controls = "/var/lib/app/ground_truth/expected_controls.txt"

    # Temporary directory for local files
    temp_dir = tempfile.mkdtemp()
    local_result = os.path.join(temp_dir, "result.json")
    local_csv = os.path.join(temp_dir, "report.csv")
    local_targets = os.path.join(temp_dir, "targets.txt")
    local_controls = os.path.join(temp_dir, "controls.txt")

    try:
        # --- 1. Load Task Result Metadata ---
        try:
            copy_from_env(container_result_path, local_result)
            with open(local_result, 'r') as f:
                result_data = json.load(f)
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task result: {str(e)}"}

        if not result_data.get("output_exists", False):
            return {"passed": False, "score": 0, "feedback": "Cohort report CSV file not found at ~/Documents/cohort_report.csv"}
        
        if not result_data.get("file_created_during_task", False):
            return {"passed": False, "score": 0, "feedback": "Report file exists but was not created during this task session (stale data)."}

        # --- 2. Load Content Files ---
        try:
            copy_from_env(container_output_path, local_csv)
            copy_from_env(container_gt_targets, local_targets)
            copy_from_env(container_gt_controls, local_controls)
        except Exception as e:
            return {"passed": False, "score": 20, "feedback": f"File exists but failed to copy content for verification: {str(e)}"}

        # Read Ground Truth
        with open(local_targets, 'r') as f:
            target_names = [line.strip().lower() for line in f if line.strip()]
        
        with open(local_controls, 'r') as f:
            control_names = [line.strip().lower() for line in f if line.strip()]

        # Read Agent Output
        # flexible reading: read as raw text to handle various CSV formats or just list formats
        with open(local_csv, 'r', errors='ignore') as f:
            csv_content = f.read().lower()

        # --- 3. Score Content ---
        score = 20 # Base score for file existence
        feedback = []
        
        # Check Targets (True Positives)
        targets_found = 0
        for name in target_names:
            if name in csv_content:
                targets_found += 1
            else:
                feedback.append(f"Missing target patient: {name}")
        
        target_score = (targets_found / len(target_names)) * 40 if target_names else 40
        score += target_score
        feedback.append(f"Found {targets_found}/{len(target_names)} target patients.")

        # Check Controls (False Positives)
        controls_found = 0
        for name in control_names:
            if name in csv_content:
                controls_found += 1
                feedback.append(f"Incorrectly included control patient: {name}")
        
        # 20 points for excluding controls. Lose 10 pts per error.
        control_penalty = controls_found * 10
        control_score = max(0, 20 - control_penalty)
        score += control_score

        # --- 4. VLM Verification ---
        # Verify they actually used the interface
        frames = sample_trajectory_frames(traj, n=4)
        vlm_score = 0
        
        if frames:
            prompt = """
            Review these screenshots of an agent using LibreHealth EHR.
            Did the agent navigate to a 'Reports', 'Patient List', or 'Flow Board' section?
            Is there evidence of searching or filtering by 'Diagnosis', 'Problem', or 'Chronic Fatigue'?
            
            Answer YES or NO and explain briefly.
            """
            vlm_res = query_vlm(images=frames, prompt=prompt)
            if vlm_res and vlm_res.get("success"):
                explanation = vlm_res.get("parsed", {}).get("answer", "").lower()
                # Basic heuristic check on VLM output
                if "yes" in str(vlm_res).lower():
                    vlm_score = 20
                    feedback.append("VLM confirms reporting workflow usage.")
                else:
                    feedback.append("VLM did not clearly observe reporting workflow.")
            else:
                # If VLM fails, give benefit of doubt if output is perfect
                if targets_found == len(target_names) and controls_found == 0:
                    vlm_score = 20
        
        score += vlm_score

        # Final pass determination
        # Must find ALL targets and exclude ALL controls to pass
        passed = (targets_found == len(target_names)) and (controls_found == 0) and (score >= 80)
        
        return {
            "passed": passed,
            "score": int(score),
            "feedback": " ".join(feedback)
        }

    finally:
        # Cleanup
        import shutil
        shutil.rmtree(temp_dir, ignore_errors=True)