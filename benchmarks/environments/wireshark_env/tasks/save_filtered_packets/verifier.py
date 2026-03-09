#!/usr/bin/env python3
"""
Verifier for save_filtered_packets task.
Checks if the user correctly filtered for TCP SYN packets and exported them.
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_save_filtered_packets(traj, env_info, task_info):
    """
    Verify the Wireshark packet filtering and export task.
    
    Scoring Criteria:
    1. File Exists & Valid (15 pts)
    2. Created After Task Start (10 pts)
    3. Is Proper Subset of original (15 pts)
    4. Contains SYN Packets (20 pts)
    5. All Packets Match Filter (25 pts)
    6. Correct Total Count (15 pts)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Copy result file from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # Extract data
    file_exists = result.get('file_exists', False)
    file_path = result.get('file_path', '')
    file_mtime = result.get('file_mtime', 0)
    task_start = result.get('task_start', 0)
    
    output_count = result.get('output_packet_count', 0)
    syn_count = result.get('syn_packet_count', 0)
    non_syn_count = result.get('non_syn_packet_count', 0)
    
    expected_syn = result.get('expected_syn_count', 0)
    original_total = result.get('original_total_count', 0)
    
    # --- Criterion 1: File Exists & Valid (15 pts) ---
    if file_exists and output_count > 0:
        score += 15
        feedback_parts.append(f"Output file found: {os.path.basename(file_path)}")
    else:
        feedback_parts.append("Output file not found or empty")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}
        
    # --- Criterion 2: Created After Task Start (10 pts) ---
    # Allow 5 second buffer for clock skew
    if file_mtime >= (task_start - 5):
        score += 10
        feedback_parts.append("File created during task")
    else:
        feedback_parts.append("File timestamp predates task start")
        
    # --- Criterion 3: Is Proper Subset (15 pts) ---
    if output_count < original_total:
        score += 15
        feedback_parts.append("File is a filtered subset")
    elif output_count == original_total:
        feedback_parts.append("File contains ALL packets (filtering likely failed)")
    else:
        feedback_parts.append("File larger than original (unexpected)")
        
    # --- Criterion 4: Contains SYN Packets (20 pts) ---
    if syn_count > 0:
        score += 20
        feedback_parts.append(f"Contains {syn_count} SYN packets")
    else:
        feedback_parts.append("No SYN packets found in output")
        
    # --- Criterion 5: All Packets Match Filter (25 pts) ---
    if non_syn_count == 0:
        score += 25
        feedback_parts.append("Clean filter: 100% of packets are SYN-only")
    else:
        # Partial credit logic
        match_ratio = syn_count / output_count if output_count > 0 else 0
        if match_ratio > 0.9:
            score += 15
            feedback_parts.append(f"Filter mostly correct ({int(match_ratio*100)}% match)")
        else:
            feedback_parts.append(f"Poor filtering: {non_syn_count} incorrect packets included")
            
    # --- Criterion 6: Correct Total Count (15 pts) ---
    # Tolerance of +/- 2 packets
    diff = abs(output_count - expected_syn)
    if diff <= 2:
        score += 15
        feedback_parts.append(f"Packet count matches expected ({output_count})")
    elif diff <= 5:
        score += 8
        feedback_parts.append(f"Packet count close ({output_count} vs {expected_syn})")
    else:
        feedback_parts.append(f"Count mismatch ({output_count} vs {expected_syn})")
        
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }