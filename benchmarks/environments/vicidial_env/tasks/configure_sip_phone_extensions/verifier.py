#!/usr/bin/env python3
"""
Verifier for configure_sip_phone_extensions task.
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_configure_sip_phone_extensions(traj, env_info, task_info):
    """
    Verify that two SIP phone extensions were correctly configured in Vicidial.
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
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    max_score = 100
    feedback_parts = []
    
    # Extract data
    actual_server_ip = result.get('actual_server_ip', '')
    phone_8501 = result.get('phone_8501')
    phone_8502 = result.get('phone_8502')
    initial_count = int(result.get('initial_phone_count', 0))
    final_count = int(result.get('final_phone_count', 0))

    # --- Verify Phone 8501 (45 points) ---
    if phone_8501:
        score += 8
        feedback_parts.append("Phone 8501 exists (+8)")
        
        # Credentials
        if phone_8501.get('login') == 'cc_remote_8501' and phone_8501.get('pass') == 'Xk9mPw2nQ':
            score += 10
            feedback_parts.append("P1 creds OK (+10)")
        else:
            feedback_parts.append(f"P1 creds wrong: {phone_8501.get('login')}/{phone_8501.get('pass')}")

        # SIP Config
        p1_proto = phone_8501.get('protocol')
        p1_ip = phone_8501.get('server_ip')
        if p1_proto == 'SIP' and p1_ip == actual_server_ip:
            score += 10
            feedback_parts.append("P1 SIP/Server OK (+10)")
        else:
            feedback_parts.append(f"P1 SIP mismatch: {p1_proto} on {p1_ip} (expected {actual_server_ip})")

        # Dialplan/Voicemail
        if phone_8501.get('dialplan_number') == '8501' and phone_8501.get('voicemail_id') == '8501':
            score += 5
            feedback_parts.append("P1 Dialplan OK (+5)")
            
        # Timezone & Metadata
        # GMT can be "-5.00" or "-5" depending on DB storage
        gmt = str(phone_8501.get('local_gmt', ''))
        if gmt.startswith("-5"):
            score += 5
            feedback_parts.append("P1 GMT OK (+5)")
        else:
            feedback_parts.append(f"P1 GMT wrong ({gmt})")
            
        if phone_8501.get('active') == 'Y':
            score += 7
            feedback_parts.append("P1 Active (+7)")
    else:
        feedback_parts.append("Phone 8501 MISSING")

    # --- Verify Phone 8502 (45 points) ---
    if phone_8502:
        score += 8
        feedback_parts.append("Phone 8502 exists (+8)")
        
        # Credentials
        if phone_8502.get('login') == 'cc_remote_8502' and phone_8502.get('pass') == 'Qr7nLv4bZ':
            score += 10
            feedback_parts.append("P2 creds OK (+10)")
        else:
            feedback_parts.append(f"P2 creds wrong")

        # SIP Config
        p2_proto = phone_8502.get('protocol')
        p2_ip = phone_8502.get('server_ip')
        if p2_proto == 'SIP' and p2_ip == actual_server_ip:
            score += 10
            feedback_parts.append("P2 SIP/Server OK (+10)")
        else:
            feedback_parts.append(f"P2 SIP mismatch")

        # Dialplan/Voicemail
        if phone_8502.get('dialplan_number') == '8502' and phone_8502.get('voicemail_id') == '8502':
            score += 5
            feedback_parts.append("P2 Dialplan OK (+5)")
            
        # Timezone
        gmt = str(phone_8502.get('local_gmt', ''))
        if gmt.startswith("-6"):
            score += 5
            feedback_parts.append("P2 GMT OK (+5)")
        else:
            feedback_parts.append(f"P2 GMT wrong ({gmt})")
            
        if phone_8502.get('active') == 'Y':
            score += 7
            feedback_parts.append("P2 Active (+7)")
    else:
        feedback_parts.append("Phone 8502 MISSING")

    # --- Anti-Gaming (10 points) ---
    # Check that records were actually added
    if final_count >= initial_count + 2:
        score += 5
        feedback_parts.append("Count increased (+5)")
    
    # Check distinct configurations
    if phone_8501 and phone_8502:
        distinct = (phone_8501.get('login') != phone_8502.get('login') and 
                    phone_8501.get('local_gmt') != phone_8502.get('local_gmt'))
        if distinct:
            score += 5
            feedback_parts.append("Configs distinct (+5)")
        else:
            feedback_parts.append("Configs identical (possible copy/paste)")

    passed = score >= 60
    
    # Ensure key criteria for passing
    if passed and (not phone_8501 or not phone_8502):
        passed = False
        feedback_parts.append("FAIL: Both phones must exist")

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }