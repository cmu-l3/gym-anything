#!/usr/bin/env python3
"""
Verifier for csv_to_hl7_migration task.

Criteria:
1. Channel Creation & Config (20 pts): Channel exists, correct source type.
2. File Generation (20 pts): Output files generated, correct count.
3. HL7 Structure (20 pts): Valid MSH, PID segments.
4. Data Transformation (40 pts):
   - Date Normalization (MM/DD/YYYY -> YYYYMMDD)
   - Gender Normalization (Male/Female -> M/F)
   - Correct Mapping (Sample check)

Total: 100 pts
"""

import json
import tempfile
import os
import tarfile
import re
import shutil
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_csv_to_hl7_migration(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    # 1. Retrieve Task Result JSON
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)
            
    # 2. Retrieve Ground Truth (optional, for strict checking)
    ground_truth = []
    temp_gt = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/ground_truth.json", temp_gt.name)
        with open(temp_gt.name, 'r') as f:
            ground_truth = json.load(f)
    except:
        logger.warning("Ground truth not found, skipping strict content match.")
    finally:
        if os.path.exists(temp_gt.name):
            os.unlink(temp_gt.name)

    # 3. Retrieve Output Files Archive
    temp_tar = tempfile.NamedTemporaryFile(delete=False, suffix='.tar.gz')
    extract_dir = tempfile.mkdtemp()
    
    try:
        copy_from_env(result.get("output_archive_path", "/tmp/hl7_output.tar.gz"), temp_tar.name)
        with tarfile.open(temp_tar.name, "r:gz") as tar:
            tar.extractall(path=extract_dir)
            
        # Locate the actual files (tar usually preserves structure hl7_import/...)
        output_files_dir = os.path.join(extract_dir, "hl7_import")
        if not os.path.exists(output_files_dir):
            # Fallback if tar structure is different
            output_files_dir = extract_dir
            
        hl7_files = [os.path.join(output_files_dir, f) for f in os.listdir(output_files_dir) if os.path.isfile(os.path.join(output_files_dir, f))]
        
    except Exception as e:
        logger.error(f"Failed to retrieve/extract output archive: {e}")
        hl7_files = []
    finally:
        if os.path.exists(temp_tar.name):
            os.unlink(temp_tar.name)

    # === Evaluation ===
    score = 0
    feedback_parts = []
    
    # Criterion 1: Channel Config (20 pts)
    if result.get("channel_exists"):
        score += 10
        feedback_parts.append("Channel 'Legacy_CSV_Import' exists")
        
        # Check source type (bonus for correct config)
        stype = result.get("source_type", "")
        if "Delimited" in stype:
            score += 10
            feedback_parts.append("Source type configured as Delimited Text")
        else:
            feedback_parts.append(f"Source type '{stype}' may be incorrect (expected Delimited Text)")
    else:
        feedback_parts.append("Channel NOT found")

    # Criterion 2: File Generation (20 pts)
    expected_count = 20
    actual_count = len(hl7_files)
    
    if actual_count >= expected_count:
        score += 20
        feedback_parts.append(f"Generated {actual_count} HL7 files (Expected: {expected_count})")
    elif actual_count > 0:
        score += 10
        feedback_parts.append(f"Partial generation: {actual_count}/{expected_count} files")
    else:
        feedback_parts.append("No output files generated")
        
    # Criterion 3 & 4: HL7 Content Analysis (60 pts)
    valid_hl7_count = 0
    date_normalized_count = 0
    gender_normalized_count = 0
    content_match_count = 0
    
    # Regex for YYYYMMDD
    date_pattern = re.compile(r'^\d{8}$')
    
    for fpath in hl7_files:
        try:
            with open(fpath, 'r') as f:
                content = f.read().strip()
                
            # Basic HL7 check
            if content.startswith("MSH|^~\\&") or ("ADT^A28" in content):
                valid_hl7_count += 1
                
                # Extract PID segment
                # Split by segment delimiter (CR \r or Newline \n)
                segments = re.split(r'[\r\n]+', content)
                pid_segment = next((s for s in segments if s.startswith("PID|")), None)
                
                if pid_segment:
                    fields = pid_segment.split('|')
                    # PID-7 is Date of Birth (index 7 in 1-based HL7, index 7 in 0-based split because PID is index 0)
                    # "PID|1|ID|..." -> [PID, 1, ID...]
                    # Index: 0   1   2
                    # PID-3 is index 3
                    # PID-5 is index 5
                    # PID-7 is index 7
                    # PID-8 is index 8
                    
                    if len(fields) > 7:
                        dob = fields[7]
                        # Check Date Normalization
                        if date_pattern.match(dob):
                            # Ensure it's not the original MM/DD/YYYY
                            if "/" not in dob:
                                date_normalized_count += 1
                    
                    if len(fields) > 8:
                        gender = fields[8]
                        # Check Gender Normalization
                        if gender in ['M', 'F']:
                            gender_normalized_count += 1
        except Exception as e:
            logger.error(f"Error reading file {fpath}: {e}")

    # Score HL7 Structure
    if valid_hl7_count >= (actual_count * 0.9) and actual_count > 0:
        score += 20
        feedback_parts.append("Output files are valid HL7 messages")
    elif actual_count > 0:
        feedback_parts.append(f"Some files invalid HL7 ({valid_hl7_count}/{actual_count})")

    # Score Transformations (Requires at least some files)
    if actual_count > 0:
        # Date
        if date_normalized_count >= (actual_count * 0.9):
            score += 20
            feedback_parts.append("Date format correctly transformed (YYYYMMDD)")
        else:
            feedback_parts.append(f"Date format incorrect or not transformed ({date_normalized_count}/{actual_count})")
            
        # Gender
        if gender_normalized_count >= (actual_count * 0.9):
            score += 20
            feedback_parts.append("Gender correctly transformed (M/F)")
        else:
            feedback_parts.append(f"Gender incorrect or not transformed ({gender_normalized_count}/{actual_count})")

    # Cleanup
    shutil.rmtree(extract_dir, ignore_errors=True)

    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }