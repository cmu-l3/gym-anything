#!/usr/bin/env python3
"""
Verifier for XML to HL7 Lab Transformation task.
Verifies channel creation, status, and most importantly, the structure of the generated HL7 message.
"""

import json
import base64
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_xml_to_hl7_lab_transformation(traj, env_info, task_info):
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
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # Metadata expectations
    metadata = task_info.get('metadata', {})
    expected_analyte_count = metadata.get('expected_analyte_count', 5)
    expected_patient_name = metadata.get('expected_patient_name', 'SMITH^JENNIFER')
    analyte_check = metadata.get('analyte_check', {"name": "WBC", "value": "7.2"})

    score = 0
    feedback = []

    # 1. Channel Status (20 pts)
    if result.get('channel_found'):
        score += 10
        feedback.append("Channel 'XML_to_HL7_Lab' created.")
        status = result.get('channel_status', 'UNKNOWN')
        if status in ['STARTED', 'DEPLOYED']:
            score += 10
            feedback.append(f"Channel is in {status} state.")
        else:
            feedback.append(f"Channel state is {status} (expected STARTED).")
    else:
        feedback.append("Channel 'XML_to_HL7_Lab' not found.")

    # 2. Output File Existence (20 pts)
    hl7_content = ""
    if result.get('output_file_exists'):
        score += 20
        feedback.append(f"Output file {result.get('output_filename')} generated.")
        
        # Decode content
        try:
            b64_content = result.get('output_content_b64', '')
            hl7_content = base64.b64decode(b64_content).decode('utf-8', errors='ignore')
        except Exception as e:
            feedback.append(f"Error decoding output file: {e}")
    else:
        feedback.append("No output file generated in /opt/mirthdata/hl7_out/.")

    # 3. Content Verification (60 pts)
    if hl7_content:
        # Split into segments (handle \r or \n)
        segments = [s.strip() for s in hl7_content.replace('\r', '\n').split('\n') if s.strip()]
        
        # Check Segment Types
        has_msh = any(s.startswith('MSH') for s in segments)
        has_pid = any(s.startswith('PID') for s in segments)
        has_obr = any(s.startswith('OBR') for s in segments)
        
        obx_segments = [s for s in segments if s.startswith('OBX')]
        obx_count = len(obx_segments)

        # Header/PID check (10 pts)
        if has_msh and has_pid and has_obr:
            score += 10
            feedback.append("Valid HL7 structure (MSH, PID, OBR found).")
        else:
            feedback.append("Missing required segments (MSH/PID/OBR).")

        # Patient Name Check (10 pts)
        # Simple check if expected name string exists in PID
        if any(expected_patient_name in s for s in segments if s.startswith('PID')):
            score += 10
            feedback.append(f"Patient name {expected_patient_name} found.")
        else:
            feedback.append(f"Patient name {expected_patient_name} not found in PID.")

        # Loop Logic / OBX Count (20 pts)
        if obx_count == expected_analyte_count:
            score += 20
            feedback.append(f"Correct number of OBX segments found ({obx_count}).")
        elif obx_count > 0:
            score += 10
            feedback.append(f"Found {obx_count} OBX segments, expected {expected_analyte_count}.")
        else:
            feedback.append("No OBX segments found.")

        # Analyte Value Check (20 pts)
        # Check if specific values mapped correctly (e.g. WBC|7.2)
        # HL7 pipe delimited: OBX|1|NM|WBC^...|...|7.2|...
        target_name = analyte_check.get('name')
        target_val = analyte_check.get('value')
        
        found_analyte = False
        for obx in obx_segments:
            parts = obx.split('|')
            # Look for Name (field 3) and Value (field 5) approximately
            # This is loose matching to account for varying agent mapping styles
            if len(parts) > 5 and target_name in parts[3] and target_val in parts[5]:
                found_analyte = True
                break
        
        if found_analyte:
            score += 20
            feedback.append(f"Analyte data ({target_name}={target_val}) mapped correctly.")
        else:
            feedback.append(f"Could not verify mapping for {target_name}={target_val}.")

    return {
        "passed": score >= 70,
        "score": score,
        "feedback": " ".join(feedback)
    }