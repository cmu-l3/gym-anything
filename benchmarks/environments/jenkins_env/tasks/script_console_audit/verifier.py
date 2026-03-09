#!/usr/bin/env python3
"""
Verifier for Jenkins Script Console System Audit task.
"""

import json
import sys
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_script_console_audit(traj, env_info, task_info):
    """
    Verify the Script Console Audit task results.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    score = 0
    max_score = 100
    details = []
    
    # Load results from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/script_console_audit_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {
            "score": 0,
            "max_score": max_score,
            "passed": False,
            "feedback": f"Could not load result file: {e}"
        }
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # Criterion 1: File exists and non-empty (10 points)
    if result.get("file_exists", False):
        if result.get("file_lines", 0) > 0:
            score += 10
            details.append("✓ Audit report file exists and is non-empty (+10)")
        else:
            details.append("✗ Audit report file exists but is empty (+0)")
    else:
        details.append("✗ Audit report file does not exist at /var/jenkins_home/audit_report.txt (+0)")

    # Anti-gaming: File created during task (Critical)
    if not result.get("file_created_during_task", False):
        details.append("⚠ File was not created/modified during task session!")
        # We don't fail immediately but penalty applies if score > 0
        score = 0 
    
    # Criterion 2: Jenkins version present (15 points)
    if result.get("version_in_file", False):
        score += 15
        details.append(f"✓ Jenkins version '{result.get('gt_version', '?')}' found in report (+15)")
    else:
        details.append(f"✗ Jenkins version not found in report (+0)")

    # Criterion 3: JVM info present (10 points)
    if result.get("jvm_in_file", False):
        score += 10
        details.append("✓ JVM/Java information found in report (+10)")
    else:
        details.append("✗ No JVM/Java information found in report (+0)")

    # Criterion 4: Plugin listing present (20 points)
    if result.get("has_plugin_entries", False):
        score += 20
        details.append(f"✓ Plugin entries found (+20)")
    else:
        details.append(f"✗ No substantial plugin listing found (+0)")

    # Criterion 5: Plugin coverage >= 80% (15 points)
    total_gt = result.get("total_gt_plugins", 0)
    matched = result.get("matched_plugins", 0)
    if total_gt > 0:
        coverage = matched / total_gt
        if coverage >= 0.8:
            score += 15
            details.append(f"✓ Plugin coverage: {matched}/{total_gt} ({coverage:.0%}) >= 80% (+15)")
        elif coverage >= 0.5:
            partial = int(15 * (coverage - 0.5) / 0.3)
            score += partial
            details.append(f"△ Plugin coverage: {matched}/{total_gt} ({coverage:.0%}) - partial credit (+{partial})")
        else:
            details.append(f"✗ Plugin coverage: {matched}/{total_gt} ({coverage:.0%}) < 50% (+0)")

    # Criterion 6: Plugin versions accurate (10 points)
    sampled_total = result.get("sampled_version_total", 0)
    sampled_matches = result.get("sampled_version_matches", 0)
    if sampled_total > 0:
        if sampled_matches / sampled_total >= 0.75:
            score += 10
            details.append(f"✓ Plugin version accuracy: {sampled_matches}/{sampled_total} sampled versions correct (+10)")
        elif sampled_matches / sampled_total >= 0.5:
            score += 5
            details.append(f"△ Plugin version accuracy: {sampled_matches}/{sampled_total} - partial (+5)")
        else:
            details.append(f"✗ Plugin version accuracy low (+0)")
    else:
        details.append("△ Could not verify plugin versions (no samples matched) (+0)")

    # Criterion 7: All pre-existing jobs listed (15 points)
    jobs_found = result.get("jobs_found", 0)
    jobs_expected = result.get("jobs_expected", 3)
    if jobs_found >= jobs_expected:
        score += 15
        details.append(f"✓ All {jobs_expected} pre-existing jobs found in report (+15)")
    elif jobs_found > 0:
        partial = int(15 * jobs_found / jobs_expected)
        score += partial
        details.append(f"△ {jobs_found}/{jobs_expected} pre-existing jobs found (+{partial})")
    else:
        details.append(f"✗ No pre-existing jobs found in report (+0)")

    # Criterion 8: File substantive > 20 lines (5 points)
    if result.get("file_lines", 0) > 20:
        score += 5
        details.append(f"✓ Report is substantive ({result['file_lines']} lines) (+5)")
    else:
        details.append(f"✗ Report too short ({result.get('file_lines', 0)} lines) (+0)")

    passed = score >= 70
    
    return {
        "score": score,
        "max_score": max_score,
        "passed": passed,
        "feedback": "\n".join(details)
    }