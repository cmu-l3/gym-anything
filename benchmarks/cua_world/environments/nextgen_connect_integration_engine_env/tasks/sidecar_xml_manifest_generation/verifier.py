#!/usr/bin/env python3
"""
Verifier for sidecar_xml_manifest_generation task.
"""

import json
import tempfile
import os
import re

def verify_sidecar_xml_manifest(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_pid = metadata.get('expected_patient_id', '12345')
    expected_name = metadata.get('expected_patient_name', 'Doe John')
    expected_iso_date = metadata.get('expected_iso_date', '2023-01-01T12:00:00')

    # Copy result
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
    feedback_parts = []
    
    # 1. Channel Exists & Status (10 pts)
    if result.get('channel_found'):
        status = result.get('channel_status', '').lower()
        if status in ['started', 'deployed', 'running']:
            score += 10
            feedback_parts.append("Channel deployed and running.")
        else:
            score += 5
            feedback_parts.append(f"Channel found but status is '{status}'.")
    else:
        feedback_parts.append("Channel not found.")

    # 2. HL7 File Creation (15 pts)
    hl7_filename = result.get('hl7_filename', '')
    if result.get('hl7_file_exists') and hl7_filename:
        score += 15
        feedback_parts.append("HL7 output file created.")
    else:
        feedback_parts.append("HL7 output file NOT created.")

    # 3. XML File Creation (15 pts)
    xml_filename = result.get('xml_filename', '')
    if result.get('xml_file_exists') and xml_filename:
        score += 15
        feedback_parts.append("XML output file created.")
    else:
        feedback_parts.append("XML output file NOT created.")

    # 4. Filename Matching Pattern (10 pts)
    # Check if they share the same base ID (e.g. adt-1.hl7 and adt-1.xml)
    if hl7_filename and xml_filename:
        base_hl7 = os.path.splitext(hl7_filename)[0]
        base_xml = os.path.splitext(xml_filename)[0]
        if base_hl7 == base_xml:
            score += 10
            feedback_parts.append(f"Filenames match pattern: {base_hl7}")
        else:
            feedback_parts.append(f"Filename mismatch: {hl7_filename} vs {xml_filename}")
    
    # 5. XML Validation & Data Extraction (40 pts total)
    if result.get('xml_valid'):
        score += 10 # Basic valid XML
        
        # Check Patient Data (10 pts)
        parsed_pid = result.get('parsed_pid', '')
        parsed_name = result.get('parsed_name', '')
        if parsed_pid == expected_pid and parsed_name == expected_name:
            score += 10
            feedback_parts.append("XML Metadata: Patient ID/Name correct.")
        else:
            feedback_parts.append(f"XML Metadata mismatch: Expected '{expected_pid}'/'{expected_name}', Got '{parsed_pid}'/'{parsed_name}'")

        # Check Date Format (ISO 8601) (20 pts)
        parsed_date = result.get('parsed_date', '')
        # Allow exact match or standard ISO variations (e.g. milliseconds)
        # Expected: 2023-01-01T12:00:00
        # Regex for YYYY-MM-DDTHH:MM:SS
        if parsed_date == expected_iso_date:
            score += 20
            feedback_parts.append("XML Metadata: Date conversion correct (Exact match).")
        elif re.match(r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}', parsed_date):
            score += 20
            feedback_parts.append("XML Metadata: Date format appears to be valid ISO 8601.")
        else:
            feedback_parts.append(f"XML Metadata: Date conversion failed. Got '{parsed_date}'")

        # Check File Reference (10 pts)
        parsed_ref = result.get('parsed_file_ref', '')
        if parsed_ref and parsed_ref == hl7_filename:
            score += 10
            feedback_parts.append("XML Metadata: <OriginalFile> reference correct.")
        else:
            feedback_parts.append(f"XML Metadata: <OriginalFile> incorrect. Expected '{hl7_filename}', Got '{parsed_ref}'")
            
    else:
        feedback_parts.append("XML file was not valid or empty.")

    return {
        "passed": score >= 70,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }