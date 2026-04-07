#!/usr/bin/env python3
"""
Verifier for runtime_metrics_baseline task.
Evaluates:
1. Simulated device creation (via Logs/Windows)
2. Performance report file existence and freshness
3. Content analysis of the report (Metrics, Commands, Recommendations)
"""

import json
import os
import re
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_runtime_metrics_baseline(traj, env_info, task_info):
    """
    Verify that the agent created devices and profiled the JVM performance.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Retrieve result JSON
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
    feedback_parts = []
    
    # --- Check 1: Device Creation (Primary) ---
    # We look for evidence in logs or window titles
    # Known simulated device types in OpenICE
    device_keywords = [
        "multiparameter", "monitor", "pulse", "oximeter", "spo2", 
        "infusion", "pump", "co2", "capno", "nibp", "blood pressure", 
        "ecg", "temperature", "scale", "ventilator"
    ]
    
    window_list = result.get("window_list", "").lower()
    log_sample = result.get("new_log_content_sample", "").lower()
    
    created_devices = set()
    for kw in device_keywords:
        if kw in window_list or kw in log_sample:
            # Group synonyms
            if kw in ["multiparameter", "monitor"]: created_devices.add("Multiparameter Monitor")
            elif kw in ["pulse", "oximeter", "spo2"]: created_devices.add("Pulse Oximeter")
            elif kw in ["infusion", "pump"]: created_devices.add("Infusion Pump")
            elif kw in ["co2", "capno"]: created_devices.add("CO2 Monitor")
            else: created_devices.add(kw.title())
    
    # Also check generic window count increase as fallback evidence
    initial_wins = int(result.get("initial_window_count", 0))
    current_wins = int(result.get("current_window_count", 0))
    win_increase = current_wins - initial_wins
    
    if len(created_devices) >= 2:
        score += 20
        feedback_parts.append(f"Confirmed 2+ devices created: {', '.join(created_devices)}")
    elif len(created_devices) == 1:
        score += 10
        feedback_parts.append(f"Confirmed 1 device created: {list(created_devices)[0]}")
    elif win_increase >= 2:
        # Fallback: 2 new windows likely means 2 devices
        score += 10
        feedback_parts.append(f"Device creation inferred from window count (+{win_increase})")
    else:
        feedback_parts.append("No clear evidence of device creation")

    # Gate condition: If no report AND no devices, fail immediately
    report_exists = result.get("report_exists", False)
    if not report_exists and len(created_devices) == 0 and win_increase < 1:
        return {"passed": False, "score": 0, "feedback": "Did nothing: No devices created and no report found."}

    # --- Check 2: Report Existence & Freshness ---
    report_content = result.get("report_content", "")
    report_fresh = result.get("report_fresh", False)
    
    if report_exists and report_fresh:
        score += 10
        feedback_parts.append("Report file exists and was created during task")
    elif report_exists:
        score += 5
        feedback_parts.append("Report file exists but timestamp verification failed")
    else:
        feedback_parts.append("Report file missing")

    # --- Check 3: Report Content Analysis ---
    if report_content:
        lower_content = report_content.lower()
        
        # A. Device names mentioned (10 pts)
        device_mentions = 0
        for kw in device_keywords:
            if kw in lower_content:
                device_mentions += 1
        if device_mentions >= 2:
            score += 10
            feedback_parts.append("Report mentions multiple device types")
        elif device_mentions == 1:
            score += 5
            feedback_parts.append("Report mentions one device type")

        # B. Memory Metrics (15 pts)
        # Look for Heap/Memory keyword AND a number followed by MB/GB
        mem_keyword = re.search(r'(heap|memory|vmrss|resident|usage)', lower_content)
        mem_val = re.search(r'\d+(\.\d+)?\s*(mb|gb|k|m|g)', lower_content)
        if mem_keyword and mem_val:
            score += 15
            feedback_parts.append("Memory metrics documented with units")
        elif mem_keyword:
            score += 5
            feedback_parts.append("Memory mentioned but missing clear value/units")

        # C. CPU Metrics (15 pts)
        # Look for CPU keyword AND percentage
        cpu_keyword = re.search(r'(cpu|processor)', lower_content)
        cpu_val = re.search(r'\d+(\.\d+)?\s*%', lower_content)
        if cpu_keyword and cpu_val:
            score += 15
            feedback_parts.append("CPU metrics documented with %")
        elif cpu_keyword:
            score += 5
            feedback_parts.append("CPU mentioned but missing % value")

        # D. Thread Metrics (10 pts)
        thread_keyword = re.search(r'(thread)', lower_content)
        thread_val = re.search(r'\d+', lower_content)
        if thread_keyword and thread_val:
            score += 10
            feedback_parts.append("Thread count documented")
        
        # E. Commands Used (10 pts)
        # Look for common Linux/Java commands
        commands = ["jstat", "jcmd", "jmap", "jstack", "top", "ps", "proc", "vmstat", "grep", "awk"]
        cmds_found = [c for c in commands if c in lower_content]
        if len(cmds_found) >= 1:
            score += 10
            feedback_parts.append(f"Diagnostic commands documented: {', '.join(cmds_found)}")
        
        # F. Recommendation (10 pts)
        rec_keywords = ["recommend", "sizing", "gb ram", "cpu core", "suggest", "minimum", "requirements"]
        if any(k in lower_content for k in rec_keywords):
            score += 10
            feedback_parts.append("Sizing recommendation found")

    # Final Pass/Fail Check
    # Pass if score >= 60 AND OpenICE is running
    openice_running = result.get("openice_running", False)
    passed = score >= 60 and openice_running

    if not openice_running:
        feedback_parts.append("FAIL: OpenICE application was not running at end of task")

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }