#!/usr/bin/env python3
"""
Verifier for create_formatted_label_field task.
Verifies that a DBF file has a specific new field with correctly formatted values.
"""

import json
import os
import sys
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Try to import pyshp, verify if installation is needed
try:
    import shapefile
except ImportError:
    import subprocess
    logger.info("Installing pyshp for verification...")
    subprocess.check_call([sys.executable, "-m", "pip", "install", "pyshp"])
    import shapefile

def verify_create_formatted_label_field(traj, env_info, task_info):
    """
    Verify the task by inspecting the exported DBF file.
    
    Criteria:
    1. DBF file exists and was modified.
    2. 'FULL_LABEL' field exists.
    3. Field type is Character (String).
    4. Data matches pattern "NAME (ADM0_A3)" for sampled records.
    """
    
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    # Load task metadata
    metadata = task_info.get('metadata', {})
    expected_field = metadata.get('new_field_name', 'FULL_LABEL')
    
    # Load result JSON
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {str(e)}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)
            
    # Check basics
    if not result_data.get('dbf_exists', False):
        return {"passed": False, "score": 0, "feedback": "Target DBF file not found."}
        
    score = 0
    feedback = []
    
    # 1. Modification Check (10 pts)
    if result_data.get('dbf_modified', False):
        score += 10
        feedback.append("File modification detected.")
    else:
        feedback.append("Warning: DBF file timestamp indicates no changes saved.")
    
    # Copy DBF file for inspection
    temp_dbf = tempfile.NamedTemporaryFile(delete=False, suffix='.dbf')
    dbf_path = temp_dbf.name
    temp_dbf.close()
    
    try:
        copy_from_env("/tmp/result.dbf", dbf_path)
        
        # Open DBF
        sf = shapefile.Reader(dbf_path)
        fields = [f[0] for f in sf.fields[1:]] # Skip deletion flag field
        
        # 2. Schema Check (30 pts)
        if expected_field in fields:
            score += 30
            feedback.append(f"Field '{expected_field}' found.")
            
            # Check field type
            field_idx = fields.index(expected_field)
            field_desc = sf.fields[field_idx + 1] # +1 offset for deletion flag
            field_type = field_desc[1]
            
            if field_type == 'C':
                score += 10
                feedback.append("Field type is correct (String/Character).")
            else:
                feedback.append(f"Field type incorrect. Expected 'C', got '{field_type}'.")
        else:
            feedback.append(f"Field '{expected_field}' NOT found in schema.")
            return {"passed": False, "score": score, "feedback": " ".join(feedback)}
            
        # 3. Data Content Check (50 pts)
        # Verify 5 random records
        records = sf.records()
        total_records = len(records)
        correct_count = 0
        sample_size = 0
        
        # Find indices for source fields
        try:
            name_idx = fields.index("NAME")
            code_idx = fields.index("ADM0_A3")
            target_idx = fields.index(expected_field)
        except ValueError:
            return {"passed": False, "score": score, "feedback": "Source fields (NAME, ADM0_A3) missing from shapefile! Data corrupted?"}
            
        # Check every record (up to 20 to save time if large, but here 177 is small enough)
        for i, rec in enumerate(records):
            name_val = str(rec[name_idx]).strip()
            code_val = str(rec[code_idx]).strip()
            target_val = str(rec[target_idx]).strip()
            
            expected_val = f"{name_val} ({code_val})"
            
            if target_val == expected_val:
                correct_count += 1
            else:
                # Log first failure
                if sample_size == 0:
                    feedback.append(f"Mismatch in record {i}: Expected '{expected_val}', got '{target_val}'.")
            
            sample_size += 1
        
        accuracy = correct_count / sample_size if sample_size > 0 else 0
        
        if accuracy == 1.0:
            score += 50
            feedback.append("All checked records formatted correctly.")
        elif accuracy > 0.8:
            score += 30
            feedback.append(f"Most records correct ({int(accuracy*100)}%).")
        elif accuracy > 0:
            score += 10
            feedback.append(f"Some records correct ({int(accuracy*100)}%). Check logic.")
        else:
            feedback.append("Data formatting incorrect.")

    except Exception as e:
        feedback.append(f"Error analyzing DBF file: {str(e)}")
    finally:
        if os.path.exists(dbf_path):
            os.unlink(dbf_path)
            
    return {
        "passed": score >= 80,
        "score": score,
        "feedback": " ".join(feedback)
    }