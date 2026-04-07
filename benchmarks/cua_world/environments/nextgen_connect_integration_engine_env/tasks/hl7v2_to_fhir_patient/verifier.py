#!/usr/bin/env python3
import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_hl7v2_to_fhir_patient(traj, env_info, task_info):
    """
    Verify the HL7v2 to FHIR Patient transformation task.
    
    Criteria:
    1. Channel created and deployed (STARTED).
    2. Correct Source configuration (Port 6661).
    3. Correct Destination configuration (File Writer to /tmp/fhir_output).
    4. Output file generated (Anti-gaming: created after task start).
    5. Output content is valid FHIR JSON with correct field mappings.
    """
    
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
        
    # Load metadata expectations
    metadata = task_info.get('metadata', {})
    expected_mappings = metadata.get('expected_mappings', {})
    
    # Copy result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)
            
    score = 0
    feedback_parts = []
    
    # 1. Channel Status (20 pts)
    if result.get('channel_found'):
        status = result.get('channel_status', 'UNKNOWN')
        if status == 'STARTED':
            score += 20
            feedback_parts.append("Channel created and STARTED.")
        else:
            score += 10
            feedback_parts.append(f"Channel created but status is {status} (expected STARTED).")
    else:
        feedback_parts.append("Channel 'ADT_to_FHIR_Patient' NOT found.")
        
    # 2. Configuration Check (20 pts)
    config = result.get('config', {})
    # Port
    if str(config.get('port')) == '6661':
        score += 10
        feedback_parts.append("Source port 6661 correct.")
    else:
        feedback_parts.append(f"Incorrect source port: {config.get('port')}.")
        
    # Dest Dir
    dest_dir = config.get('dest_dir', '')
    if '/tmp/fhir_output' in dest_dir:
        score += 10
        feedback_parts.append("Destination directory correct.")
    else:
        feedback_parts.append(f"Incorrect destination directory: {dest_dir}.")
        
    # 3. Output File Existence & Timestamp (10 pts)
    file_exists = result.get('output_file_exists')
    file_ts = result.get('file_timestamp', 0)
    start_time = result.get('task_start_time', 0)
    
    valid_file = False
    if file_exists:
        if file_ts > start_time:
            score += 10
            valid_file = True
            feedback_parts.append("Output file generated during task.")
        else:
            feedback_parts.append("Output file exists but timestamp is too old (pre-existing?).")
    else:
        feedback_parts.append("No output file generated.")
        
    # 4. Content Verification (50 pts)
    if valid_file:
        try:
            content_str = result.get('file_content', '')
            fhir = json.loads(content_str)
            
            # Resource Type
            if fhir.get('resourceType') == 'Patient':
                score += 5
            else:
                feedback_parts.append("Invalid resourceType.")
                
            # Identifier (MRN12345)
            ids = fhir.get('identifier', [])
            # Handle if single dict or list
            if isinstance(ids, dict): ids = [ids]
            
            id_found = False
            for i in ids:
                if expected_mappings['identifier'] in str(i.get('value', '')):
                    id_found = True
                    break
            if id_found:
                score += 10
            else:
                feedback_parts.append(f"Identifier {expected_mappings['identifier']} not found.")
                
            # Name (SMITH, JOHN)
            names = fhir.get('name', [])
            if isinstance(names, dict): names = [names]
            
            name_score = 0
            for n in names:
                family = str(n.get('family', '')).upper()
                given = str(n.get('given', [])).upper()
                if expected_mappings['family'] in family:
                    name_score += 5
                if expected_mappings['given'] in given:
                    name_score += 5
            if name_score < 10:
                feedback_parts.append("Name mapping incorrect/incomplete.")
            score += min(name_score, 10)
            
            # BirthDate
            if fhir.get('birthDate') == expected_mappings['birthDate']:
                score += 5
            else:
                feedback_parts.append(f"Incorrect birthDate: {fhir.get('birthDate')}.")
                
            # Gender
            if fhir.get('gender') == expected_mappings['gender']:
                score += 5
            else:
                feedback_parts.append(f"Incorrect gender: {fhir.get('gender')}.")
                
            # Address
            addrs = fhir.get('address', [])
            if isinstance(addrs, dict): addrs = [addrs]
            
            addr_score = 0
            for a in addrs:
                # Loose matching to allow case diffs
                txt = str(a).upper()
                if expected_mappings['city'] in txt and expected_mappings['zip'] in txt:
                    addr_score = 10
                    break
            if addr_score == 10:
                score += 10
            else:
                feedback_parts.append("Address mapping incorrect.")
                
            # Telecom
            telecoms = fhir.get('telecom', [])
            if isinstance(telecoms, dict): telecoms = [telecoms]
            
            tel_found = False
            for t in telecoms:
                if expected_mappings['phone'] in str(t.get('value', '')):
                    tel_found = True
                    break
            if tel_found:
                score += 5
            else:
                feedback_parts.append("Telecom mapping incorrect.")
                
        except json.JSONDecodeError:
            feedback_parts.append("Output file is not valid JSON.")
        except Exception as e:
            feedback_parts.append(f"Error parsing content: {str(e)}")
            
    passed = score >= 60
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback_parts)
    }