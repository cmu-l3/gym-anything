#!/usr/bin/env python3
"""
Verifier for hl7_repeating_segments_to_json task.

Strategy:
1. ACTIVE PROBE: Send a unique HL7 message with repeating NK1 segments to localhost:6661.
2. FILE CHECK: Retrieve the resulting JSON file from the container.
3. VALIDATION: Check JSON structure, correct iteration of contacts, and name formatting.
4. STATIC CHECK: Fallback to checking if the agent ran the sample test if active probe fails (lower score).
"""

import json
import socket
import time
import os
import random
import string
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def generate_id():
    """Generate a random patient ID."""
    return 'TEST' + ''.join(random.choices(string.digits, k=6))

def generate_hl7(patient_id, contacts):
    """Generate an HL7 ADT message with multiple NK1 segments."""
    timestamp = time.strftime("%Y%m%d%H%M%S")
    
    # Header & PID
    msg = f"MSH|^~\\&|TEST|VERIFY|CONNECT|PORTAL|{timestamp}||ADT^A01|{timestamp}|P|2.3\r"
    msg += f"EVN|A01|{timestamp}\r"
    msg += f"PID|1||{patient_id}^^^MRN||TEST^PATIENT||19800101|M\r"
    
    # Repeating NK1 Segments
    for idx, contact in enumerate(contacts, 1):
        # Format: NK1|1|Last^First|Rel
        msg += f"NK1|{idx}|{contact['family']}^{contact['given']}|{contact['rel']}\r"
        
    msg += f"PV1|1|I|LOC^101\r"
    return msg

def send_mllp(host, port, message):
    """Send message via MLLP protocol."""
    try:
        # MLLP Framing: <VT> message <FS><CR>
        # VT = 0x0b, FS = 0x1c, CR = 0x0d
        framed_msg = b'\x0b' + message.encode('utf-8') + b'\x1c\x0d'
        
        with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
            s.settimeout(5)
            s.connect((host, port))
            s.sendall(framed_msg)
            # Expect ACK (we don't strictly validate the ACK content, just that we got one)
            response = s.recv(1024)
            return True
    except Exception as e:
        logger.error(f"Failed to send MLLP message: {e}")
        return False

def verify_hl7_repeating_segments_to_json(traj, env_info, task_info):
    """
    Verify the task by injecting a message and checking the output file.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Read static export result (to check if channel exists/port open)
    temp_result_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    static_result = {}
    try:
        copy_from_env("/tmp/task_result.json", temp_result_file.name)
        with open(temp_result_file.name, 'r') as f:
            static_result = json.load(f)
    except Exception as e:
        logger.warning(f"Could not read static task result: {e}")
    finally:
        if os.path.exists(temp_result_file.name):
            os.unlink(temp_result_file.name)

    score = 0
    feedback_parts = []
    
    # Basic Checks from Static Analysis
    if static_result.get("channel_exists", False):
        score += 10
        feedback_parts.append("Channel 'NK1_to_JSON' created")
    else:
        feedback_parts.append("Channel 'NK1_to_JSON' NOT found")

    if static_result.get("port_6661_open", False):
        score += 10
        feedback_parts.append("Port 6661 is open")
    else:
        feedback_parts.append("Port 6661 is NOT listening")
        # If port is closed, active probe will fail, but we continue just in case

    # 2. ACTIVE PROBE
    patient_id = generate_id()
    contacts = [
        {"family": "Smith", "given": "John", "rel": "FTH"},
        {"family": "Doe", "given": "Jane", "rel": "MTH"},
        {"family": "Black", "given": "Jack", "rel": "BRO"}
    ]
    
    logger.info(f"Sending probe message for Patient {patient_id} with 3 contacts...")
    
    sent_success = send_mllp("localhost", 6661, generate_hl7(patient_id, contacts))
    
    if sent_success:
        score += 10
        feedback_parts.append("Successfully connected and sent HL7 message")
        
        # Wait for processing
        time.sleep(3)
        
        # Retrieve output file
        expected_filename = f"{patient_id}_contacts.json"
        remote_path = f"/home/ga/json_out/{expected_filename}"
        local_path = tempfile.mktemp(suffix=".json")
        
        try:
            copy_from_env(remote_path, local_path)
            
            if os.path.exists(local_path):
                score += 20
                feedback_parts.append("Output JSON file created")
                
                # Parse and Validate JSON
                try:
                    with open(local_path, 'r') as f:
                        data = json.load(f)
                    
                    # Validate Patient ID
                    if data.get("patientId") == patient_id:
                        score += 10
                        feedback_parts.append("Patient ID matches")
                    else:
                        feedback_parts.append(f"Patient ID mismatch: expected {patient_id}, got {data.get('patientId')}")
                    
                    # Validate Contacts Array
                    json_contacts = data.get("contacts", [])
                    if isinstance(json_contacts, list) and len(json_contacts) == 3:
                        score += 20
                        feedback_parts.append("Contacts array correct length (iteration working)")
                        
                        # Validate Content/Formatting
                        valid_mapping = True
                        for i, expected in enumerate(contacts):
                            actual = json_contacts[i]
                            expected_name = f"{expected['family']}, {expected['given']}"
                            
                            if actual.get("name") != expected_name:
                                valid_mapping = False
                                feedback_parts.append(f"Name formatting error: expected '{expected_name}', got '{actual.get('name')}'")
                            
                            if actual.get("relationship") != expected["rel"]:
                                valid_mapping = False
                                feedback_parts.append(f"Relationship error: expected '{expected['rel']}', got '{actual.get('relationship')}'")
                        
                        if valid_mapping:
                            score += 20
                            feedback_parts.append("Data mapping & name formatting correct")
                        
                    else:
                        feedback_parts.append(f"Contacts array invalid or wrong length: got {len(json_contacts) if isinstance(json_contacts, list) else 'type mismatch'}")
                        
                except json.JSONDecodeError:
                    feedback_parts.append("Output file is NOT valid JSON")
                finally:
                    os.unlink(local_path)
            else:
                feedback_parts.append("Output file was NOT created after sending message")
        except Exception as e:
            feedback_parts.append(f"Failed to retrieve output file: {e}")
            
    else:
        feedback_parts.append("Failed to send HL7 message (port closed or firewall?)")
        
        # Fallback: check if they ran the sample test themselves
        if static_result.get("sample_test_file_exists", False):
            score += 10
            feedback_parts.append("PARTIAL CREDIT: Sample output file found (agent ran test manually)")
            # Analyze sample content if available
            try:
                sample_json = json.loads(static_result.get("latest_file_content", "{}"))
                if sample_json.get("contacts") and len(sample_json["contacts"]) == 3:
                    score += 10
                    feedback_parts.append("PARTIAL CREDIT: Sample output looks structurally correct")
            except:
                pass

    passed = score >= 80
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }