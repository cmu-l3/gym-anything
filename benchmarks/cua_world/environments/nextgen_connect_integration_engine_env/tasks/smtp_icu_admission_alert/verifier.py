#!/usr/bin/env python3
"""
Verifier for smtp_icu_admission_alert task.
"""

import json
import tempfile
import os
import base64
import re

def verify_smtp_icu_admission_alert(traj, env_info, task_info):
    """
    Verifies the ICU Admission Alert task.
    
    Criteria:
    1. Channel Created (15 pts)
    2. Configuration Correctness (XML check) (35 pts)
       - Source: TCP Listener, Port 6661
       - Dest: SMTP Sender, Host mailhog, Port 1025
       - Filter logic exists
    3. Functional Success (50 pts)
       - ICU message -> Email received
       - Non-ICU message -> No email (Filter works)
    """
    
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load results
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
    
    # 1. Channel Existence (15 pts)
    if result.get('channel_found'):
        score += 15
        feedback.append("Channel with 'ICU' in name found.")
    else:
        feedback.append("No channel found with 'ICU' in the name.")
        return {"passed": False, "score": 0, "feedback": "\n".join(feedback)}

    # 2. Functional Testing (50 pts)
    func_test = result.get('functional_test', {})
    
    # Check if channel was started
    if result.get('channel_status') == "STARTED":
        feedback.append("Channel is deployed and running.")
    else:
        feedback.append(f"Channel status is {result.get('channel_status')} (Expected: STARTED).")
    
    # ICU Test
    if func_test.get('icu_email_received'):
        score += 25
        feedback.append("Functional Test Passed: ICU admission triggered an email.")
        
        # Check Subject/Body
        subject = func_test.get('icu_email_subject', '')
        body = func_test.get('icu_email_body_snippet', '')
        if "ICU Admission Alert" in subject:
             feedback.append("Email subject correct.")
        else:
             feedback.append(f"Warning: Email subject '{subject}' might be missing required text.")
             
        if "TESTPATIENT" in body:
             feedback.append("Email body contains patient name.")
        else:
             feedback.append("Warning: Email body might be missing patient name.")
             
    else:
        feedback.append("Functional Test Failed: ICU admission did NOT trigger an email.")

    # Filter Test
    if func_test.get('med_msg_sent'):
        if not func_test.get('med_email_received'):
            score += 25
            feedback.append("Filter Test Passed: Non-ICU admission did NOT trigger an email.")
        else:
            feedback.append("Filter Test Failed: Non-ICU admission triggered an email (Filter not working).")
    else:
        feedback.append("Could not perform filter test (Message send failed).")

    # 3. Configuration Check (XML Analysis) (35 pts)
    # Even if functional test passes, we want to ensure they used the right components 
    # (though functional success implies most config is right, strict port checks help).
    
    xml_b64 = result.get('channel_config_xml', '')
    if xml_b64:
        try:
            xml_str = base64.b64decode(xml_b64).decode('utf-8')
            
            # Check Source Port 6661
            if "<port>6661</port>" in xml_str:
                score += 10
                feedback.append("Config: Listening on port 6661.")
            else:
                feedback.append("Config: Port 6661 not found in XML.")
                
            # Check SMTP Host
            if "<smtpHost>mailhog</smtpHost>" in xml_str:
                score += 10
                feedback.append("Config: SMTP Host is 'mailhog'.")
            elif "mailhog" in xml_str:
                score += 5
                feedback.append("Config: 'mailhog' found in config.")
            else:
                feedback.append("Config: SMTP Host 'mailhog' not found.")
                
            # Check SMTP Port
            if "<smtpPort>1025</smtpPort>" in xml_str:
                score += 5
                feedback.append("Config: SMTP Port is 1025.")
            else:
                feedback.append("Config: SMTP Port 1025 not found.")

            # Check for Filter logic (Basic string check)
            if "PV1" in xml_str and "ICU" in xml_str:
                score += 10
                feedback.append("Config: Filter logic (PV1/ICU) appears to be present.")
            else:
                feedback.append("Config: Could not explicitly confirm filter logic in XML (but functional test rules).")
                
        except Exception as e:
            feedback.append(f"Error parsing config XML: {e}")

    # Final Score Calculation
    passed = score >= 60 and func_test.get('icu_email_received')
    
    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": "\n".join(feedback)
    }