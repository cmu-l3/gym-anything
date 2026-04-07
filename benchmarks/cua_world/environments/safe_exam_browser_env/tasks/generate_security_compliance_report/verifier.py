#!/usr/bin/env python3
import csv
import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_compliance_report(traj, env_info, task_info):
    """
    Verify the security compliance CSV report.
    Checks:
    1. Valid CSV formatting & header existence
    2. Number of configurations matches ground truth
    3. Exact accuracy of the Extracted EAV Boolean Settings
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    temp_gt = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    temp_csv = tempfile.NamedTemporaryFile(delete=False, suffix='.csv')
    
    try:
        # 1. Read task_result
        try:
            copy_from_env("/tmp/task_result.json", temp_result.name)
            with open(temp_result.name, 'r') as f:
                result = json.load(f)
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Failed to read task result metadata: {e}"}
            
        if not result.get('output_exists', False):
            return {"passed": False, "score": 0, "feedback": "compliance_report.csv not found in expected location"}
            
        if not result.get('file_created_during_task', False):
            return {"passed": False, "score": 0, "feedback": "Anti-gaming: File exists but was not created/modified during the task window"}

        # 2. Read ground truth
        try:
            copy_from_env("/tmp/ground_truth.json", temp_gt.name)
            with open(temp_gt.name, 'r') as f:
                ground_truth = json.load(f)
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Failed to load ground truth reference: {e}"}

        # 3. Read agent's CSV Report
        try:
            copy_from_env("/tmp/compliance_report.csv", temp_csv.name)
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Failed to copy CSV: {e}"}
        
        score = 10
        feedback_parts = ["File created"]
        
        try:
            with open(temp_csv.name, 'r', encoding='utf-8') as f:
                reader = csv.reader(f)
                rows = list(reader)
        except Exception as e:
            return {"passed": False, "score": score, "feedback": f"Failed to parse CSV: {e}"}
            
        if len(rows) < 2:
            return {"passed": False, "score": score, "feedback": "CSV is empty or missing headers"}
            
        headers = rows[0]
        if len(headers) < 3:
            feedback_parts.append("CSV does not have at least 3 columns")
        else:
            score += 10
            feedback_parts.append("Valid CSV Format")

        # Dynamically map columns based on header strings
        name_idx = -1
        vm_idx = -1
        ss_idx = -1
        
        for i, h in enumerate(headers):
            h_lower = h.lower()
            if 'name' in h_lower or 'config' in h_lower:
                name_idx = i
            elif 'virtual' in h_lower or 'vm' in h_lower:
                vm_idx = i
            elif 'screen' in h_lower or 'shar' in h_lower:
                ss_idx = i
                
        # Fallback indexes
        if name_idx == -1: name_idx = 0
        if vm_idx == -1: vm_idx = 1
        if ss_idx == -1: ss_idx = 2

        agent_data = {}
        for row in rows[1:]:
            if len(row) > max(name_idx, vm_idx, ss_idx):
                c_name = row[name_idx].strip()
                c_vm = row[vm_idx].strip().lower()
                c_ss = row[ss_idx].strip().lower()
                
                # Normalize boolean representation standard in SEB
                c_vm_bool = "true" if c_vm in ["true", "1", "yes", "y", "t"] else "false"
                c_ss_bool = "true" if c_ss in ["true", "1", "yes", "y", "t"] else "false"
                
                agent_data[c_name] = {
                    "vm": c_vm_bool,
                    "ss": c_ss_bool
                }

        configs_present = 0
        vm_correct = 0
        ss_correct = 0
        
        for gt_name, gt_vals in ground_truth.items():
            if gt_name in agent_data:
                configs_present += 1
                if agent_data[gt_name]['vm'] == str(gt_vals['allowVirtualMachine']).lower():
                    vm_correct += 1
                if agent_data[gt_name]['ss'] == str(gt_vals['allowScreenSharing']).lower():
                    ss_correct += 1

        total_gt = len(ground_truth)
        if total_gt == 0:
            return {"passed": False, "score": 0, "feedback": "Ground truth is unexpectedly empty."}
        
        # Scoring Criteria 
        if configs_present == total_gt:
            score += 20
            feedback_parts.append("All configurations present")
        else:
            score += int(20 * (configs_present / total_gt))
            feedback_parts.append(f"{configs_present}/{total_gt} configurations found")

        if vm_correct == total_gt:
            score += 30
            feedback_parts.append("VM settings 100% accurate")
        else:
            score += int(30 * (vm_correct / total_gt))
            feedback_parts.append(f"VM settings {vm_correct}/{total_gt} accurate")

        if ss_correct == total_gt:
            score += 30
            feedback_parts.append("Screen settings 100% accurate")
        else:
            score += int(30 * (ss_correct / total_gt))
            feedback_parts.append(f"Screen settings {ss_correct}/{total_gt} accurate")

        # Pass threshold (80 out of 100 max points -> demands full format, existence + at least 1 perfect column)
        passed = score >= 80

        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }

    finally:
        for p in [temp_result.name, temp_gt.name, temp_csv.name]:
            if os.path.exists(p):
                os.unlink(p)