#!/usr/bin/env python3
"""
Verifier for graphite_nagios_plugin task.

Evaluates the Python script by inspecting the test outcomes exported from the container.
"""

import json
import os
import re
import tempfile

RESULT_PATH = "/tmp/graphite_nagios_plugin_result.json"

def check_nagios_output(stdout, expected_status, expected_value, expected_warning, expected_critical):
    if not stdout:
        return False, "No stdout produced"
    
    parts = stdout.split('|')
    if len(parts) != 2:
        return False, "Missing or multiple pipe '|' characters separating message and perfdata"
    
    msg, perfdata = parts[0].strip(), parts[1].strip()
    
    if not msg.upper().startswith(expected_status):
        return False, f"Status message does not start with '{expected_status}'"
    
    # Check if the correct parsed metric value appears in the string
    val_str = str(expected_value)
    if val_str not in msg and str(float(expected_value)) not in msg and str(int(expected_value)) not in msg:
        return False, f"Expected value {expected_value} not found in the status message"
    
    # Validate Nagios performance data format: metric=val;warn;crit
    perf_match = re.search(r"metric=([0-9\.\-]+)\s*;\s*([0-9\.\-]+)\s*;\s*([0-9\.\-]+)", perfdata)
    if not perf_match:
        return False, "Perfdata does not match the 'metric=val;warn;crit' pattern"
    
    pval, pwarn, pcrit = float(perf_match.group(1)), float(perf_match.group(2)), float(perf_match.group(3))
    
    if pval != float(expected_value):
        return False, f"Perfdata metric value '{pval}' does not match expected '{expected_value}'"
    if pwarn != float(expected_warning):
        return False, f"Perfdata warning value '{pwarn}' does not match expected '{expected_warning}'"
    if pcrit != float(expected_critical):
        return False, f"Perfdata critical value '{pcrit}' does not match expected '{expected_critical}'"
        
    return True, "Valid"

def check_unknown_output(stdout):
    if not stdout:
        return False, "No stdout produced"
    if not stdout.upper().startswith("UNKNOWN"):
        return False, "Message does not start with 'UNKNOWN'"
    return True, "Valid"

def check_real_metric_output(stdout, exit_code, expected_warning, expected_critical):
    if exit_code not in [0, 1, 2]:
        return False, f"Invalid state exit code: {exit_code} (expected 0, 1, or 2)"
        
    parts = stdout.split('|')
    if len(parts) != 2:
        return False, "Missing perfdata pipe '|' character"
        
    msg, perfdata = parts[0].strip(), parts[1].strip()
    status = msg.split()[0].upper() if msg else ""
    if exit_code == 0 and status != "OK": return False, "Exit code 0 but textual status is not OK"
    if exit_code == 1 and status != "WARNING": return False, "Exit code 1 but textual status is not WARNING"
    if exit_code == 2 and status != "CRITICAL": return False, "Exit code 2 but textual status is not CRITICAL"
    
    perf_match = re.search(r"metric=([0-9\.\-]+)\s*;\s*([0-9\.\-]+)\s*;\s*([0-9\.\-]+)", perfdata)
    if not perf_match:
        return False, "Perfdata formatting is invalid"
        
    pwarn, pcrit = float(perf_match.group(2)), float(perf_match.group(3))
    if pwarn != float(expected_warning): return False, "Warning threshold mismatch in perfdata"
    if pcrit != float(expected_critical): return False, "Critical threshold mismatch in perfdata"
    
    return True, "Valid"

def verify_graphite_nagios_plugin(trajectory, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}
        
    try:
        with tempfile.NamedTemporaryFile(suffix=".json", delete=False) as tmp:
            tmp_path = tmp.name
        copy_from_env(RESULT_PATH, tmp_path)
        with open(tmp_path) as f:
            result = json.load(f)
        os.unlink(tmp_path)
    except Exception as e:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Could not load test results file: {e}"
        }
        
    score = 0
    feedback_parts = []
    
    if not result.get("script_exists"):
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "Target script /home/ga/check_graphite_metric.py does not exist."
        }
        
    score += 5
    feedback_parts.append("[+5] Script exists")
    
    if result.get("script_executable"):
        score += 5
        feedback_parts.append("[+5] Script is executable")
    else:
        feedback_parts.append("[-] Script is not executable (chmod +x was not applied)")
        
    tests = result.get("tests", {})
    if not tests:
        return {"passed": False, "score": score, "feedback": " | ".join(feedback_parts) + " | No execution test results found."}
        
    # Test 1: OK State (15 pts)
    test_ok = tests.get("ok", {})
    if test_ok.get("exit_code") == 0:
        ok_valid, ok_msg = check_nagios_output(test_ok.get("stdout", ""), "OK", 50, 70, 90)
        if ok_valid:
            score += 15
            feedback_parts.append("[+15] OK Test passed")
        else:
            feedback_parts.append(f"[-] OK Test failed: {ok_msg}")
    else:
        feedback_parts.append(f"[-] OK Test failed: exit code {test_ok.get('exit_code')} (expected 0). Stderr: {test_ok.get('stderr')}")
        
    # Test 2: WARNING State (15 pts)
    test_warn = tests.get("warning", {})
    if test_warn.get("exit_code") == 1:
        w_valid, w_msg = check_nagios_output(test_warn.get("stdout", ""), "WARNING", 80, 70, 90)
        if w_valid:
            score += 15
            feedback_parts.append("[+15] WARNING Test passed")
        else:
            feedback_parts.append(f"[-] WARNING Test failed: {w_msg}")
    else:
        feedback_parts.append(f"[-] WARNING Test failed: exit code {test_warn.get('exit_code')} (expected 1). Stderr: {test_warn.get('stderr')}")
        
    # Test 3: CRITICAL State (15 pts)
    test_crit = tests.get("critical", {})
    if test_crit.get("exit_code") == 2:
        c_valid, c_msg = check_nagios_output(test_crit.get("stdout", ""), "CRITICAL", 95, 70, 90)
        if c_valid:
            score += 15
            feedback_parts.append("[+15] CRITICAL Test passed")
        else:
            feedback_parts.append(f"[-] CRITICAL Test failed: {c_msg}")
    else:
        feedback_parts.append(f"[-] CRITICAL Test failed: exit code {test_crit.get('exit_code')} (expected 2). Stderr: {test_crit.get('stderr')}")
        
    # Test 4: UNKNOWN State (15 pts)
    test_unk = tests.get("unknown", {})
    if test_unk.get("exit_code") == 3:
        u_valid, u_msg = check_unknown_output(test_unk.get("stdout", ""))
        if u_valid:
            score += 15
            feedback_parts.append("[+15] UNKNOWN Test passed (handled missing metric)")
        else:
            feedback_parts.append(f"[-] UNKNOWN Test failed: {u_msg}")
    else:
        feedback_parts.append(f"[-] UNKNOWN Test failed: exit code {test_unk.get('exit_code')} (expected 3 for no data). Stderr: {test_unk.get('stderr')}")
        
    # Test 5: URL Encoding (15 pts)
    test_url = tests.get("url_encode", {})
    if test_url.get("exit_code") == 1:
        url_valid, url_msg = check_nagios_output(test_url.get("stdout", ""), "WARNING", 75, 70, 90)
        if url_valid:
            score += 15
            feedback_parts.append("[+15] URL Encode Test passed (handled complex target)")
        else:
            feedback_parts.append(f"[-] URL Encode Test failed: {url_msg}")
    else:
        feedback_parts.append(f"[-] URL Encode Test failed: exit code {test_url.get('exit_code')} (expected 1). Probable HTTP 400 Bad Request. Stderr: {test_url.get('stderr')}")
        
    # Test 6: Null value handling / Real Metric (15 pts)
    test_real = tests.get("real_metric", {})
    if test_real.get("exit_code") in [0, 1, 2]:
        r_valid, r_msg = check_real_metric_output(test_real.get("stdout", ""), test_real.get("exit_code"), 0, 200)
        if r_valid:
            score += 15
            feedback_parts.append("[+15] Real Metric Test passed (successfully filtered trailing nulls)")
        else:
            feedback_parts.append(f"[-] Real Metric Test failed: {r_msg}")
    else:
        feedback_parts.append(f"[-] Real Metric Test failed: Script crashed/errored (exit code {test_real.get('exit_code')}). Likely a TypeError from unfiltered trailing nulls. Stderr: {test_real.get('stderr')}")

    passed = score >= 70
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }