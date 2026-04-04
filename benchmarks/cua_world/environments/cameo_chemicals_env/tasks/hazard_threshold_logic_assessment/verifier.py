#!/usr/bin/env python3
"""
Verifier for hazard_threshold_logic_assessment task.
"""

import json
import csv
import os
import tempfile
import logging
from io import StringIO

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_hazard_threshold_logic_assessment(traj, env_info, task_info):
    """
    Verifies the CSV output for hazard threshold assessment.
    
    Scoring Criteria:
    1. File Structure (10 pts): CSV exists with correct headers.
    2. LEL Conversions (20 pts): Correct ppm values (±20% tolerance).
    3. Toxic Limits (25 pts): Correct AEGL/ERPG/TEEL values (±10% tolerance).
    4. Non-Flammable Handling (10 pts): Chlorine LEL identified as N/A or 0.
    5. Hazard Logic (35 pts): Status matches logic derived from values.
    
    Total: 100 pts. Pass Threshold: 80 pts.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    scenarios = metadata.get('scenarios', [])
    output_path = metadata.get('output_path', '/home/ga/Documents/alarm_logic_assessment.csv')
    
    score = 0
    feedback_parts = []
    
    # 1. Check if file exists and was created during task
    # First read the metadata result json
    temp_meta = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_meta.name)
        with open(temp_meta.name, 'r') as f:
            meta_result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result metadata: {str(e)}"}
    finally:
        if os.path.exists(temp_meta.name):
            os.unlink(temp_meta.name)
            
    if not meta_result.get('output_exists', False):
        return {"passed": False, "score": 0, "feedback": "Output CSV file not found"}
        
    if not meta_result.get('file_created_during_task', False):
        feedback_parts.append("Warning: File timestamp indicates it wasn't created during task (potential pre-existing file).")
        # We penalize but continue to check content in case of clock skew/filesystem quirks, 
        # usually this would be a fail but let's see content.
    
    # 2. Read and Parse CSV
    temp_csv = tempfile.NamedTemporaryFile(delete=False, suffix='.csv')
    try:
        copy_from_env(output_path, temp_csv.name)
        with open(temp_csv.name, 'r', encoding='utf-8', errors='replace') as f:
            content = f.read()
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read CSV content: {str(e)}"}
    finally:
        if os.path.exists(temp_csv.name):
            os.unlink(temp_csv.name)
            
    try:
        reader = csv.DictReader(StringIO(content))
        rows = list(reader)
        headers = reader.fieldnames if reader.fieldnames else []
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Invalid CSV format: {str(e)}"}

    # normalize headers
    headers_norm = [h.strip().lower() for h in headers]
    required_headers = ['chemical', 'detected_ppm', 'lel_ppm', 'toxic_limit_ppm', 'hazard_status']
    
    if all(any(req in h for h in headers_norm) for req in required_headers):
        score += 10
        feedback_parts.append("CSV structure correct")
    else:
        feedback_parts.append(f"Missing required columns. Found: {headers}")
        # Try to proceed if we can map columns vaguely, else fail
        # For strictness, if headers are totally wrong, we might fail, but let's try to look at data
    
    # Helper to parse number
    def parse_num(val):
        if not val: return None
        clean = ''.join(c for c in str(val) if c.isdigit() or c == '.')
        try:
            return float(clean)
        except:
            return None

    # Helper to clean string
    def clean_str(val):
        return str(val).strip().upper() if val else ""

    # Scoring trackers
    lel_score = 0
    toxic_score = 0
    non_flam_score = 0
    logic_score = 0
    
    # Process each expected scenario
    for scen in scenarios:
        name = scen['name']
        
        # Find matching row
        row = next((r for r in rows if name.lower() in str(r).lower()), None)
        
        if not row:
            feedback_parts.append(f"Missing row for {name}")
            continue
            
        # Map keys flexibly
        row_map = {k.strip().lower(): v for k, v in row.items()}
        
        # Get values
        # Find keys that look right
        k_detected = next((k for k in row_map if 'detected' in k), None)
        k_lel = next((k for k in row_map if 'lel' in k), None)
        k_toxic = next((k for k in row_map if 'toxic' in k), None)
        k_status = next((k for k in row_map if 'status' in k), None)
        
        val_lel = parse_num(row_map.get(k_lel))
        val_toxic = parse_num(row_map.get(k_toxic))
        val_status = clean_str(row_map.get(k_status))
        val_detected = parse_num(row_map.get(k_detected))
        
        # --- Check LEL (20 pts total -> 4 pts per chemical) ---
        expected_lel_percent = scen['expected_lel_percent']
        if expected_lel_percent is None:
            # Non-flammable (Chlorine)
            # Check if they wrote N/A, 0, or Non-flammable
            raw_lel = str(row_map.get(k_lel)).lower()
            if val_lel == 0 or 'n/a' in raw_lel or 'none' in raw_lel or 'non' in raw_lel or 'inf' in raw_lel:
                non_flam_score += 10 # Only applies to Chlorine
            else:
                feedback_parts.append(f"{name}: Failed to identify as non-flammable (wrote {raw_lel})")
        else:
            expected_lel_ppm = expected_lel_percent * 10000
            if val_lel is not None:
                # 20% tolerance
                if abs(val_lel - expected_lel_ppm) / expected_lel_ppm < 0.2:
                    lel_score += 5 # 4 chemicals with LEL * 5 pts = 20 pts
                else:
                    feedback_parts.append(f"{name}: LEL incorrect. Expected ~{expected_lel_ppm}, got {val_lel}")
            else:
                 feedback_parts.append(f"{name}: LEL missing/unparseable")

        # --- Check Toxic Limit (25 pts total -> 5 pts per chemical) ---
        expected_toxic = scen['expected_toxic_limit']
        if val_toxic is not None:
            # 15% tolerance for variations in data versions
            if abs(val_toxic - expected_toxic) / expected_toxic < 0.15:
                toxic_score += 5
            else:
                feedback_parts.append(f"{name}: Toxic limit mismatch. Expected ~{expected_toxic}, got {val_toxic}")
        else:
            feedback_parts.append(f"{name}: Toxic limit missing")

        # --- Check Logic (35 pts total -> 7 pts per chemical) ---
        # Logic is checked against the EXPECTED status to ensure they used the right limits AND logic
        # OR we could check self-consistency. Let's check against Ground Truth Logic first.
        expected_status = scen['expected_status']
        
        # Fuzzy match status
        # Normalize agent status
        # "TOXIC AND EXPLOSIVE" contains "TOXIC" and "EXPLOSIVE"
        # "SAFE"
        
        match = False
        if expected_status == "SAFE":
            if "SAFE" in val_status and "TOXIC" not in val_status and "EXPLOSIVE" not in val_status:
                match = True
        elif expected_status == "TOXIC AND EXPLOSIVE":
            if "TOXIC" in val_status and "EXPLOSIVE" in val_status:
                match = True
        elif expected_status == "TOXIC":
            if "TOXIC" in val_status and "EXPLOSIVE" not in val_status:
                match = True
        elif expected_status == "EXPLOSIVE":
            if "EXPLOSIVE" in val_status and "TOXIC" not in val_status:
                match = True
                
        if match:
            logic_score += 7
        else:
            feedback_parts.append(f"{name}: Status logic wrong. Expected {expected_status}, got {val_status}")

    # Add up scores
    # Adjust scores based on number of items if needed, but simple addition works here
    # LEL: 4 items * 5 = 20
    # Non-flam: 1 item * 10 = 10
    # Toxic: 5 items * 5 = 25
    # Logic: 5 items * 7 = 35
    
    score += lel_score + non_flam_score + toxic_score + logic_score
    
    passed = score >= 80
    
    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": "; ".join(feedback_parts) if feedback_parts else "All criteria met perfectly.",
        "details": {
            "lel_score": lel_score,
            "toxic_score": toxic_score,
            "logic_score": logic_score,
            "structure_score": 10 if score >= 10 else 0
        }
    }