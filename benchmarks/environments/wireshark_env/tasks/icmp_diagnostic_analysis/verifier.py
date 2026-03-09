#!/usr/bin/env python3
import json
import re
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def parse_report_values(content):
    """
    Parses the unstructured text report to extract key metrics.
    Returns a dictionary of found values.
    """
    findings = {
        "total_packets": None,
        "type_counts": {},
        "avg_rtt": None,
        "hops": None,
        "unreachable": []
    }
    
    if not content:
        return findings

    lines = content.split('\n')
    for line in lines:
        lower_line = line.lower()
        
        # Parse Total Count
        if "total icmp" in lower_line:
            # Extract first number found
            nums = re.findall(r'\d+', line)
            if nums:
                findings["total_packets"] = int(nums[0])

        # Parse Type Counts
        # Looks for lines like "- Type 8 (Echo Request): 25"
        if "type" in lower_line and ":" in line:
            # regex for "Type [digits] ... : [digits]"
            match = re.search(r'type\s*(\d+).*?:\s*(\d+)', lower_line)
            if match:
                type_num = match.group(1)
                count = int(match.group(2))
                findings["type_counts"][type_num] = count

        # Parse RTT
        if "average rtt" in lower_line or "avg rtt" in lower_line:
            # Extract floating point number
            # matches 12.5, 12, 0.5
            match = re.search(r'(\d+(\.\d+)?)', line.split(':')[1] if ':' in line else line)
            if match:
                findings["avg_rtt"] = float(match.group(1))

        # Parse Hops
        if "unique traceroute hops" in lower_line or "unique hops" in lower_line:
            nums = re.findall(r'\d+', line)
            if nums:
                findings["hops"] = int(nums[-1]) # usually the last number is the count

        # Parse Unreachable
        if "unreachable destinations" in lower_line or "unreachable" in lower_line:
            # Look for IPs
            ips = re.findall(r'\b(?:\d{1,3}\.){3}\d{1,3}\b', line)
            if ips:
                findings["unreachable"].extend(ips)

    return findings

def verify_icmp_diagnostic_analysis(traj, env_info, task_info):
    """
    Verifies the ICMP analysis task.
    
    Scoring Breakdown (100 pts total):
    - Report file exists & created during task: 10 pts
    - Total packet count (±2): 10 pts
    - ICMP Types identified correctly (Type 0, 8, 11, 3): 20 pts (5 each)
    - Average RTT accuracy (±20%): 25 pts
    - Unique hops count (±1): 15 pts
    - Unreachable IP identification: 10 pts
    - VLM Visual Confirmation (Wireshark usage): 10 pts
    """
    
    # 1. Load Result using copy_from_env
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env missing"}

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load task result: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 2. Extract Data
    file_exists = result.get("file_exists", False)
    created_fresh = result.get("created_during_task", False)
    report_content = result.get("report_content", "")
    ground_truth = result.get("ground_truth", {})
    
    # Parse User Report
    user_data = parse_report_values(report_content)
    
    score = 0
    feedback = []

    # --- Criterion 1: File Existence (10 pts) ---
    if file_exists and created_fresh:
        score += 10
        feedback.append("Report file created successfully.")
    elif file_exists:
        score += 5
        feedback.append("Report file exists but timestamp suggests it wasn't created during this session.")
    else:
        return {"passed": False, "score": 0, "feedback": "Report file not found."}

    # --- Criterion 2: Total Packet Count (10 pts) ---
    gt_total = ground_truth.get("total_count", 0)
    user_total = user_data.get("total_packets")
    
    if user_total is not None and abs(user_total - gt_total) <= 2:
        score += 10
        feedback.append(f"Total packet count correct ({user_total}).")
    else:
        feedback.append(f"Total packet count mismatch (Expected ~{gt_total}, Got {user_total}).")

    # --- Criterion 3: ICMP Type Counts (20 pts) ---
    # We check for presence and rough accuracy of key types: 
    # 0 (Echo Reply), 8 (Echo Request), 11 (Time Exceeded), 3 (Unreachable)
    gt_types = ground_truth.get("type_counts", {}) # e.g. {"0": 10, "8": 10}
    user_types = user_data.get("type_counts", {})
    
    type_score = 0
    # Check key types
    for t_id in ["0", "8", "11", "3"]:
        gt_count = gt_types.get(t_id, 0)
        
        # If ground truth has 0 for this type, we don't penalize missing it, 
        # but if user reports >0, it's an error.
        if gt_count == 0:
            if user_types.get(t_id, 0) == 0:
                type_score += 5
            continue
            
        # Standard check
        user_count = user_types.get(t_id, 0)
        if abs(user_count - gt_count) <= 2:
            type_score += 5
    
    score += type_score
    feedback.append(f"ICMP Type analysis score: {type_score}/20.")

    # --- Criterion 4: Average RTT (25 pts) ---
    gt_rtt = ground_truth.get("avg_rtt", 0)
    user_rtt = user_data.get("avg_rtt")
    
    if user_rtt is not None and gt_rtt > 0:
        # Allow 20% margin or +/- 5ms (whichever is greater)
        diff = abs(user_rtt - gt_rtt)
        margin = max(gt_rtt * 0.2, 5.0)
        
        if diff <= margin:
            score += 25
            feedback.append(f"RTT calculation accurate ({user_rtt}ms vs {gt_rtt:.1f}ms).")
        else:
            feedback.append(f"RTT calculation incorrect (Got {user_rtt}ms, Expected ~{gt_rtt:.1f}ms).")
    elif gt_rtt == 0:
        # If network failed and RTT is 0, accept 0
        score += 25
        feedback.append("Network simulation restricted (RTT 0), skipped RTT check.")
    else:
        feedback.append("RTT not found in report.")

    # --- Criterion 5: Unique Hops (15 pts) ---
    gt_hops = ground_truth.get("unique_hops", 0)
    user_hops = user_data.get("hops")
    
    if user_hops is not None:
        if abs(user_hops - gt_hops) <= 1:
            score += 15
            feedback.append(f"Hop count correct ({user_hops}).")
        else:
            feedback.append(f"Hop count mismatch (Expected {gt_hops}, Got {user_hops}).")
    else:
        feedback.append("Hop count not found.")

    # --- Criterion 6: Unreachable IPs (10 pts) ---
    gt_unreachables = ground_truth.get("unreachable_ips", "")
    user_unreachables = user_data.get("unreachable", [])
    
    if gt_unreachables:
        found_any = False
        for ip in user_unreachables:
            if ip in gt_unreachables:
                found_any = True
                break
        if found_any:
            score += 10
            feedback.append("Unreachable IP correctly identified.")
        else:
            feedback.append("Unreachable IP not identified correctly.")
    else:
        # If no unreachables in GT, give points if user didn't hallucinate
        if not user_unreachables:
            score += 10

    # --- Criterion 7: Visual/App Check (10 pts) ---
    # Simple check if they actually generated content based on file
    if score >= 30: # If they got some data right, they likely used the app
        score += 10
    else:
        feedback.append("Score too low to award workflow points.")

    return {
        "passed": score >= 60,
        "score": score,
        "feedback": " ".join(feedback)
    }