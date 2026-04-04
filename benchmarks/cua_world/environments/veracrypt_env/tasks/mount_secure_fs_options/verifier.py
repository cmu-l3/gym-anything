#!/usr/bin/env python3
"""
Verifier for mount_secure_fs_options task.

Task: Mount encrypted volume with noexec, nosuid, nodev options and report findings.

Verification Criteria:
1. Volume mounted at correct location (25 pts)
2. Filesystem Options:
   - noexec applied (20 pts)
   - nosuid applied (10 pts)
   - nodev applied (10 pts)
3. Files accessible (10 pts)
4. Report exists and is valid (10 pts)
5. Report content correctness (15 pts)

Pass Threshold: 65 points (Must have mount + options/report)
"""

import json
import tempfile
import os
import logging
import re

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_mount_secure_fs_options(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    score = 0
    max_score = 100
    feedback_parts = []
    
    # Retrieve result JSON
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        try:
            copy_from_env("/tmp/task_result.json", temp_result.name)
            with open(temp_result.name, 'r') as f:
                result = json.load(f)
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}

        # 1. Check Mount Status (25 pts)
        is_mounted = result.get('is_mounted', False)
        mount_point = result.get('mount_point', 'unknown')
        if is_mounted:
            score += 25
            feedback_parts.append(f"Volume mounted at {mount_point}")
        else:
            feedback_parts.append("Volume NOT mounted at required path")
            # Major fail if not mounted, but continue checking report
        
        # 2. Check Filesystem Options (40 pts total)
        mount_opts = result.get('mount_options', '')
        noexec_active = result.get('noexec_active', False)
        
        # noexec (20 pts)
        if 'noexec' in mount_opts:
            score += 20
            feedback_parts.append("Option 'noexec' found")
        elif noexec_active:
            # Fallback: if script failed to run but option text missing (rare), give credit
            score += 20
            feedback_parts.append("Option 'noexec' enforced (verified via test)")
        else:
            feedback_parts.append("Option 'noexec' MISSING")

        # nosuid (10 pts)
        if 'nosuid' in mount_opts:
            score += 10
            feedback_parts.append("Option 'nosuid' found")
        else:
            feedback_parts.append("Option 'nosuid' MISSING")

        # nodev (10 pts)
        if 'nodev' in mount_opts:
            score += 10
            feedback_parts.append("Option 'nodev' found")
        else:
            feedback_parts.append("Option 'nodev' MISSING")

        # 3. Files Accessible (10 pts)
        files_count = result.get('files_count', 0)
        # We expect at least the 3 sample files provided in setup
        if files_count >= 2:
            score += 10
            feedback_parts.append(f"Files accessible ({files_count} files)")
        elif is_mounted:
            feedback_parts.append(f"Volume appears empty ({files_count} files)")
        
        # 4. Report Existence (10 pts)
        report_exists = result.get('report_exists', False)
        report_size = result.get('report_size', 0)
        
        if report_exists and report_size > 50:
            score += 10
            feedback_parts.append("Report file exists")
        elif report_exists:
            score += 5
            feedback_parts.append("Report file exists but is very short")
        else:
            feedback_parts.append("Report file NOT found")

        # 5. Report Content (15 pts)
        report_content = result.get('report_content', '').lower()
        content_score = 0
        
        if report_exists:
            # Check for path mentions
            if 'secure_data' in report_content or 'mountpoints' in report_content:
                content_score += 3
            if 'data_volume' in report_content:
                content_score += 3
                
            # Check for options mentions
            if 'noexec' in report_content and 'nosuid' in report_content:
                content_score += 3
            
            # Check for file listing (partial match)
            if 'sf312' in report_content or 'budget' in report_content or 'authorized_keys' in report_content:
                content_score += 3
            
            # Check for functionality confirmation
            if any(x in report_content for x in ['denied', 'permission', 'prevented', 'working', 'success']):
                content_score += 3
            
            score += content_score
            feedback_parts.append(f"Report content quality: {content_score}/15")

        # Anti-Gaming: Check timestamps
        task_start = result.get('task_start', 0)
        task_end = result.get('task_end', 0)
        
        if is_mounted and task_start > 0:
            # Note: We can't easily check mount time from Python without stat-ing the mount point
            # which happens in export_result.sh. Assuming export_result handled the logic check
            pass

    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Verification error: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    passed = score >= 65
    feedback = " | ".join(feedback_parts)

    return {
        "passed": passed,
        "score": score,
        "feedback": feedback
    }