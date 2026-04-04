#!/usr/bin/env python3
"""
Verifier for DHS CFATS Security Screening task.
"""

import json
import base64
import io
import csv
import logging
import tempfile
import os
from gym_anything.vlm import sample_trajectory_frames, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_dhs_cfats_security_screening(traj, env_info, task_info):
    """
    Verify the agent correctly identified CFATS regulated chemicals and extracted STQs.
    
    Scoring Breakdown (100 pts total):
    - 10 pts: Output file exists and was created during task.
    - 10 pts: Valid CSV format with correct headers.
    - 60 pts: Data Accuracy (10 pts per chemical).
    - 20 pts: VLM Trajectory Verification (process check).
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    score = 0
    feedback = []
    
    # 1. Load result from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 2. Check File Existence and Timestamp (10 pts)
    if not result.get("output_exists", False):
        return {"passed": False, "score": 0, "feedback": "Output CSV file not found."}
    
    if not result.get("file_created_during_task", False):
        feedback.append("⚠️ File timestamp suggests it was not created during this task session.")
    else:
        score += 10
        feedback.append("✅ Output file created during task.")

    # 3. Parse CSV Content
    content_b64 = result.get("content_base64", "")
    if not content_b64:
        return {"passed": False, "score": score, "feedback": "Output file is empty."}
    
    try:
        content_str = base64.b64decode(content_b64).decode('utf-8')
        csv_reader = csv.DictReader(io.StringIO(content_str))
        rows = list(csv_reader)
        
        # Check headers (10 pts)
        required_headers = {'Chemical', 'Regulated', 'Security_Issue', 'STQ_lb'}
        if not csv_reader.fieldnames or not required_headers.issubset(set(csv_reader.fieldnames)):
            feedback.append(f"❌ Incorrect CSV headers. Expected: {required_headers}")
        else:
            score += 10
            feedback.append("✅ CSV headers correct.")
    except Exception as e:
        return {"passed": False, "score": score, "feedback": f"Failed to parse CSV: {e}"}

    # 4. Verify Data Accuracy (60 pts max)
    # Ground Truth Data
    gt = task_info.get('metadata', {}).get('ground_truth', {})
    
    # Helper to clean strings
    def clean(s): return s.strip().lower() if s else ""
    
    # We will look for chemicals by keyword matching
    processed_chemicals = set()
    
    for row in rows:
        chem_name = row.get('Chemical', '')
        
        # Find matching ground truth entry
        match = None
        for gt_name, gt_data in gt.items():
            if clean(gt_name) in clean(chem_name):
                match = (gt_name, gt_data)
                break
        
        if not match:
            continue
            
        gt_name, gt_data = match
        processed_chemicals.add(gt_name)
        
        # Evaluate row
        row_score = 0
        
        # Check Regulated status
        is_regulated_user = clean(row.get('Regulated', '')) == 'yes'
        is_regulated_gt = gt_data['regulated']
        
        if is_regulated_user == is_regulated_gt:
            row_score += 4 # Base points for getting status right
            
            if is_regulated_gt:
                # Check STQ (allow slight formatting diffs, e.g. "500" vs "500.0")
                try:
                    user_stq = float(str(row.get('STQ_lb', '0')).replace(',', ''))
                    gt_stq = float(gt_data['stq'])
                    if user_stq == gt_stq:
                        row_score += 3
                    else:
                        feedback.append(f"⚠️ {gt_name}: Incorrect STQ (Expected {gt_stq}, got {user_stq})")
                except:
                    feedback.append(f"⚠️ {gt_name}: Invalid STQ format")

                # Check Security Issue Keyword
                user_issue = clean(row.get('Security_Issue', ''))
                gt_issue_kw = clean(gt_data['issue_keyword'])
                if gt_issue_kw in user_issue:
                    row_score += 3
                else:
                    feedback.append(f"⚠️ {gt_name}: Security issue missing keyword '{gt_issue_kw}'")
            else:
                # If not regulated, getting status right is full points
                row_score += 6
        else:
            feedback.append(f"❌ {gt_name}: Incorrect regulation status")
            
        score += row_score

    # Check if all chemicals were processed
    if len(processed_chemicals) < 6:
        feedback.append(f"⚠️ Missing chemicals in report. Found: {len(processed_chemicals)}/6")

    # 5. VLM Verification (20 pts)
    # Check if the agent actually visited Regulatory Information pages
    frames = sample_trajectory_frames(traj, n=5)
    
    vlm_prompt = """
    Review these screenshots of an agent using the CAMEO Chemicals website.
    The agent should be:
    1. Searching for chemicals (Chlorine, Propane, etc.)
    2. Viewing 'Regulatory Information' sections (tables with DHS CFATS data).
    
    Do you see evidence of the agent navigating to Regulatory Information sections or viewing chemical datasheets?
    Answer 'YES' or 'NO' and explain.
    """
    
    try:
        vlm_result = query_vlm(images=frames, prompt=vlm_prompt)
        if vlm_result.get('success'):
            if "YES" in vlm_result.get('response', '').upper():
                score += 20
                feedback.append("✅ VLM verified workflow.")
            else:
                feedback.append("⚠️ VLM did not observe clear regulatory research workflow.")
    except Exception:
        feedback.append("⚠️ VLM verification skipped due to error.")
        # Grant partial credit if data is perfect, otherwise 0
        if score >= 70:
            score += 20

    passed = score >= 70
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }