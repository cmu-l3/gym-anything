#!/usr/bin/env python3
"""
Verifier for HL7 ADT Message Generation Task.
Parses the generated HL7 file and validates against database records.
"""

import json
import os
import tempfile
import logging
import re

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def parse_hl7_message(raw_msg):
    """Parse a raw HL7 message string into a dict of segments."""
    segments = {}
    lines = raw_msg.strip().split('\n')
    for line in lines:
        line = line.strip()
        if not line:
            continue
        fields = line.split('|')
        seg_name = fields[0]
        # Store as list of lists (segments can repeat, but for this task we assume 1 per type usually)
        if seg_name not in segments:
            segments[seg_name] = []
        segments[seg_name].append(fields)
    return segments

def verify_hl7_generation(traj, env_info, task_info):
    """
    Verify the generated HL7 file.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    required_patients = metadata.get('required_patients', [])
    
    # Load task result metadata
    result_json_path = "/tmp/task_result.json"
    local_result_json = tempfile.mktemp()
    
    try:
        copy_from_env(result_json_path, local_result_json)
        with open(local_result_json, 'r') as f:
            task_result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load task result JSON: {e}"}
    finally:
        if os.path.exists(local_result_json):
            os.remove(local_result_json)

    # Check basic file existence requirements
    if not task_result.get('output_exists', False):
        return {"passed": False, "score": 0, "feedback": "Output file not found at ~/hl7_output/adt_messages.hl7"}
        
    if not task_result.get('file_created_during_task', False):
        return {"passed": False, "score": 0, "feedback": "Output file exists but was not created during this task session (anti-gaming check failed)."}

    # Load and parse the HL7 content
    hl7_file_path = "/tmp/adt_messages_export.hl7"
    local_hl7_path = tempfile.mktemp()
    
    try:
        copy_from_env(hl7_file_path, local_hl7_path)
        with open(local_hl7_path, 'r', encoding='utf-8', errors='replace') as f:
            content = f.read()
    except Exception as e:
        return {"passed": False, "score": 10, "feedback": f"Failed to retrieve HL7 file content: {e}"}
    finally:
        if os.path.exists(local_hl7_path):
            os.remove(local_hl7_path)

    # Split content into messages (usually separated by blank lines or just consecutive MSH)
    # Reliable split: look for MSH segments
    raw_messages = re.split(r'(?=^MSH\|)', content, flags=re.MULTILINE)
    messages = [m for m in raw_messages if m.strip()]
    
    if not messages:
        return {"passed": False, "score": 10, "feedback": "File contains no valid HL7 messages (no MSH segments found)."}

    score = 10  # Base score for file existence
    feedback = []
    
    # 1. Structure Verification (Max 30 pts)
    struct_score = 0
    valid_msh_count = 0
    valid_pid_count = 0
    valid_evn_count = 0
    valid_pv1_count = 0
    
    parsed_patients = []
    
    for msg in messages:
        parsed = parse_hl7_message(msg)
        
        # MSH Check
        if 'MSH' in parsed:
            msh = parsed['MSH'][0]
            if len(msh) >= 9 and 'ADT^A04' in msh[8] and '2.4' in msh[11]:
                valid_msh_count += 1
        
        # PID Check
        if 'PID' in parsed:
            valid_pid_count += 1
            pid = parsed['PID'][0]
            # Extract patient info for later matching
            # PID|1||GUID||NAME^FIRST||DOB|SEX|||ADDR^^CITY^CP^FR|||||||NIR
            # Note: Fields list index is 1-based in HL7 docs, 0-based in python list.
            # Split usually keeps empty strings, so indexes roughly align if we account for MSH field separator counting weirdness
            # Standard python split('|'): MSH|... -> ['MSH', '...', ...]
            # For PID: PID|1||ID -> ['PID', '1', '', 'ID']
            # PID-3 is index 3. PID-5 is index 5.
            
            try:
                p_data = {
                    'name_field': pid[5] if len(pid) > 5 else "",
                    'dob': pid[7] if len(pid) > 7 else "",
                    'sex': pid[8] if len(pid) > 8 else "",
                    'addr_field': pid[11] if len(pid) > 11 else "",
                    'nir': pid[19] if len(pid) > 19 else ""
                }
                parsed_patients.append(p_data)
            except IndexError:
                pass

        if 'EVN' in parsed:
            valid_evn_count += 1
        if 'PV1' in parsed:
            valid_pv1_count += 1

    total_msgs = len(messages)
    
    # Scoring structure
    if valid_msh_count == total_msgs:
        struct_score += 10
        feedback.append("All messages have valid MSH.")
    else:
        feedback.append(f"Only {valid_msh_count}/{total_msgs} MSH segments valid.")
        
    if valid_pid_count == total_msgs:
        struct_score += 10
        feedback.append("All messages have PID.")
    
    if valid_evn_count == total_msgs:
        struct_score += 5
    if valid_pv1_count == total_msgs:
        struct_score += 5

    score += struct_score

    # 2. Content Verification (Max 45 pts - 15 per patient)
    patient_score = 0
    
    for target in required_patients:
        found = False
        target_last = target['lastname'].upper()
        target_first = target['firstname']
        target_dob = target['dob']
        
        for p in parsed_patients:
            # check name (LAST^FIRST)
            name_parts = p['name_field'].split('^')
            if len(name_parts) >= 2:
                last_match = target_last in name_parts[0].upper()
                first_match = target_first.upper() in name_parts[1].upper()
            else:
                last_match = target_last in p['name_field'].upper()
                first_match = False
            
            # check dob
            dob_match = target_dob in p['dob'].replace('-', '')
            
            if last_match and dob_match:
                # Found candidate, check details
                p_score = 5 # Base for finding name+dob
                
                # Check sex
                if target['sex'] == p['sex']:
                    p_score += 2
                else:
                    feedback.append(f"Patient {target_last}: Wrong sex {p['sex']}")

                # Check city
                if target['city'].upper() in p['addr_field'].upper():
                    p_score += 4
                else:
                    feedback.append(f"Patient {target_last}: City {target['city']} not found in {p['addr_field']}")

                # Check NIR
                if target['nir_fragment'] in p['nir'].replace(' ', ''):
                    p_score += 4
                else:
                    feedback.append(f"Patient {target_last}: NIR mismatch or missing")
                
                patient_score += p_score
                found = True
                break
        
        if not found:
            feedback.append(f"Patient {target_last} {target_first} NOT found in output.")

    score += patient_score

    # 3. Completeness Verification (Max 15 pts)
    # Check if message count roughly matches DB count
    db_count = task_result.get('db_patient_count', 0)
    if total_msgs >= max(3, int(db_count) - 5): # Allow small variance
        score += 15
        feedback.append(f"Message count ({total_msgs}) matches DB records ({db_count}).")
    elif total_msgs >= 3:
        score += 5
        feedback.append(f"Message count ({total_msgs}) lower than DB records ({db_count}).")
    else:
        feedback.append(f"Too few messages ({total_msgs}).")

    passed = (score >= 60) and (patient_score >= 15) # Pass if score >= 60 AND at least one full patient is correct

    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }