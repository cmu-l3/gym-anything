#!/usr/bin/env python3
"""
Verifier for MAC OUI Inventory task.
"""

import json
import os
import re
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def normalize_mac(mac):
    """Normalize MAC address to lowercase, colon-separated."""
    # Remove common delimiters
    clean = re.sub(r'[^a-fA-F0-9]', '', mac)
    if len(clean) != 12:
        return None
    # Insert colons
    return ':'.join(clean[i:i+2] for i in range(0, 12, 2)).lower()

def verify_mac_oui_inventory(traj, env_info, task_info):
    """
    Verify the agent's network inventory report.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Retrieve files from environment
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    temp_report = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
    temp_gt = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    
    try:
        # Get result metadata
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            res_meta = json.load(f)
            
        # Check basic file existence/freshness (Anti-gaming)
        if not res_meta.get("report_exists", False):
            return {"passed": False, "score": 0, "feedback": "Report file not found."}
        
        if not res_meta.get("report_created_during_task", False):
            return {"passed": False, "score": 0, "feedback": "Report file was not created/modified during the task."}
            
        if res_meta.get("report_size", 0) < 50:
            return {"passed": False, "score": 0, "feedback": "Report file is too small/empty."}

        # Get the actual report content
        copy_from_env(res_meta["report_path"], temp_report.name)
        with open(temp_report.name, 'r', errors='ignore') as f:
            report_content = f.read()
            
        # Get ground truth
        copy_from_env(res_meta["ground_truth_path"], temp_gt.name)
        with open(temp_gt.name, 'r') as f:
            ground_truth = json.load(f)
            
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Error retrieving verification data: {str(e)}"}
    finally:
        # Cleanup
        for fpath in [temp_result.name, temp_report.name, temp_gt.name]:
            if os.path.exists(fpath):
                os.unlink(fpath)

    # 2. Parse User Report
    # We look for MAC addresses and associated data in the text
    report_lower = report_content.lower()
    
    # Extract total unique count claim
    total_match = re.search(r'total\s+(?:unique\s+)?mac.*?(\d+)', report_lower)
    user_total_count = int(total_match.group(1)) if total_match else -1
    
    # Extract most active sender claim
    # Looking for: "Most active sender: XX:XX:XX:XX:XX:XX"
    active_match = re.search(r'most\s+active.*?([0-9a-f]{2}(?:[:-][0-9a-f]{2}){5})', report_lower)
    user_active_mac = normalize_mac(active_match.group(1)) if active_match else None
    
    # Find all MACs mentioned in report
    # We use a set to check presence
    user_macs_found = set()
    # Regex for standard MAC formats
    mac_regex = re.compile(r'([0-9a-f]{2}(?:[:-][0-9a-f]{2}){5})', re.IGNORECASE)
    for m in mac_regex.findall(report_content):
        norm = normalize_mac(m)
        if norm:
            user_macs_found.add(norm)
            
    # 3. Score Calculation
    score = 0
    feedback = []
    
    gt_total = ground_truth["total_unique_macs"]
    gt_macs = ground_truth["mac_details"]
    gt_active = ground_truth["most_active_sender"]
    gt_active_count = ground_truth["most_active_sent_count"]
    
    # Criterion 1: Total Count (15 pts)
    if user_total_count == gt_total:
        score += 15
        feedback.append(f"Correct total MAC count ({gt_total})")
    elif abs(user_total_count - gt_total) <= 1:
        score += 10
        feedback.append(f"Total MAC count close ({user_total_count} vs {gt_total})")
    else:
        feedback.append(f"Total MAC count incorrect ({user_total_count} vs {gt_total})")
        
    # Criterion 2: Most Active Sender (15 pts)
    if user_active_mac == gt_active:
        score += 15
        feedback.append("Correct most active sender identified")
    elif user_active_mac:
        feedback.append(f"Wrong active sender identified ({user_active_mac} vs {gt_active})")
    else:
        feedback.append("Could not identify most active sender in report")
        
    # Criterion 3: Recall - Found all MACs (30 pts)
    # We check if GT macs are present in the user report
    found_count = 0
    for mac in gt_macs:
        if mac in user_macs_found:
            found_count += 1
            
    recall_pct = found_count / gt_total if gt_total > 0 else 0
    score += int(30 * recall_pct)
    feedback.append(f"Found {found_count}/{gt_total} MAC addresses")
    
    # Criterion 4: Vendor & Count Accuracy (30 pts)
    # We sample a few MACs to check if details are somewhat correct
    # Parsing structured data from free text is hard, so we do simpler string presence checks
    # around the MAC address position
    details_score = 0
    checked_macs = 0
    
    for mac, info in gt_macs.items():
        if mac not in user_macs_found:
            continue
            
        checked_macs += 1
        # Locate MAC in text
        pos = report_lower.find(mac)
        if pos == -1: continue
        
        # Look at a window of text around the MAC
        window = report_lower[pos:pos+300]
        
        # Check Vendor (fuzzy)
        gt_vendor = info["vendor"].lower()
        if gt_vendor and gt_vendor != "unknown":
            # Check if significant part of vendor name is present
            # e.g., "Apple" from "Apple_xx:xx:xx"
            core_vendor = gt_vendor.split('_')[0]
            if len(core_vendor) > 3 and core_vendor in window:
                details_score += 1
        else:
            # If unknown, giving point freely or checking for "unknown"
            details_score += 1
            
        # Check Counts (fuzzy)
        # We look for the numbers in the window
        gt_src = info["src_count"]
        gt_dst = info["dst_count"]
        
        # Find all numbers in window
        nums = [int(n) for n in re.findall(r'\d+', window)]
        
        # Flexible matching: if exact counts appear near the MAC
        if gt_src in nums or (gt_src > 0 and any(abs(n - gt_src) <= 2 for n in nums)):
            details_score += 1
        if gt_dst in nums or (gt_dst > 0 and any(abs(n - gt_dst) <= 2 for n in nums)):
            details_score += 1
            
    # Max possible details points: checked_macs * 3
    # Normalize to 30 pts
    if checked_macs > 0:
        details_normalized = (details_score / (checked_macs * 3)) * 30
        score += int(details_normalized)
        feedback.append(f"Detail accuracy score: {int(details_normalized)}/30")
    
    # Criterion 5: File existence/creation (10 pts)
    # Already checked initially, awarding points for getting this far
    score += 10
    
    return {
        "passed": score >= 60,
        "score": score,
        "feedback": "; ".join(feedback)
    }