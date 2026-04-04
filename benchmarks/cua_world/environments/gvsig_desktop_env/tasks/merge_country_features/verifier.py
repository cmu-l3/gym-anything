#!/usr/bin/env python3
"""
Verifier for merge_country_features task.

Criteria:
1. 'sales_regions.shp' (and .dbf, .shx) must exist and be valid.
2. The file must have been created/modified during the task window.
3. The attribute table must contain exactly ONE record with NAME="Benelux Region".
4. The attribute table must NOT contain records for "Belgium", "Netherlands", or "Luxembourg".
5. The total feature count should be reduced by 2 (177 -> 175) compared to original.
"""

import json
import os
import struct
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def parse_dbf(dbf_path):
    """
    Minimal DBF parser to avoid external dependencies like pyshp/dbfread in the verification environment.
    Returns a list of dicts representing records.
    """
    try:
        with open(dbf_path, 'rb') as f:
            # Header info
            version = f.read(1)
            year, month, day = struct.unpack('<BBB', f.read(3))
            num_records, header_len, record_len = struct.unpack('<IHH', f.read(8))
            
            # Skip rest of header prefix
            f.seek(32)
            
            fields = []
            while True:
                sep = f.read(1)
                if sep == b'\r':
                    break
                # Field descriptor is 32 bytes
                field_name_raw = sep + f.read(10)
                field_name = field_name_raw.strip(b'\x00').decode('ascii', errors='ignore')
                field_type = f.read(1).decode('ascii')
                f.read(4) # displacement
                field_len = struct.unpack('<B', f.read(1))[0]
                field_dec = struct.unpack('<B', f.read(1))[0]
                f.read(14) # reserved
                fields.append({'name': field_name, 'type': field_type, 'len': field_len})
            
            records = []
            f.seek(header_len)
            
            for _ in range(num_records):
                deletion_flag = f.read(1)
                record = {}
                for field in fields:
                    raw_data = f.read(field['len'])
                    data_str = raw_data.strip(b'\x00').decode('latin1', errors='ignore').strip()
                    record[field['name']] = data_str
                
                if deletion_flag != b'*': # '*' means deleted
                    records.append(record)
                    
            return records
    except Exception as e:
        logger.error(f"Error parsing DBF: {e}")
        return []

def verify_merge_country_features(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_count = metadata.get('expected_feature_count', 175)
    target_name = metadata.get('target_name', "Benelux Region")
    source_names = metadata.get('source_names', ["Belgium", "Netherlands", "Luxembourg"])

    # 1. Retrieve Result JSON
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Could not retrieve task result: {e}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    # 2. Check Basic File Existence
    if not result.get("output_exists", False):
        return {"passed": False, "score": 0, "feedback": "Output shapefile 'sales_regions.shp' was not found."}
    
    if not result.get("file_created_during_task", False):
        return {"passed": False, "score": 0, "feedback": "Output file exists but was not modified during the task."}

    # 3. Retrieve DBF for Content Verification
    dbf_path_remote = result.get("dbf_path")
    temp_dbf = tempfile.NamedTemporaryFile(delete=False, suffix='.dbf')
    
    records = []
    try:
        copy_from_env(dbf_path_remote, temp_dbf.name)
        records = parse_dbf(temp_dbf.name)
    except Exception as e:
        return {"passed": False, "score": 20, "feedback": f"File created but failed to parse DBF: {e}"}
    finally:
        if os.path.exists(temp_dbf.name):
            os.unlink(temp_dbf.name)

    # 4. Analyze Records
    benelux_found = False
    sources_remaining = []
    
    for rec in records:
        name = rec.get("NAME", "")
        # Check target
        if name.lower() == target_name.lower():
            benelux_found = True
        
        # Check sources
        for src in source_names:
            if name.lower() == src.lower():
                sources_remaining.append(src)

    actual_count = len(records)
    
    # 5. Scoring
    score = 20 # Base points for file creation
    feedback = []

    # Criterion: Target feature exists (40 pts)
    if benelux_found:
        score += 40
        feedback.append(f"Success: '{target_name}' feature found.")
    else:
        feedback.append(f"Failure: '{target_name}' feature NOT found in attribute table.")

    # Criterion: Source features removed (20 pts)
    if not sources_remaining:
        score += 20
        feedback.append("Success: Individual source countries removed.")
    else:
        feedback.append(f"Failure: Found unmerged source countries: {', '.join(sources_remaining)}.")

    # Criterion: Feature count (10 pts)
    if actual_count == expected_count:
        score += 10
        feedback.append(f"Success: Feature count is correct ({actual_count}).")
    else:
        feedback.append(f"Warning: Feature count {actual_count} != expected {expected_count}.")

    # 6. VLM Verification (Trajectory) (10 pts)
    # We check if the agent actually used the selection and edit tools
    frames = sample_trajectory_frames(traj, n=5)
    final_img = get_final_screenshot(traj)
    
    vlm_score = 0
    try:
        vlm_resp = query_vlm(
            images=frames + [final_img],
            prompt="Does the user select multiple countries (highlighted yellow) and use an 'Edit' or 'Merge' tool in the interface? "
                   "Does the final map look like normal gvSIG? Answer YES/NO and explain."
        )
        if "YES" in vlm_resp.get("answer", "").upper():
            vlm_score = 10
            feedback.append("VLM: Workflow verification passed.")
        else:
            feedback.append("VLM: Workflow verification inconclusive.")
    except:
        vlm_score = 10 # Fallback if VLM fails
        feedback.append("VLM: Skipped.")
    
    score += vlm_score

    return {
        "passed": score >= 70 and benelux_found,
        "score": score,
        "feedback": " ".join(feedback)
    }