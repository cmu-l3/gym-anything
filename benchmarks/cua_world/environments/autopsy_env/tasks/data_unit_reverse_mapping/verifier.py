#!/usr/bin/env python3
"""
Verifier for data_unit_reverse_mapping task.

Scoring System (100 points total, pass threshold = 68):
- 20 points: Output CSV exists, was created during task, and has correct header.
- 16 points per block (5 blocks total = 80 points):
    - 4 points: Correct allocation status
    - 6 points: Correct inode mapping
    - 6 points: Correct file path mapping
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_data_unit_reverse_mapping(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    result_file = metadata.get('result_file', '/tmp/task_result.json')
    gt_file = metadata.get('gt_file', '/tmp/data_unit_reverse_mapping_gt.json')

    score = 0
    feedback_parts = []
    
    # ---------------------------------------------------------
    # 1. Fetch Result and Ground Truth from VM
    # ---------------------------------------------------------
    try:
        tmp_res = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        copy_from_env(result_file, tmp_res.name)
        with open(tmp_res.name, 'r') as f:
            result = json.load(f)
        os.unlink(tmp_res.name)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read agent results: {e}"}

    try:
        tmp_gt = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        copy_from_env(gt_file, tmp_gt.name)
        with open(tmp_gt.name, 'r') as f:
            gt_data = json.load(f)
        os.unlink(tmp_gt.name)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read ground truth: {e}"}

    # ---------------------------------------------------------
    # 2. Basic Checks (File existence, Timestamp, Format)
    # ---------------------------------------------------------
    if not result.get("output_exists"):
        return {"passed": False, "score": 0, "feedback": "Output report CSV was not found."}
    
    if not result.get("file_created_during_task"):
        feedback_parts.append("Warning: Output file timestamp is older than task start.")
    else:
        feedback_parts.append("File created during session.")
        
    content = result.get("file_content", "").strip()
    if not content:
        return {"passed": False, "score": 0, "feedback": "Output report CSV is empty."}
        
    lines = [line.strip() for line in content.splitlines() if line.strip()]
    header = lines[0]
    
    # Determine delimiter
    delimiter = "|"
    if delimiter not in header and "," in header:
        delimiter = ","
        feedback_parts.append("Used comma delimiter instead of pipe (-2 pts)")
        format_score = 18
    elif header == "BLOCK_ID|BLOCK_ALLOCATED|INODE|FILE_PATH":
        feedback_parts.append("Header format perfect.")
        format_score = 20
    else:
        feedback_parts.append("Header mismatch or missing (-5 pts)")
        format_score = 15
        
    score += format_score

    # ---------------------------------------------------------
    # 3. Parse Agent CSV data
    # ---------------------------------------------------------
    agent_mappings = {}
    for line in lines[1:]:
        parts = line.split(delimiter)
        if len(parts) >= 1:
            block_id = parts[0].strip()
            agent_mappings[block_id] = {
                "allocated": parts[1].strip().upper() if len(parts) > 1 else "",
                "inode": parts[2].strip() if len(parts) > 2 else "",
                "path": parts[3].strip() if len(parts) > 3 else ""
            }

    # ---------------------------------------------------------
    # 4. Compare with Ground Truth
    # ---------------------------------------------------------
    blocks_scored = 0
    total_gt_blocks = len(gt_data)
    
    for block_id, gt_info in gt_data.items():
        if block_id not in agent_mappings:
            feedback_parts.append(f"Block {block_id} missing from report.")
            continue
            
        agent_info = agent_mappings[block_id]
        block_score = 0
        
        # A) Allocation Check (4 points)
        if agent_info["allocated"] == gt_info["allocated"]:
            block_score += 4
        else:
            feedback_parts.append(f"B{block_id} alloc mismatch (Exp:{gt_info['allocated']}, Got:{agent_info['allocated']})")
            
        # B) Inode Check (6 points)
        gt_inode_base = gt_info["inode"].split('-')[0] if gt_info["inode"] != "NONE" else "NONE"
        ag_inode = agent_info["inode"].upper()
        
        if gt_inode_base == "NONE" and ("NONE" in ag_inode or "N/A" in ag_inode or ag_inode == ""):
            block_score += 6
        elif gt_inode_base != "NONE" and gt_inode_base in ag_inode:
            block_score += 6
        else:
            feedback_parts.append(f"B{block_id} inode mismatch (Exp:{gt_inode_base}, Got:{ag_inode})")
            
        # C) Path Check (6 points)
        gt_path = gt_info["path"]
        ag_path = agent_info["path"].replace("\\", "/") # Normalize slashes
        
        if gt_path == "NONE":
            if "NONE" in ag_path.upper() or "UNKNOWN" in ag_path.upper() or ag_path == "" or "N/A" in ag_path.upper():
                block_score += 6
            else:
                feedback_parts.append(f"B{block_id} path mismatch (Exp:NONE, Got:{ag_path})")
        else:
            # GT path might be full path e.g., "dir1/dir2/file.txt"
            # As long as the agent includes the basename or full path correctly
            base_gt_name = gt_path.split('/')[-1]
            if base_gt_name.lower() in ag_path.lower():
                block_score += 6
            else:
                feedback_parts.append(f"B{block_id} path mismatch (Exp:{gt_path}, Got:{ag_path})")
                
        score += block_score
        blocks_scored += 1

    if blocks_scored < total_gt_blocks:
        feedback_parts.append(f"Only mapped {blocks_scored}/{total_gt_blocks} blocks.")

    # ---------------------------------------------------------
    # 5. Final Evaluation
    # ---------------------------------------------------------
    passed = score >= 68
    
    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback_parts)
    }