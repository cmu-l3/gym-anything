#!/usr/bin/env python3
"""
Verifier for Workload Manager Configuration Task.
Checks if the Oracle Resource Manager plan, groups, directives, and mappings are correctly configured.
"""

import json
import logging
import os
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_workload_manager(traj, env_info, task_info):
    """
    Verify Oracle Workload Manager configuration.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Retrieve result JSON
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/workload_manager_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    # Check for DB connection errors
    if result.get("error"):
        return {"passed": False, "score": 0, "feedback": f"Database verification error: {result['error']}"}

    score = 0
    feedback_parts = []
    
    # 1. Plan Existence (10 pts)
    if result.get("plan_exists"):
        score += 10
        feedback_parts.append("Plan STABILITY_PLAN created")
    else:
        feedback_parts.append("Plan STABILITY_PLAN not found")

    # 2. Consumer Groups Existence (10 pts)
    groups = result.get("consumer_groups", [])
    if "CRITICAL_APP_CG" in groups and "BATCH_REPORT_CG" in groups:
        score += 10
        feedback_parts.append("Consumer groups created")
    else:
        feedback_parts.append(f"Consumer groups missing (found: {groups})")

    # 3. CPU Allocation Rules (20 pts)
    # Looking for CRITICAL_APP_CG=60, BATCH_REPORT_CG=20, OTHER_GROUPS=20 (at level 1)
    directives = result.get("directives", [])
    cpu_correct = False
    critical_cpu = next((d for d in directives if d["group"] == "CRITICAL_APP_CG"), None)
    batch_cpu = next((d for d in directives if d["group"] == "BATCH_REPORT_CG"), None)
    other_cpu = next((d for d in directives if d["group"] == "OTHER_GROUPS"), None)

    if critical_cpu and batch_cpu and other_cpu:
        if (critical_cpu.get("cpu_p1") == 60 and 
            batch_cpu.get("cpu_p1") == 20 and 
            other_cpu.get("cpu_p1") == 20):
            score += 20
            feedback_parts.append("CPU allocations correct (60/20/20)")
            cpu_correct = True
        else:
            feedback_parts.append("CPU allocations incorrect percentages")
    else:
        feedback_parts.append("Missing directives for required groups")

    # 4. Switching Rule (20 pts)
    # CRITICAL_APP_CG -> switch to BATCH_REPORT_CG after 60s
    switch_correct = False
    if critical_cpu:
        sw_time = critical_cpu.get("switch_time")
        sw_group = critical_cpu.get("switch_group")
        if sw_time == 60 and sw_group == "BATCH_REPORT_CG":
            score += 20
            switch_correct = True
            feedback_parts.append("Switching rule correct")
        else:
            feedback_parts.append(f"Switching rule incorrect (time={sw_time}, target={sw_group})")

    # 5. User Mapping (10 pts)
    mappings = result.get("mappings", [])
    app_mapped = any(m["user"] == "APP_USER" and m["group"] == "CRITICAL_APP_CG" for m in mappings)
    rpt_mapped = any(m["user"] == "RPT_USER" and m["group"] == "BATCH_REPORT_CG" for m in mappings)
    
    if app_mapped and rpt_mapped:
        score += 10
        feedback_parts.append("User mappings correct")
    elif app_mapped or rpt_mapped:
        score += 5
        feedback_parts.append("User mappings partially correct")
    else:
        feedback_parts.append("User mappings missing")

    # 6. Switch Privileges (10 pts)
    # Users need privilege to switch to assigned groups for mapping to work
    privs = result.get("privileges", [])
    app_priv = any(p["user"] == "APP_USER" and p["group"] == "CRITICAL_APP_CG" for p in privs)
    rpt_priv = any(p["user"] == "RPT_USER" and p["group"] == "BATCH_REPORT_CG" for p in privs)

    if app_priv and rpt_priv:
        score += 10
        feedback_parts.append("Switch privileges granted")
    else:
        feedback_parts.append("Missing switch privileges")

    # 7. Plan Enabled (20 pts)
    if result.get("plan_enabled"):
        score += 20
        feedback_parts.append("Plan is currently active")
    else:
        feedback_parts.append(f"Plan not active (current: {result.get('active_plan')})")

    # Final result
    passed = (score >= 60 and result.get("plan_enabled") and cpu_correct)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }