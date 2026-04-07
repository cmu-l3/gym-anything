#!/usr/bin/env python3
"""
Verifier for create_custom_decoder task.

Verification Strategy:
1. Static Analysis: Parse XML files for correct structure, names, regex, and rule IDs.
2. Functional Analysis: Check output of `wazuh-logtest` run on a test log line.
3. Anti-gaming: Ensure files were modified during the task window.
"""

import json
import os
import re
import tempfile
import logging
import xml.etree.ElementTree as ET

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_custom_decoder(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result from container
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {str(e)}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    score = 0
    max_score = 100
    feedback_parts = []

    # --- 1. Anti-gaming / Prerequisite Checks (10 pts) ---
    files_modified = result.get('files_modified_during_task', False)
    manager_status = result.get('manager_status', '')

    if files_modified:
        score += 5
        feedback_parts.append("Files modified during task")
    else:
        feedback_parts.append("Files NOT modified during task")

    if "wazuh-manager is running" in manager_status or "is running" in manager_status:
        score += 5
        feedback_parts.append("Manager running")
    else:
        feedback_parts.append("Manager NOT running (config error?)")

    # --- 2. Static XML Analysis (40 pts) ---
    decoder_content = result.get('decoder_content', '')
    rules_content = result.get('rules_content', '')

    # Check Decoder XML
    decoder_valid = False
    try:
        # Wrap in fake root if multiple root elements exist (common in these files)
        if not decoder_content.strip().startswith('<root>'):
            wrapped_decoder = f"<root>{decoder_content}</root>"
        else:
            wrapped_decoder = decoder_content
        
        root = ET.fromstring(wrapped_decoder)
        
        # Look for decoder named 'bastion-session'
        target_decoder = None
        for decoder in root.findall(".//decoder"):
            if decoder.get('name') == 'bastion-session':
                target_decoder = decoder
                break
        
        if target_decoder is not None:
            score += 10
            feedback_parts.append("Decoder 'bastion-session' found")
            
            # Check program name
            prog = target_decoder.find('program_name')
            if prog is not None and prog.text == 'session_auth':
                score += 5
                feedback_parts.append("Program name match")
            
            # Check for regex extraction (rudimentary check)
            regex = target_decoder.find('regex')
            if regex is not None and 'user' in regex.text and 'src_ip' in regex.text:
                score += 5
                feedback_parts.append("Regex field extraction looks plausible")
                
            decoder_valid = True
        else:
            feedback_parts.append("Decoder 'bastion-session' NOT found in XML")

    except ET.ParseError:
        feedback_parts.append("XML Parse Error in local_decoder.xml")

    # Check Rules XML
    try:
        # Wrap in fake root
        if not rules_content.strip().startswith('<root>'):
            wrapped_rules = f"<root>{rules_content}</root>"
        else:
            wrapped_rules = rules_content
            
        root = ET.fromstring(wrapped_rules)
        
        rule_100010 = None
        rule_100011 = None
        
        for rule in root.findall(".//rule"):
            rid = rule.get('id')
            if rid == '100010':
                rule_100010 = rule
            elif rid == '100011':
                rule_100011 = rule
        
        if rule_100010 is not None:
            score += 10
            feedback_parts.append("Rule 100010 found")
            if rule_100010.get('level') == '8':
                score += 5
                feedback_parts.append("Rule 100010 level correct")
        else:
            feedback_parts.append("Rule 100010 NOT found")
            
        if rule_100011 is not None:
            score += 5
            feedback_parts.append("Rule 100011 found")
            
    except ET.ParseError:
        feedback_parts.append("XML Parse Error in local_rules.xml")


    # --- 3. Functional Verification (50 pts) ---
    # This is the most important part. Even if XML is ugly, if logtest works, it works.
    logtest_failed_out = result.get('logtest_output_failed', '')
    
    # Check Phase 2: Decoding
    if "decoder: 'bastion-session'" in logtest_failed_out:
        score += 20
        feedback_parts.append("Functional: Decoding successful")
        
        # Check field extraction in logtest output
        if "user: 'root'" in logtest_failed_out:
            score += 5
            feedback_parts.append("Functional: User field extracted")
    else:
        feedback_parts.append("Functional: Decoding FAILED (decoder not matched)")

    # Check Phase 3: Rule Matching
    if "id: '100010'" in logtest_failed_out:
        score += 25
        feedback_parts.append("Functional: Rule 100010 fired correctly")
    else:
        feedback_parts.append("Functional: Rule 100010 did NOT fire")

    # Bonus: Check success rule
    logtest_success_out = result.get('logtest_output_success', '')
    if "id: '100011'" in logtest_success_out:
        # Just confirmation, no extra points beyond max, but good for robust check
        feedback_parts.append("Functional: Rule 100011 fired correctly")


    # Final Pass/Fail Logic
    # Must have functional success (decoding + rule firing)
    functional_pass = ("decoder: 'bastion-session'" in logtest_failed_out) and \
                      ("id: '100010'" in logtest_failed_out)
    
    passed = functional_pass and (score >= 70)

    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback_parts)
    }