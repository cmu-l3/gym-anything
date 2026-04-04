#!/usr/bin/env python3
"""
Verifier for DHCP Lease Forensics Task.
"""

import json
import base64
import re
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_dhcp_lease_forensics(traj, env_info, task_info):
    """
    Verify the DHCP analysis report against ground truth.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Framework error: copy_from_env missing"}

    # 1. Fetch Result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read task result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []
    
    # 2. Check File Existence & Creation
    if not result.get("report_exists", False):
        return {"passed": False, "score": 0, "feedback": "Report file not found."}
    
    if not result.get("file_created_during_task", False):
        feedback.append("Warning: Report file timestamp suggests it wasn't created during this session.")
        # We allow it but maybe penalize or fail if strict strict.
        # For now, give partial credit for existence.
        score += 5
    else:
        score += 10
        feedback.append("Report file created successfully.")

    # 3. Decode Report Content
    try:
        content_b64 = result.get("report_content_b64", "")
        report_text = base64.b64decode(content_b64).decode('utf-8', errors='ignore')
        # Normalize text for searching (lowercase, simplify delimiters)
        report_norm = report_text.lower().replace(":", "").replace("-", "")
    except Exception:
        return {"passed": False, "score": score, "feedback": "Failed to decode report content."}

    if len(report_text) < 50:
        return {"passed": False, "score": score, "feedback": "Report file is too short/empty."}

    # 4. Compare against Ground Truth
    gt = result.get("ground_truth", {})
    
    # helper to check fuzzy presence
    def check_presence(gt_csv, item_name, points_total):
        if not gt_csv: 
            return 0
        
        items = [x.strip() for x in gt_csv.split(',')]
        if not items: 
            return 0
            
        found_count = 0
        for item in items:
            # Normalize item for comparison
            if "mac" in item_name or "id" in item_name:
                # Remove colons, dashes, lowercase
                needle = item.lower().replace(":", "").replace("-", "")
                # remove 0x prefix if hex
                needle = needle.replace("0x", "")
            else:
                needle = item.lower()
            
            if needle in report_norm:
                found_count += 1
        
        if len(items) == 0: return points_total
        
        ratio = found_count / len(items)
        pts = int(ratio * points_total)
        
        if found_count == len(items):
            feedback.append(f"All {item_name} found ({found_count}/{len(items)}).")
        elif found_count > 0:
            feedback.append(f"Some {item_name} missing ({found_count}/{len(items)} found).")
        else:
            feedback.append(f"No {item_name} found in report.")
            
        return pts

    # SCORING BREAKDOWN
    
    # Packet Count (10 pts)
    # Check if the number appears in the text
    gt_total = gt.get("total_packets", "0").strip()
    if gt_total in report_text:
        score += 10
        feedback.append(f"Total packet count ({gt_total}) matched.")
    else:
        feedback.append(f"Total packet count ({gt_total}) not found.")

    # Transaction IDs (15 pts)
    score += check_presence(gt.get("transaction_ids"), "transaction IDs", 15)

    # Client MACs (20 pts)
    score += check_presence(gt.get("client_macs"), "Client MACs", 20)

    # Assigned IPs (20 pts)
    score += check_presence(gt.get("assigned_ips"), "Assigned IPs", 20)

    # Server IPs (10 pts)
    score += check_presence(gt.get("server_ips"), "Server IPs", 10)

    # Options (15 pts shared)
    opt_pts = 0
    opt_pts += check_presence(gt.get("subnets"), "Subnet Masks", 5)
    opt_pts += check_presence(gt.get("routers"), "Gateways", 5)
    opt_pts += check_presence(gt.get("dns_servers"), "DNS Servers", 5)
    score += opt_pts

    # 5. Structure Check (Simple Heuristics)
    if "transaction" in report_text.lower():
        # implicit points mostly covered above, but good for format
        pass
        
    passed = score >= 60
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }