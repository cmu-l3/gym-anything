#!/usr/bin/env python3
import json
import re
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_configure_multiline_logs(traj, env_info, task_info):
    """
    Verify configure_multiline_logs task.
    
    Criteria:
    1. ossec.conf: <logall> set to 'yes' (20 pts)
    2. ossec.conf: <localfile> block exists for billing_app.log (20 pts)
    3. ossec.conf: <multiline_regex> is correctly configured (30 pts)
    4. Functional: Test log appears as a SINGLE event in archives.log (20 pts)
    5. Manager is running (10 pts)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result from container
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
    feedback = []
    
    ossec_conf = result.get('ossec_conf', '')
    archives_grep = result.get('archives_grep', '')
    test_id = result.get('test_id', 'UNKNOWN_ID')
    manager_running = result.get('manager_running', False)

    # 1. Check Manager Status (10 pts)
    if manager_running:
        score += 10
    else:
        feedback.append("Wazuh Manager is not running (configuration likely invalid).")

    # 2. Check logall (20 pts)
    # Regex for <logall>yes</logall> allowing for whitespace
    if re.search(r'<logall>\s*yes\s*</logall>', ossec_conf):
        score += 20
        feedback.append("Logall enabled.")
    else:
        feedback.append("Logall not enabled in ossec.conf.")

    # 3. Check localfile block (20 pts)
    # We look for a localfile block containing the specific location
    # This is a bit complex with regex on full XML, simplifying to checking if location exists inside a localfile tag
    # or just checking proximity.
    
    # Extract all localfile blocks
    localfile_blocks = re.findall(r'<localfile>(.*?)</localfile>', ossec_conf, re.DOTALL)
    billing_block = None
    for block in localfile_blocks:
        if '/var/log/billing_app.log' in block:
            billing_block = block
            break
            
    if billing_block:
        score += 20
        feedback.append("Localfile configuration found.")
    else:
        feedback.append("No <localfile> block found for /var/log/billing_app.log.")

    # 4. Check multiline_regex (30 pts)
    if billing_block:
        # Check for multiline_regex tag
        if '<multiline_regex' in billing_block:
            # Basic check for timestamp pattern (year-month-day)
            # Pattern in task: ^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}
            # User might interpret it differently, but needs to match 2023-11-15...
            if re.search(r'\d{4}.?\d{2}.?\d{2}', billing_block):
                score += 30
                feedback.append("Multiline regex configured.")
            else:
                score += 10 # Partial credit for tag existence
                feedback.append("Multiline regex tag found but pattern seems missing or simplistic.")
        else:
            feedback.append("Missing <multiline_regex> configuration.")

    # 5. Functional Verification (20 pts)
    # The injection was 3 lines.
    # If successful, Wazuh processes it as 1 event.
    # In archives.log, each event gets a header like "2023 Nov ... agent->file ...".
    # If split, we see the header 3 times (once per line).
    # If merged, we see the header 1 time.
    
    if test_id in archives_grep:
        # Count how many times the file path header appears in the grep output
        # The grep output includes the test_id line and 5 lines after.
        # Header usually contains "->/var/log/billing_app.log"
        header_marker = "->/var/log/billing_app.log"
        header_count = archives_grep.count(header_marker)
        
        # We expect exactly 1 header for the 3-line block if merged correctly
        # We allow lenient 1 or 0 (if header format is different but log is present)
        # But if it's > 1, it definitely failed to merge.
        
        if header_count == 1:
            score += 20
            feedback.append("Functional test passed: Log merged into single event.")
        elif header_count > 1:
            feedback.append(f"Functional test failed: Log split into {header_count} events (expected 1).")
        else:
            # Maybe header format is different, check if stack trace lines are present
            if "java.lang.NullPointerException" in archives_grep:
                score += 20
                feedback.append("Functional test passed (log present, header count ambiguous).")
            else:
                feedback.append("Functional test inconclusive: Log found but structure unclear.")
    else:
        feedback.append("Functional test failed: Test log not found in archives.log.")

    passed = (score >= 70)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }