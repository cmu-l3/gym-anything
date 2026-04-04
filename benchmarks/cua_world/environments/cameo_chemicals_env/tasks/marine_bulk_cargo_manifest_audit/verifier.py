#!/usr/bin/env python3
"""
Verifier for Marine Bulk Cargo Manifest Audit task.
Verifies the agent created a CSV with correct USCG CHRIS Codes and Compatibility Groups.
"""

import json
import os
import csv
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_marine_bulk_cargo_manifest_audit(traj, env_info, task_info):
    """
    Verify the CSV file contains the correct CHRIS codes and USCG groups.
    """
    # 1. Setup and helper functions
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    ground_truth = metadata.get('ground_truth', {})
    output_path = metadata.get('output_path', '/home/ga/Desktop/marine_manifest.csv')

    score = 0
    feedback = []
    
    # 2. Get result JSON (metadata)
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result_meta = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result metadata: {e}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    # 3. Check file existence and timestamp (Anti-gaming)
    if not result_meta.get('output_exists', False):
        return {"passed": False, "score": 0, "feedback": "Output CSV file not found on Desktop."}
    
    score += 10
    feedback.append("File exists")

    if not result_meta.get('file_created_during_task', False):
        feedback.append("WARNING: File timestamp indicates it was not created during this task session.")
        # We penalize but don't fail immediately, in case of clock skew issues, but strictly this is 0
        return {"passed": False, "score": 10, "feedback": "File was not created during the task window."}

    # 4. Copy and Parse CSV
    temp_csv = tempfile.NamedTemporaryFile(delete=False, suffix='.csv')
    try:
        copy_from_env(output_path, temp_csv.name)
        
        # Parse CSV
        rows = []
        with open(temp_csv.name, 'r', encoding='utf-8', errors='replace') as f:
            # Handle potential variation in CSV format (dialect)
            try:
                # Try reading with header detection
                snippet = f.read(1024)
                f.seek(0)
                has_header = csv.Sniffer().has_header(snippet)
                dialect = csv.Sniffer().sniff(snippet)
                reader = csv.reader(f, dialect)
            except:
                # Fallback to standard
                f.seek(0)
                reader = csv.reader(f)
            
            all_rows = list(reader)

    except Exception as e:
        return {"passed": False, "score": score, "feedback": f"Failed to read/parse CSV file: {e}"}
    finally:
        if os.path.exists(temp_csv.name):
            os.unlink(temp_csv.name)

    # Validate structure
    if len(all_rows) < 2:
        return {"passed": False, "score": score, "feedback": "CSV file is empty or missing data rows."}

    score += 10
    feedback.append("Valid CSV format")

    # Normalize data for comparison
    # Expected Headers roughly: Name, CHRIS, Group
    # We will iterate rows and try to fuzzy match chemical names to ground truth
    
    # Map normalized chemical names (lowercase) to their ground truth keys
    chem_map = {k.lower(): k for k in ground_truth.keys()}
    
    found_data = {}
    
    # Headers are likely row 0, but we scan all rows for data
    for row in all_rows:
        if len(row) < 3:
            continue
            
        # Basic cleaning
        row_clean = [str(x).strip() for x in row]
        
        # Check if first column matches a chemical name
        name_val = row_clean[0].lower()
        
        matched_key = None
        for key in chem_map:
            if key in name_val: # Contains check (e.g. "Styrene monomer" inside "Styrene monomer")
                matched_key = chem_map[key]
                break
        
        if matched_key:
            chris_val = row_clean[1].upper()
            # Extract digits for group (handle "Group 15" or "15")
            group_raw = row_clean[2]
            group_val = ''.join(filter(str.isdigit, group_raw))
            
            found_data[matched_key] = {
                "chris": chris_val,
                "group": group_val,
                "raw_group": group_raw
            }

    # 5. Score Data Accuracy
    # 5 chemicals, 16 points each (8 for CHRIS, 8 for Group)
    # Total remaining points: 80
    
    for chem_name, truth in ground_truth.items():
        if chem_name not in found_data:
            feedback.append(f"Missing data for {chem_name}")
            continue
            
        agent_data = found_data[chem_name]
        
        # Check CHRIS Code
        if agent_data['chris'] == truth['chris']:
            score += 8
        else:
            feedback.append(f"{chem_name}: Wrong CHRIS (Expected {truth['chris']}, Got {agent_data['chris']})")
            
        # Check Group
        # Special check: Ensure they didn't put the Reactive Group NAME instead of USCG Number
        # If group is empty but raw_group has text, they might have copied the reactive group text
        if agent_data['group'] == truth['group']:
            score += 8
        else:
            # check for common mistake (Reactive Group count)
            # e.g. Sulfuric acid is 'Acids, Strong Oxidizing' (Reactive Group 2 in older versions or text)
            # But we strictly want the USCG number.
            feedback.append(f"{chem_name}: Wrong USCG Group (Expected {truth['group']}, Got {agent_data['raw_group']})")

    # 6. Final Assessment
    passed = score >= 74  # Threshold from description
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }