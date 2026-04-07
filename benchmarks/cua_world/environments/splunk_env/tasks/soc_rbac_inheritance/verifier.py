#!/usr/bin/env python3
"""Verifier for soc_rbac_inheritance task.

STRICT REQUIREMENTS:
- soc_tier1 MUST exist and inherit 'user'.
- soc_tier1 MUST restrict indexes to 'security_logs' and 'web_logs' (no '*' or 'main').
- soc_tier1 MUST have Jobs Quota = 2, Time Window = 604800.
- soc_tier2 MUST exist and inherit 'soc_tier1'.
- soc_tier2 MUST have Jobs Quota = 6, Time Window = 0 (infinite).
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_soc_rbac_inheritance(traj, env_info, task_info):
    """Verify that the agent correctly created the hierarchical Splunk roles."""
    
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

    role_analysis = result.get('role_analysis', {})
    
    score = 0
    feedback_parts = []
    
    tier1_found = role_analysis.get('tier1_found', False)
    tier1_config = role_analysis.get('tier1_config', {})
    tier2_found = role_analysis.get('tier2_found', False)
    tier2_config = role_analysis.get('tier2_config', {})

    # =======================================================
    # CRITERION 1: soc_tier1 Exists and Inherits (15 points)
    # =======================================================
    if tier1_found:
        imported_t1 = tier1_config.get('imported_roles', [])
        if isinstance(imported_t1, str):
            imported_t1 = [imported_t1]
            
        if 'user' in imported_t1:
            score += 15
            feedback_parts.append("soc_tier1 exists and correctly inherits 'user'")
        else:
            feedback_parts.append(f"soc_tier1 exists but misses 'user' inheritance (Got: {imported_t1})")
    else:
        feedback_parts.append("FAIL: soc_tier1 was not created")

    # =======================================================
    # CRITERION 2: soc_tier1 Index Restrictions (20 points)
    # =======================================================
    if tier1_found:
        idx_t1 = tier1_config.get('srchIndexesAllowed', [])
        if isinstance(idx_t1, str):
            idx_t1 = [idx_t1]
            
        idx_t1_clean = [i.strip().lower() for i in idx_t1]
        
        has_sec = 'security_logs' in idx_t1_clean
        has_web = 'web_logs' in idx_t1_clean
        has_wildcard = '*' in idx_t1_clean or 'main' in idx_t1_clean
        
        if has_sec and has_web and not has_wildcard:
            score += 20
            feedback_parts.append("soc_tier1 index restrictions are strictly configured")
        elif has_sec and has_web and has_wildcard:
            feedback_parts.append("FAIL: soc_tier1 has correct indexes but still allows '*' or 'main'")
        else:
            feedback_parts.append(f"FAIL: soc_tier1 indexes are incorrect (Got: {idx_t1})")

    # =======================================================
    # CRITERION 3: soc_tier1 Quotas Applied (15 points)
    # =======================================================
    if tier1_found:
        t1_jobs = str(tier1_config.get('srchJobsQuota', '')).strip()
        t1_time = str(tier1_config.get('srchTimeWin', '')).strip().lower()
        
        jobs_ok = t1_jobs == '2'
        time_ok = t1_time in ['604800', '7d', '7days', '7 days']
        
        if jobs_ok and time_ok:
            score += 15
            feedback_parts.append("soc_tier1 quota limits are correct (Jobs=2, Time=7d)")
        else:
            feedback_parts.append(f"FAIL: soc_tier1 quotas incorrect (Jobs={t1_jobs}, Time={t1_time})")

    # =======================================================
    # CRITERION 4: soc_tier2 Exists and Inherits (20 points)
    # =======================================================
    if tier2_found:
        imported_t2 = tier2_config.get('imported_roles', [])
        if isinstance(imported_t2, str):
            imported_t2 = [imported_t2]
            
        if 'soc_tier1' in imported_t2:
            score += 20
            feedback_parts.append("soc_tier2 exists and correctly inherits 'soc_tier1'")
        else:
            feedback_parts.append(f"soc_tier2 exists but misses 'soc_tier1' inheritance (Got: {imported_t2})")
    else:
        feedback_parts.append("FAIL: soc_tier2 was not created")

    # =======================================================
    # CRITERION 5: soc_tier2 Quota Overrides (30 points)
    # =======================================================
    if tier2_found:
        t2_jobs = str(tier2_config.get('srchJobsQuota', '')).strip()
        t2_time = str(tier2_config.get('srchTimeWin', '')).strip()
        
        jobs_ok = t2_jobs == '6'
        # Infinite in Splunk is represented by 0 or -1, or occasionally left empty
        time_ok = t2_time in ['0', '-1', '']
        
        if jobs_ok and time_ok:
            score += 30
            feedback_parts.append("soc_tier2 overrides are correct (Jobs=6, Time=Infinite)")
        else:
            feedback_parts.append(f"FAIL: soc_tier2 overrides incorrect (Jobs={t2_jobs}, Time={t2_time})")

    # Determine pass/fail
    passed = score >= 70 and tier1_found and tier2_found

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }