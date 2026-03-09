#!/usr/bin/env python3
"""
Verifier for configure_resource_quotas task.

Criteria:
1. acmecorp.test: 2048 MB Disk, 10 GB Bandwidth
2. greenleaf.test: 1024 MB Disk, 5 GB Bandwidth
3. craftworks.test: 512 MB Disk, 2 GB Bandwidth
4. Anti-gaming: Values must be distinct and modified from initial state.
"""

import json
import os
import tempfile
import logging
import re

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def parse_size_string(size_str):
    """
    Parses a size string like '2 GB', '2048 MB', '5368709120' into MB.
    Returns float MB or None if parsing fails/unlimited.
    """
    if not size_str or 'unlimited' in size_str.lower() or 'none' in size_str.lower():
        return None
    
    # Normalize
    s = size_str.strip().upper().replace(',', '')
    
    # Check for units
    if 'TB' in s:
        val = float(re.sub(r'[^0-9.]', '', s))
        return val * 1024 * 1024
    elif 'GB' in s:
        val = float(re.sub(r'[^0-9.]', '', s))
        return val * 1024
    elif 'MB' in s:
        val = float(re.sub(r'[^0-9.]', '', s))
        return val
    elif 'KB' in s:
        val = float(re.sub(r'[^0-9.]', '', s))
        return val / 1024
    elif 'BYTES' in s or re.match(r'^\d+$', s):
        # Assume bytes if just digits or explicitly 'bytes'
        val = float(re.sub(r'[^0-9.]', '', s))
        return val / (1024 * 1024)
    elif 'BLOCKS' in s:
        # Virtualmin sometimes uses 1KB blocks
        val = float(re.sub(r'[^0-9.]', '', s))
        return val / 1024
    
    return None

def verify_configure_resource_quotas(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load metadata targets
    metadata = task_info.get('metadata', {})
    targets = metadata.get('targets', {})
    
    # Retrieve result from container
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
    max_score = 100
    feedback_parts = []
    
    domains_result = result.get('domains', [])
    domain_map = {d['domain']: d for d in domains_result}
    
    # Scoring Breakdown:
    # 6 items to check (3 domains * 2 settings) = 15 points each = 90 points
    # 10 points for anti-gaming checks (distinct values, modified state)
    
    processed_values = [] # To check distinctness

    for target_domain, target_specs in targets.items():
        if target_domain not in domain_map:
            feedback_parts.append(f"{target_domain}: Not found")
            continue
            
        actual = domain_map[target_domain]
        
        # Check Disk Quota (15 pts)
        expected_disk = target_specs['disk_quota_mb']
        actual_disk_raw = actual.get('disk_quota_raw', '')
        actual_disk_mb = parse_size_string(actual_disk_raw)
        
        # Store for distinct check
        if actual_disk_mb is not None:
            processed_values.append(actual_disk_mb)

        # Tolerance: +/- 5% or 50MB
        if actual_disk_mb is not None:
            if abs(actual_disk_mb - expected_disk) <= max(50, expected_disk * 0.05):
                score += 15
                feedback_parts.append(f"{target_domain} Disk: OK")
            else:
                feedback_parts.append(f"{target_domain} Disk: Incorrect ({actual_disk_raw} vs {expected_disk}MB)")
        else:
             feedback_parts.append(f"{target_domain} Disk: Unlimited/Unset")

        # Check Bandwidth (15 pts)
        expected_bw_gb = target_specs['bandwidth_gb']
        actual_bw_raw = actual.get('bandwidth_limit_raw', '')
        actual_bw_mb = parse_size_string(actual_bw_raw)
        
        # Convert expected to MB for comparison
        expected_bw_mb = expected_bw_gb * 1024
        
        if actual_bw_mb is not None:
            if abs(actual_bw_mb - expected_bw_mb) <= max(100, expected_bw_mb * 0.05):
                score += 15
                feedback_parts.append(f"{target_domain} BW: OK")
            else:
                feedback_parts.append(f"{target_domain} BW: Incorrect ({actual_bw_raw} vs {expected_bw_gb}GB)")
        else:
             feedback_parts.append(f"{target_domain} BW: Unlimited/Unset")
             
    # Anti-gaming: Check if values are distinct
    # We expect 3 distinct disk quotas
    distinct_count = len(set(processed_values))
    if distinct_count == 3:
        score += 5
        feedback_parts.append("Distinct quotas applied")
    elif distinct_count > 0:
        feedback_parts.append("Warning: Some quotas identical")
    
    # Anti-gaming: Check if modified flag is true for at least one
    if any(d.get('modified', False) for d in domains_result):
        score += 5
        feedback_parts.append("Configuration modified")
    else:
        feedback_parts.append("No changes detected")

    passed = score >= 60
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }