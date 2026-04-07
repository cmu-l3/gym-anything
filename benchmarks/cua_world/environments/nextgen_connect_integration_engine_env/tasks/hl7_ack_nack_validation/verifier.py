#!/usr/bin/env python3
"""
Verifier for HL7 ACK/NACK Validation Task.

Verification Strategy:
1. Static Analysis (from export_result.sh):
   - Check channel existence, name, port, status.
2. Active Functional Testing (performed here):
   - Connect to localhost:6661 (mapped container port).
   - Send VALID message -> Expect ACK (AA).
   - Send INVALID message -> Expect ACK (AE).
3. Evidence Checks:
   - File output count.
"""

import json
import socket
import time
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# MLLP Constants
SB = b'\x0b'
EB = b'\x1c'
CR = b'\x0d'

def send_mllp_message(host, port, hl7_data, timeout=5):
    """Send HL7 message via MLLP and return response."""
    try:
        with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
            s.settimeout(timeout)
            s.connect((host, port))
            
            # Wrap in MLLP
            msg = SB + hl7_data.encode('utf-8') + EB + CR
            s.sendall(msg)
            
            # Receive response
            response = b""
            while True:
                chunk = s.recv(1024)
                if not chunk:
                    break
                response += chunk
                if EB + CR in response:
                    break
            
            # Unwrap MLLP
            if response.startswith(SB):
                response = response[1:]
            if response.endswith(EB + CR):
                response = response[:-2]
                
            return response.decode('utf-8')
    except Exception as e:
        logger.error(f"MLLP connection failed: {e}")
        return None

def verify_hl7_ack_nack_validation(traj, env_info, task_info):
    """Verify ADT Validator channel functionality."""
    
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Retrieve Static Analysis Result
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)
            
    score = 0
    feedback_parts = []
    
    # --- Static Checks (40 Points) ---
    
    # Channel Exists (10)
    if result.get("channel_exists", False):
        score += 10
        feedback_parts.append("Channel 'ADT_Inbound_Validator' exists.")
    else:
        feedback_parts.append("Channel 'ADT_Inbound_Validator' NOT found.")
        return {"passed": False, "score": 0, "feedback": "\n".join(feedback_parts)}
        
    # Port Correct (10)
    port = result.get("listening_port", "")
    if str(port) == "6661":
        score += 10
        feedback_parts.append("Listening on port 6661.")
    else:
        feedback_parts.append(f"Incorrect port: {port} (Expected 6661).")
        
    # Status Started (10)
    status = result.get("channel_status", "").upper()
    if status in ["STARTED", "RUNNING"]:
        score += 10
        feedback_parts.append("Channel is STARTED.")
    else:
        feedback_parts.append(f"Channel status is {status} (Expected STARTED).")

    # Source Type (10)
    if result.get("source_type") == "TCP Listener":
        score += 10
        feedback_parts.append("Source connector is TCP Listener.")
    else:
        feedback_parts.append("Source connector is NOT TCP Listener.")

    # --- Active Functional Testing (60 Points) ---
    # Attempt to connect to localhost:6661 (Container port mapped to host)
    
    # Test Data
    timestamp = time.strftime("%Y%m%d%H%M%S")
    valid_msg = f"MSH|^~\\&|SEND|FAC|REC|FAC|{timestamp}||ADT^A04|MSG001|P|2.3\rPID|||12345^^^MRN||Doe^John"
    invalid_msg_no_pid3 = f"MSH|^~\\&|SEND|FAC|REC|FAC|{timestamp}||ADT^A04|MSG002|P|2.3\rPID|||||Doe^John"
    invalid_msg_no_pid5 = f"MSH|^~\\&|SEND|FAC|REC|FAC|{timestamp}||ADT^A04|MSG003|P|2.3\rPID|||12345^^^MRN||"

    try:
        # Test 1: Valid Message (Expect AA) (20 pts)
        resp_valid = send_mllp_message("localhost", 6661, valid_msg)
        if resp_valid and "MSA|AA" in resp_valid:
            score += 20
            feedback_parts.append("Valid message received correct ACK (AA).")
        else:
            feedback_parts.append(f"Valid message failed. Response: {resp_valid[:50] if resp_valid else 'None'}")
            
        # Test 2: Invalid Message (Expect AE) (20 pts)
        resp_invalid = send_mllp_message("localhost", 6661, invalid_msg_no_pid3)
        # Accept AE (Application Error) or AR (Application Reject)
        if resp_invalid and ("MSA|AE" in resp_invalid or "MSA|AR" in resp_invalid):
            score += 20
            feedback_parts.append("Invalid message received correct NACK (AE).")
        else:
            feedback_parts.append(f"Invalid message failed validation check. Response: {resp_invalid[:50] if resp_invalid else 'None'}")
            
    except Exception as e:
        feedback_parts.append(f"Functional testing failed: {e}")

    # Output File Check (20 pts)
    # We expect at least the valid message to be written
    if result.get("output_file_count", 0) > 0:
        score += 20
        feedback_parts.append("Output files detected.")
    else:
        feedback_parts.append("No output files written.")

    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": "\n".join(feedback_parts)
    }