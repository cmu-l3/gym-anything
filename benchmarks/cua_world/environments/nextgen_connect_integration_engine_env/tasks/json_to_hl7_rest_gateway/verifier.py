#!/usr/bin/env python3
"""
Verifier for json_to_hl7_rest_gateway task.
Checks:
1. Channel existence and status.
2. HTTP Listener port availability.
3. Functional correctness:
   - Acceptance of JSON payload (HTTP 200).
   - Creation of output file.
   - Content of HL7 file (MSH, PID, PV1 segments mapping).
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def parse_hl7_message(hl7_text):
    """Parses a basic HL7 string into a dictionary of segments."""
    segments = {}
    if not hl7_text:
        return segments
        
    lines = hl7_text.strip().split('\r')
    if len(lines) == 1: # Try newline if \r didn't split
        lines = hl7_text.strip().split('\n')
        
    for line in lines:
        parts = line.split('|')
        if not parts:
            continue
        seg_name = parts[0]
        segments[seg_name] = parts
    return segments

def get_field(segment, index):
    """Safely gets a field from a segment array (1-based index)."""
    # HL7 fields are 1-based. In the split array:
    # Segments like MSH are special because the delimiter counts as a field.
    # Standard: MSH|^~\&|SendingApp...
    # split('|'): ['MSH', '^~\&', 'SendingApp'...]
    # MSH-1 is the delimiter '|' (implied)
    # MSH-2 is '^~\&' (index 1 in split)
    # MSH-3 is 'SendingApp' (index 2 in split)
    
    # For PID/PV1:
    # PID|1|...
    # split: ['PID', '1', ...]
    # PID-1 is index 1.
    
    if not segment:
        return None
    
    # Adjust for MSH special case if needed, but usually index matches split index for MSH-3+ 
    # MSH-1 (field sep) -> not in split
    # MSH-2 (encoding chars) -> index 1
    # MSH-3 -> index 2
    
    if segment[0] == 'MSH':
        # MSH fields are shifted by 1 compared to standard list access because field separator is implied
        # MSH-3 is at index 2
        if index == 1: return '|'
        if index == 2: return segment[1] if len(segment) > 1 else ''
        actual_index = index - 1
        return segment[actual_index] if len(segment) > actual_index else ''
    else:
        return segment[index] if len(segment) > index else ''

def verify_json_to_hl7_rest_gateway(traj, env_info, task_info):
    """
    Verifies the JSON to HL7 REST Gateway task.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_values = metadata.get('expected_hl7_values', {})

    # Copy result file
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    score = 0
    feedback_parts = []
    
    # 1. Channel Status (30 points)
    channel_exists = result.get('channel_exists', False)
    channel_status = result.get('channel_status', 'UNKNOWN')
    port_open = result.get('port_6661_open', False)
    
    if channel_exists:
        score += 10
        feedback_parts.append(f"Channel '{result.get('channel_name')}' exists.")
        
        if channel_status in ['STARTED', 'DEPLOYED']:
            score += 10
            feedback_parts.append("Channel is deployed/started.")
        else:
            feedback_parts.append(f"Channel status is {channel_status} (expected STARTED).")
            
        if port_open:
            score += 10
            feedback_parts.append("Port 6661 is open and listening.")
        else:
            feedback_parts.append("Port 6661 is NOT listening.")
    else:
        feedback_parts.append("Channel not found.")
        return {"passed": False, "score": 0, "feedback": "\n".join(feedback_parts)}

    # 2. HTTP Interaction (20 points)
    http_code = result.get('http_response_code', '000')
    if str(http_code).startswith('2'):
        score += 20
        feedback_parts.append(f"HTTP POST accepted (Code {http_code}).")
    else:
        feedback_parts.append(f"HTTP POST failed or rejected (Code {http_code}).")

    # 3. Output File Creation (10 points)
    if result.get('functional_test_file_created', False):
        score += 10
        feedback_parts.append("Output HL7 file was created.")
    else:
        feedback_parts.append("No output file created during test.")

    # 4. HL7 Content Verification (40 points)
    hl7_content = result.get('output_content', '')
    if hl7_content:
        segments = parse_hl7_message(hl7_content)
        
        # Check MSH-9 (Message Type)
        msh = segments.get('MSH')
        if msh:
            msh_9 = get_field(msh, 9)
            if 'ADT' in msh_9 and 'A04' in msh_9:
                score += 10
                feedback_parts.append(f"MSH-9 correct: {msh_9}")
            else:
                feedback_parts.append(f"MSH-9 incorrect: got '{msh_9}', expected ADT^A04")
        else:
            feedback_parts.append("Missing MSH segment.")

        # Check PID-3 (MRN)
        pid = segments.get('PID')
        if pid:
            pid_3 = get_field(pid, 3)
            expected_mrn = expected_values.get('PID.3', 'MRN-TEST-999')
            if expected_mrn in pid_3:
                score += 10
                feedback_parts.append(f"PID-3 (MRN) correct: {pid_3}")
            else:
                feedback_parts.append(f"PID-3 mismatch: got '{pid_3}', expected '{expected_mrn}'")
            
            # Check PID-5 (Name)
            pid_5 = get_field(pid, 5)
            expected_name = expected_values.get('PID.5', 'Verify^Agent')
            if expected_name in pid_5:
                score += 10
                feedback_parts.append(f"PID-5 (Name) correct: {pid_5}")
            else:
                feedback_parts.append(f"PID-5 mismatch: got '{pid_5}', expected '{expected_name}'")
        else:
            feedback_parts.append("Missing PID segment.")

        # Check PV1-19 (Visit Number)
        pv1 = segments.get('PV1')
        if pv1:
            pv1_19 = get_field(pv1, 19)
            expected_visit = expected_values.get('PV1.19', 'V-TEST-999')
            if expected_visit in pv1_19:
                score += 10
                feedback_parts.append(f"PV1-19 (Visit) correct: {pv1_19}")
            else:
                feedback_parts.append(f"PV1-19 mismatch: got '{pv1_19}', expected '{expected_visit}'")
        else:
            feedback_parts.append("Missing PV1 segment.")
    else:
        feedback_parts.append("No HL7 content to verify.")

    # Final Pass Check
    # Need at least 60 points AND functional success
    functional_success = str(http_code).startswith('2') and result.get('functional_test_file_created', False)
    passed = score >= 60 and functional_success

    return {
        "passed": passed,
        "score": score,
        "feedback": "\n".join(feedback_parts)
    }