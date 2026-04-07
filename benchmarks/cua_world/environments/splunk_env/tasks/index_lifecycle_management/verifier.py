#!/usr/bin/env python3
"""
Verifier for the index_lifecycle_management task.

Verifies:
1. audit_trail index exists with specific retention and size limits.
2. security_logs index retention updated.
3. web_logs index retention updated.
4. Index_Volume_Monitor saved search exists and contains index metadata logic.
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def check_numeric_tolerance(actual_str, expected_val, tolerance):
    """Safely check if a string numeric value is within tolerance of expected."""
    try:
        actual_val = float(actual_str)
        return abs(actual_val - expected_val) <= tolerance
    except (ValueError, TypeError):
        return False

def verify_index_lifecycle(traj, env_info, task_info):
    """Verify that the data lifecycle settings were correctly applied."""
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    ret_365 = metadata.get('retention_365_days_sec', 31536000)
    ret_90 = metadata.get('retention_90_days_sec', 7776000)
    ret_tol = metadata.get('retention_tolerance_sec', 86400)
    max_size = metadata.get('max_size_5gb_mb', 5120)
    size_tol = metadata.get('max_size_tolerance_mb', 512)
    metadata_keywords = metadata.get('metadata_keywords', [])

    # Copy result file from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/index_lifecycle_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    analysis = result.get('analysis', {})
    audit_trail = analysis.get('audit_trail', {})
    security_logs = analysis.get('security_logs', {})
    web_logs = analysis.get('web_logs', {})
    saved_search = analysis.get('saved_search', {})

    score = 0
    feedback_parts = []
    
    # 1. audit_trail index exists (15 points)
    if audit_trail.get('exists', False):
        score += 15
        feedback_parts.append("audit_trail index exists")
        
        # 2. audit_trail retention is 365 days (15 points)
        if check_numeric_tolerance(audit_trail.get('frozenTimePeriodInSecs'), ret_365, ret_tol):
            score += 15
            feedback_parts.append("audit_trail retention is ~365 days")
        else:
            feedback_parts.append(f"FAIL: audit_trail retention incorrect (expected {ret_365}, got {audit_trail.get('frozenTimePeriodInSecs')})")

        # 3. audit_trail size is 5GB (10 points)
        if check_numeric_tolerance(audit_trail.get('maxTotalDataSizeMB'), max_size, size_tol):
            score += 10
            feedback_parts.append("audit_trail max size is ~5GB")
        else:
            feedback_parts.append(f"FAIL: audit_trail max size incorrect (expected {max_size}, got {audit_trail.get('maxTotalDataSizeMB')})")
    else:
        feedback_parts.append("FAIL: audit_trail index does not exist")

    # 4. security_logs retention updated (20 points)
    if security_logs.get('exists', False):
        if check_numeric_tolerance(security_logs.get('frozenTimePeriodInSecs'), ret_365, ret_tol):
            score += 20
            feedback_parts.append("security_logs retention updated to ~365 days")
        else:
            feedback_parts.append(f"FAIL: security_logs retention incorrect (got {security_logs.get('frozenTimePeriodInSecs')})")
    else:
        feedback_parts.append("FAIL: security_logs index missing")

    # 5. web_logs retention updated (20 points)
    if web_logs.get('exists', False):
        if check_numeric_tolerance(web_logs.get('frozenTimePeriodInSecs'), ret_90, ret_tol):
            score += 20
            feedback_parts.append("web_logs retention updated to ~90 days")
        else:
            feedback_parts.append(f"FAIL: web_logs retention incorrect (got {web_logs.get('frozenTimePeriodInSecs')})")
    else:
        feedback_parts.append("FAIL: web_logs index missing")

    # 6. Saved search exists (10 points)
    if saved_search.get('exists', False):
        score += 10
        feedback_parts.append("Index_Volume_Monitor saved search exists")
        
        # 7. Saved search logic contains metadata querying concepts (10 points)
        search_query = saved_search.get('search', '').lower()
        if any(kw.lower() in search_query for kw in metadata_keywords):
            score += 10
            feedback_parts.append("Saved search appropriately queries index metadata")
        else:
            feedback_parts.append(f"FAIL: Saved search logic does not appear to query internal metadata (query: {search_query[:50]}...)")
    else:
        feedback_parts.append("FAIL: Index_Volume_Monitor saved search does not exist")

    # Pass threshold: 60 points
    passed = score >= 60

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }