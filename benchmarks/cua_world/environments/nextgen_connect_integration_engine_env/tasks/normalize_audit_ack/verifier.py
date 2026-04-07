#!/usr/bin/env python3
"""
Verifier for normalize_audit_ack task.

Tests:
1. Network Logic: Sends HL7 message to port 6661, verifies response has "Processed Successfully".
2. Audit Logic: Verifies /home/ga/ack_audit.log contains the RAW (defective) ACK.
"""

import json
import os
import socket
import time
import base64
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def send_mllp_message(host, port, hl7_data, timeout=5):
    """Send HL7 message via MLLP and return response."""
    SB = b'\x0b'
    EB = b'\x1c'
    CR = b'\x0d'
    
    try:
        with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
            s.settimeout(timeout)
            s.connect((host, port))
            
            # Wrap in MLLP
            msg = SB + hl7_data.encode('utf-8') + EB + CR
            s.sendall(msg)
            
            # Receive response
            received = b""
            while True:
                chunk = s.recv(1024)
                if not chunk:
                    break
                received += chunk
                if EB in received and CR in received:
                    break
            
            # Unwrap MLLP
            resp_str = received.decode('utf-8', errors='ignore')
            resp_str = resp_str.strip(SB.decode()).strip(EB.decode()).strip(CR.decode())
            return resp_str
    except Exception as e:
        logger.error(f"MLLP Send Error: {e}")
        return None

def verify_normalize_audit_ack(traj, env_info, task_info):
    """
    Verify the channel normalizes ACKs and audits raw ACKs.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Load JSON result from export
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read export result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # Check 1: Channel Deployed (10 pts)
    if result.get("channel_deployed", False):
        score += 10
        feedback_parts.append("Channel is deployed.")
    else:
        feedback_parts.append("Channel is NOT deployed.")

    # Check 2: Network Verification (50 pts)
    # We attempt to send a message to localhost:6661 (mapped from container)
    # The Mock LIS inside container is on 6662.
    # Flow: Verifier -> 6661 (Agent Channel) -> 6662 (Mock LIS)
    #       Verifier <- "Normalized ACK" <- Agent Channel <- "Defective ACK" <- Mock LIS
    
    test_ctrl_id = f"VERIFY{int(time.time())}"
    test_msg = f"MSH|^~\\&|VERIFIER|TEST|||{time.strftime('%Y%m%d%H%M%S')}||ADT^A01|{test_ctrl_id}|P|2.5.1\rEVN|A01|{time.strftime('%Y%m%d%H%M%S')}"
    
    # Attempt connection (allow for port mapping config in framework)
    # Typically framework maps 6661->6661 on localhost.
    host = "localhost" 
    port = 6661
    
    response = send_mllp_message(host, port, test_msg)
    
    normalization_passed = False
    
    if response:
        feedback_parts.append("Received response from channel.")
        # Check MSA segment
        # Expected: MSA|AA|VERIFY...|Processed Successfully
        if f"|AA|{test_ctrl_id}|Processed Successfully" in response:
            score += 30
            normalization_passed = True
            feedback_parts.append("Success: ACK normalized with 'Processed Successfully'.")
        elif f"|AA|{test_ctrl_id}|" in response:
            # Matches the defective one (agent didn't fix it)
            feedback_parts.append("Fail: ACK received was still defective (missing text).")
        else:
            feedback_parts.append(f"Fail: Unexpected ACK format. Received: {response}")
            
        # Optional: Test Error Case (if agent implemented it)
        # error_msg = test_msg.replace(test_ctrl_id, "ERR" + test_ctrl_id)
        # err_resp = send_mllp_message(host, port, error_msg)
        # if err_resp and "Remote Error" in err_resp:
        #    score += 20
        #    feedback_parts.append("Success: Error ACK normalized correctly.")
        # else:
        #    # We bundle the score into the main one for simplicity, or add bonus
        #    pass
        
        # We'll just give remaining points for general message flow if normalization passed
        if normalization_passed:
            score += 20 # Full network points
    else:
        feedback_parts.append("Fail: No response received from port 6661 (Channel might not be listening or routing failed).")

    # Check 3: Audit Log Verification (40 pts)
    # We need to re-fetch the log file content NOW, after we sent our test message.
    # The export_result.sh ran BEFORE we sent the test message in this python script.
    # So we must use copy_from_env to grab the log again.
    
    log_temp = tempfile.NamedTemporaryFile(delete=False, suffix='.log')
    try:
        copy_from_env("/home/ga/ack_audit.log", log_temp.name)
        with open(log_temp.name, 'r') as f:
            log_content = f.read()
            
        if log_content:
            feedback_parts.append("Audit log file found.")
            # We look for the RAW defective ACK for our specific message
            # The Mock LIS sends: MSA|AA|{test_ctrl_id}|
            expected_raw_entry = f"|AA|{test_ctrl_id}|"
            
            # Also check that it DOES NOT contain "Processed Successfully" (should be raw)
            if expected_raw_entry in log_content:
                if f"|AA|{test_ctrl_id}|Processed Successfully" not in log_content:
                    score += 40
                    feedback_parts.append("Success: Audit log contains RAW defective ACK (unmodified).")
                else:
                    score += 20
                    feedback_parts.append("Partial: Audit log contains the ACK, but it appears to be the normalized version (should be raw).")
            else:
                feedback_parts.append("Fail: Test message ACK not found in audit log.")
        else:
            feedback_parts.append("Fail: Audit log is empty.")
    except Exception as e:
        feedback_parts.append("Fail: Could not retrieve audit log (file may not exist).")
    finally:
        if os.path.exists(log_temp.name):
            os.unlink(log_temp.name)

    passed = score >= 80
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }