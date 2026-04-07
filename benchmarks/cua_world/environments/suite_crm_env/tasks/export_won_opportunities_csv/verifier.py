#!/usr/bin/env python3
"""
Verifier for export_won_opportunities_csv task.

Criteria:
1. Exact Path Used: Saved to /home/ga/Documents/closed_won_deals.csv (15 pts)
2. CSV Validity: It parses correctly (15 pts)
3. Target Inclusion: Contains all 8 Closed Won deals (30 pts)
4. Exclusion Logic: Does not contain the noise/prospecting deals (20 pts)
5. Process Verification: Apache log shows the export endpoint was hit + VLM confirms (20 pts)
"""

import json
import os
import tempfile
import csv
import logging

from gym_anything.vlm import sample_trajectory_frames, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_export(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    target_deals = metadata.get('target_deals', [])
    noise_deals = metadata.get('noise_deals', [])

    score = 0
    feedback_parts = []

    # 1. Retrieve metadata result
    result_json_path = tempfile.NamedTemporaryFile(delete=False, suffix='.json').name
    csv_export_path = tempfile.NamedTemporaryFile(delete=False, suffix='.csv').name
    log_export_path = tempfile.NamedTemporaryFile(delete=False, suffix='.txt').name

    try:
        copy_from_env("/tmp/task_result.json", result_json_path)
        with open(result_json_path, 'r') as f:
            result = json.load(f)
            
        exact_path_used = result.get('exact_path_used', False)
        file_found = result.get('file_found', False)
        
        # Scoring Path
        if exact_path_used:
            score += 15
            feedback_parts.append("File found at exact requested path.")
        elif file_found:
            score += 5
            feedback_parts.append("File downloaded but NOT moved to requested exact path.")
        else:
            return {"passed": False, "score": 0, "feedback": "No exported CSV file found."}

        # 2. Retrieve and parse CSV
        copy_from_env("/tmp/agent_export.csv", csv_export_path)
        
        file_content = ""
        with open(csv_export_path, 'r', encoding='utf-8', errors='replace') as f:
            file_content = f.read()

        if not file_content.strip():
            return {"passed": False, "score": score, "feedback": " | ".join(feedback_parts) + " | Exported CSV is empty."}
            
        csv_reader = csv.reader(file_content.splitlines())
        rows = list(csv_reader)
        
        if len(rows) > 0:
            score += 15
            feedback_parts.append("CSV parsed successfully.")
        else:
            return {"passed": False, "score": score, "feedback": " | ".join(feedback_parts) + " | CSV parsing failed."}

        # Flatten all row cells to easily search for deal names
        flattened_data = " ".join([cell for row in rows for cell in row])

        # 3. Check for Target Inclusion
        found_targets = 0
        for deal in target_deals:
            if deal in flattened_data:
                found_targets += 1
                
        target_ratio = found_targets / len(target_deals) if target_deals else 0
        target_score = int(30 * target_ratio)
        score += target_score
        feedback_parts.append(f"Found {found_targets}/{len(target_deals)} target deals.")

        # 4. Check for Exclusion Logic (Noise)
        found_noise = 0
        for deal in noise_deals:
            if deal in flattened_data:
                found_noise += 1
                
        if found_noise == 0:
            score += 20
            feedback_parts.append("Zero noise deals found (filtering applied perfectly).")
        else:
            penalty = found_noise * 2
            noise_score = max(0, 20 - penalty)
            score += noise_score
            feedback_parts.append(f"Found {found_noise} noise deals (imperfect filtering).")

        # 5. Process Verification (Apache Logs & VLM)
        process_score = 0
        log_content = ""
        try:
            copy_from_env("/tmp/export_logs.txt", log_export_path)
            with open(log_export_path, 'r') as f:
                log_content = f.read()
        except:
            pass

        # SuiteCRM Export uses `entryPoint=export`
        if "entryPoint=export" in log_content:
            process_score += 10
            feedback_parts.append("Apache logs confirm UI Export triggered.")
        else:
            feedback_parts.append("WARNING: Apache logs do not show standard SuiteCRM UI Export usage.")

        # VLM trajectory verification
        frames = sample_trajectory_frames(traj, n=4)
        if frames:
            prompt = (
                "You are auditing an agent using SuiteCRM. Did the agent navigate to the 'Opportunities' module, "
                "apply a filter for 'Closed Won', and select records for export? "
                "Respond with 'YES' if you see evidence of filtering or exporting in the CRM interface, otherwise 'NO'."
            )
            vlm_response = query_vlm(images=frames, prompt=prompt)
            if "YES" in vlm_response.get("response", "").upper():
                process_score += 10
                feedback_parts.append("VLM confirms CRM interface usage.")
            else:
                feedback_parts.append("VLM did not detect CRM filter/export usage.")
                
        score += process_score

        # Determine pass/fail
        passed = score >= 70 and exact_path_used and (found_targets == len(target_deals)) and (found_noise == 0)

        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }

    finally:
        for p in [result_json_path, csv_export_path, log_export_path]:
            if os.path.exists(p):
                os.unlink(p)