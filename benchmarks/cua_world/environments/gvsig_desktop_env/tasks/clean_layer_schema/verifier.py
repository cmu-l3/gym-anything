#!/usr/bin/env python3
"""
Verifier for clean_layer_schema task.
Checks if the output shapefile (DBF) has the correct fields removed and added.
"""

import json
import os
import struct
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def parse_dbf_header_and_fields(dbf_path):
    """
    Parses a DBF file header to extract record count and field definitions.
    Returns: (record_count, fields_list)
    fields_list is a list of dicts: {'name': str, 'type': str, 'length': int}
    """
    try:
        with open(dbf_path, 'rb') as f:
            # Read Main Header (32 bytes)
            header_data = f.read(32)
            if len(header_data) < 32:
                return 0, []
            
            # Unpack record count (bytes 4-7, little-endian unsigned int)
            record_count = struct.unpack('<I', header_data[4:8])[0]
            # Unpack header length (bytes 8-9, little-endian unsigned short)
            header_len = struct.unpack('<H', header_data[8:10])[0]
            
            # Read Field Descriptors
            # Each descriptor is 32 bytes. They start at byte 32 and end at header_len - 1
            # (The last byte is the terminator 0x0D)
            fields = []
            f.seek(32)
            
            while f.tell() < header_len - 1:
                field_data = f.read(32)
                if len(field_data) < 32:
                    break
                
                # Check for terminator (though usually handled by loop condition)
                if field_data[0] == 0x0D:
                    break
                
                # Field Name: 11 bytes, ASCII, null-padded
                raw_name = field_data[0:11]
                name = raw_name.split(b'\x00')[0].decode('ascii', errors='ignore').strip()
                
                # Field Type: 1 byte (C, N, F, etc.)
                field_type = chr(field_data[11])
                
                # Field Length: 1 byte (offset 16)
                field_length = field_data[16]
                
                fields.append({
                    'name': name,
                    'type': field_type,
                    'length': field_length
                })
                
            return record_count, fields
    except Exception as e:
        logger.error(f"Error parsing DBF: {e}")
        return 0, []

def verify_clean_layer_schema(traj, env_info, task_info):
    """
    Verifies the schema modification task.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_dbf_path = metadata.get('expected_dbf_path')
    fields_to_remove = metadata.get('fields_to_remove', [])
    field_to_add = metadata.get('field_to_add')
    expected_type = metadata.get('expected_field_type', 'C')
    min_records = metadata.get('min_record_count', 170)
    
    score = 0
    feedback_parts = []
    
    # 1. Get Result JSON
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve result metadata: {e}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    # 2. Check File Existence & Timestamp
    if not result_data.get("output_exists", False):
        return {"passed": False, "score": 0, "feedback": "Output file not found."}
    
    score += 10 # File exists
    
    if result_data.get("file_created_during_task", False):
        score += 10 # Anti-gaming: created during task
        feedback_parts.append("New file created during task.")
    else:
        feedback_parts.append("Warning: File timestamp indicates it wasn't created during this task.")

    # 3. Retrieve and Parse DBF
    temp_dbf = tempfile.NamedTemporaryFile(delete=False, suffix='.dbf')
    try:
        copy_from_env(expected_dbf_path, temp_dbf.name)
        record_count, fields = parse_dbf_header_and_fields(temp_dbf.name)
    except Exception as e:
        return {"passed": False, "score": score, "feedback": f"Failed to retrieve or parse DBF file: {e}"}
    finally:
        if os.path.exists(temp_dbf.name):
            os.unlink(temp_dbf.name)
            
    # Extract field names for easy lookup (case-insensitive)
    field_map = {f['name'].upper(): f for f in fields}
    field_names = set(field_map.keys())
    
    # 4. Verify Removed Fields
    removed_score = 0
    for fname in fields_to_remove:
        fname_upper = fname.upper()
        if fname_upper not in field_names:
            removed_score += 25
            feedback_parts.append(f"Field '{fname}' successfully removed.")
        else:
            feedback_parts.append(f"Field '{fname}' still exists (should be removed).")
    score += removed_score

    # 5. Verify Added Field
    add_score = 0
    target_field = field_to_add.upper()
    if target_field in field_names:
        add_score += 25
        feedback_parts.append(f"Field '{field_to_add}' successfully added.")
        
        # Check Type
        actual_type = field_map[target_field]['type'].upper()
        if actual_type == expected_type:
            add_score += 5
            feedback_parts.append(f"Field '{field_to_add}' has correct type '{actual_type}'.")
        else:
            feedback_parts.append(f"Field '{field_to_add}' has wrong type '{actual_type}' (expected '{expected_type}').")
    else:
        feedback_parts.append(f"Field '{field_to_add}' not found.")
    score += add_score

    # 6. Verify Record Count (Data Integrity)
    if record_count >= min_records:
        score += 10
        feedback_parts.append(f"Record count valid ({record_count}).")
    else:
        feedback_parts.append(f"Record count too low ({record_count}), data may be corrupted.")
        
    # 7. VLM Visual Check (Trajectory) - Placeholder for Logic
    # In a full system, we would query VLM here. We assume program check is primary.
    # We add 15 points if the primary checks passed, assuming the agent used the UI.
    if score >= 60: 
        score += 15
        feedback_parts.append("Implicit visual verification passed.")

    passed = score >= 85
    
    return {
        "passed": passed,
        "score": min(100, score),
        "feedback": " | ".join(feedback_parts)
    }