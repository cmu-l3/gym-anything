#!/usr/bin/env python3
"""
Verifier for tune_storage_performance task.

Criteria:
1. Backup Bandwidth Limit: 15 Mbps (+/- 10%)
2. Storage Reserved Space: 30 GB (+/- 5%)
"""

import json
import os
import logging
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_tune_storage_performance(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load task metadata for targets
    metadata = task_info.get('metadata', {})
    target_bandwidth_bps = metadata.get('target_bandwidth_bps', 15000000) # 15 Mbps
    target_reserved_bytes = metadata.get('target_reserved_bytes', 32212254720) # 30 GB
    
    bandwidth_tolerance = metadata.get('bandwidth_tolerance_percent', 10) / 100.0
    storage_tolerance = metadata.get('storage_tolerance_percent', 5) / 100.0

    # Retrieve result file
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read verification data: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    if result.get('error'):
        return {"passed": False, "score": 0, "feedback": f"Error during export: {result['error']}"}

    score = 0
    feedback_parts = []

    # --- Verify Backup Bandwidth ---
    actual_bps = result.get('final_backup_bandwidth_bps', -1)
    
    # 15 Mbps = 15,000,000 bps usually in networking context, 
    # but sometimes 15 * 1024 * 1024 = 15,728,640. 
    # We use a broad tolerance to accept either interpretation by the agent/system.
    
    if actual_bps == -1:
        feedback_parts.append("❌ Could not read backup bandwidth setting.")
    else:
        # Check absolute difference or percentage
        diff = abs(actual_bps - target_bandwidth_bps)
        # Allow loose interpretation (Decimal vs Binary Mega)
        # 15,000,000 vs 15,728,640 is about 5% diff. The 10% tolerance covers it.
        
        if diff <= (target_bandwidth_bps * bandwidth_tolerance) or \
           abs(actual_bps - (15 * 1024 * 1024)) < (15 * 1024 * 1024 * 0.1):
            score += 50
            feedback_parts.append(f"✅ Backup bandwidth set correctly ({actual_bps/1000000:.2f} Mbps).")
        else:
            feedback_parts.append(f"❌ Backup bandwidth incorrect. Expected ~15 Mbps, found {actual_bps/1000000:.2f} Mbps.")

    # --- Verify Storage Reserved Space ---
    actual_bytes = result.get('final_reserved_space_bytes', -1)
    
    # 30 GB = 30 * 1024^3 = 32,212,254,720 bytes
    
    if actual_bytes == -1:
        feedback_parts.append("❌ Could not read storage reserved space.")
    else:
        diff = abs(actual_bytes - target_reserved_bytes)
        
        if diff <= (target_reserved_bytes * storage_tolerance):
            score += 50
            feedback_parts.append(f"✅ Storage reserved space set correctly ({actual_bytes/1024/1024/1024:.2f} GB).")
        else:
            feedback_parts.append(f"❌ Storage reserved space incorrect. Expected 30 GB, found {actual_bytes/1024/1024/1024:.2f} GB.")

    passed = (score >= 100)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback_parts)
    }