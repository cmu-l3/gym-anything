#!/usr/bin/env python3
"""
Verifier for implement_custom_app_brute_force task.

Scoring Criteria:
1. Manager Running (10 pts)
2. ossec.conf Configured (15 pts) - regex check for localfile
3. Decoder Logic (20 pts) - regex check for FinConnect decoder
4. Rule Logic (25 pts) - regex check for frequency/timeframe
5. Live Verification Success (30 pts) - Did the attack actually trigger the alert?
"""

import json
import os
import re
import logging
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_implement_custom_app_brute_force(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result JSON
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    score = 0
    feedback = []
    
    # 1. Manager Status (10 pts)
    if result.get("manager_running", False):
        score += 10
        feedback.append("Wazuh manager is running.")
    else:
        feedback.append("Wazuh manager is NOT running.")

    # 2. Live Verification (30 pts)
    # This is the gold standard. If this works, the config MUST be mostly correct.
    verification_triggered = result.get("verification_triggered", False)
    if verification_triggered:
        score += 30
        feedback.append("Live verification passed: Brute force attack detected.")
    else:
        feedback.append("Live verification failed: Simulated attack was not detected.")

    # Helper to read file content
    def read_remote_file(remote_path):
        if not remote_path: return ""
        tf = tempfile.NamedTemporaryFile(delete=False)
        try:
            copy_from_env(remote_path, tf.name)
            with open(tf.name, 'r', errors='ignore') as f:
                return f.read()
        except:
            return ""
        finally:
            if os.path.exists(tf.name): os.unlink(tf.name)

    # 3. ossec.conf Analysis (15 pts)
    ossec_conf = read_remote_file(result.get("ossec_conf_path"))
    # Look for <localfile> block with the log path
    if "/var/log/finconnect/app.log" in ossec_conf and "<localfile>" in ossec_conf:
        score += 15
        feedback.append("ossec.conf configured for log file.")
    else:
        feedback.append("ossec.conf missing valid <localfile> entry for app.log.")

    # 4. Decoder Analysis (20 pts)
    decoder_xml = read_remote_file(result.get("decoder_xml_path"))
    # Look for program_name "FinConnect" and regex extraction
    if 'program_name>FinConnect' in decoder_xml or 'program_name>FinConnect' in decoder_xml:
        if re.search(r'<regex>.*User=(\S+)\s+IP=(\S+)\s+Status=(\S+)', decoder_xml, re.IGNORECASE) or \
           re.search(r'<regex>\s*User\s*=', decoder_xml): # Lenient regex check
            score += 20
            feedback.append("Custom decoder found with field extraction.")
        else:
            score += 10
            feedback.append("Custom decoder found but regex seems incomplete.")
    else:
        feedback.append("Decoder for 'FinConnect' not found in local_decoder.xml.")

    # 5. Rule Analysis (25 pts)
    rules_xml = read_remote_file(result.get("rules_xml_path"))
    
    # Check Rule 100205 (Base)
    has_base = "100205" in rules_xml and ("Failed" in rules_xml or "Status" in rules_xml)
    
    # Check Rule 100210 (Correlation)
    # Must have frequency, timeframe, same_source_ip, if_matched_sid
    has_correlation = "100210" in rules_xml
    has_freq = re.search(r'frequency="5"', rules_xml)
    has_time = re.search(r'timeframe="30"', rules_xml)
    has_same_ip = "same_source_ip" in rules_xml
    
    if has_base:
        score += 10
        feedback.append("Base rule 100205 found.")
    
    if has_correlation and has_freq and has_time and has_same_ip:
        score += 15
        feedback.append("Correlation rule 100210 found with correct parameters.")
    elif has_correlation:
        score += 5
        feedback.append("Correlation rule 100210 found but missing parameters (frequency/same_source_ip).")

    # Anti-gaming / Safety Net
    # If live verification passed, ensure score is at least 80 even if static analysis failed (due to unexpected formatting)
    if verification_triggered and score < 80:
        score = 80
        feedback.append("Static analysis failed but system works (score boosted).")

    passed = score >= 60 and verification_triggered
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }