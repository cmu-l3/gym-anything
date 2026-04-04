#!/usr/bin/env python3
"""
Verifier for Lab Pack Chemical Classification Task.
Validates the CSV output for correct chemical classification data.
"""

import json
import csv
import os
import tempfile
import logging
import difflib

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def normalize_text(text):
    """Normalize text for comparison."""
    if not text:
        return ""
    return str(text).strip().lower()

def fuzzy_match(str1, str2, threshold=0.8):
    """Check if two strings are roughly similar."""
    s1 = normalize_text(str1)
    s2 = normalize_text(str2)
    if s1 in s2 or s2 in s1:
        return True
    return difflib.SequenceMatcher(None, s1, s2).ratio() >= threshold

def verify_lab_pack_inventory(traj, env_info, task_info):
    """
    Verify the lab pack inventory CSV.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_chemicals = metadata.get('expected_chemicals', [])
    scoring = metadata.get('scoring', {})
    
    score = 0
    feedback_parts = []
    
    # 1. Get Result JSON
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load task result: {str(e)}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    # 2. Check File Existence and Creation (Anti-Gaming)
    if not result_data.get('output_exists', False):
        return {"passed": False, "score": 0, "feedback": "Output CSV file not found."}
    
    score += scoring.get('file_exists', 10)
    
    if not result_data.get('file_created_during_task', False):
        feedback_parts.append("Warning: File timestamp indicates it wasn't created during this session.")
        # We penalize but don't fail immediately, in case of clock sync issues, but normally this is 0
    
    # 3. Retrieve and Parse CSV
    temp_csv = tempfile.NamedTemporaryFile(delete=False, suffix='.csv')
    try:
        copy_from_env("/tmp/lab_pack_inventory.csv", temp_csv.name)
        
        with open(temp_csv.name, 'r', encoding='utf-8', errors='replace') as f:
            # Read snippet for debugging
            content = f.read()
            f.seek(0)
            
            # Check for headers
            reader = csv.DictReader(f)
            headers = reader.fieldnames if reader.fieldnames else []
            
            # Normalize headers
            norm_headers = [h.lower().strip() for h in headers]
            required_headers = ["chemical name", "un number", "dot hazard class", "reactive group"]
            
            # Allow for some flexibility in header naming
            header_map = {}
            for req in required_headers:
                found = False
                for h in norm_headers:
                    if req in h or h in req:
                        header_map[req] = h
                        found = True
                        break
                if not found:
                    feedback_parts.append(f"Missing header column: {req}")
            
            if len(header_map) == len(required_headers):
                score += scoring.get('correct_headers', 5)
            else:
                score += 2 # Partial points for having a CSV at all
                
            # Parse rows
            rows = list(reader)
            
    except Exception as e:
        return {"passed": False, "score": score, "feedback": f"Failed to parse CSV: {str(e)}"}
    finally:
        if os.path.exists(temp_csv.name):
            os.unlink(temp_csv.name)

    # 4. Verify Content
    points_per_chem = scoring.get('per_chemical_points', 17)
    
    for expected in expected_chemicals:
        chem_name = expected['name']
        found_row = None
        
        # Find matching row
        for row in rows:
            # Handle case where headers might be slightly different or mapped
            row_name = ""
            for k, v in row.items():
                if "name" in k.lower() or "chemical" in k.lower():
                    row_name = v
                    break
            
            if fuzzy_match(chem_name, row_name):
                found_row = row
                break
        
        if not found_row:
            feedback_parts.append(f"Missing chemical: {chem_name}")
            continue
            
        # Check attributes
        # We map the found headers to expected keys
        row_un = ""
        row_class = ""
        row_group = ""
        
        for k, v in found_row.items():
            k_lower = k.lower()
            if "un" in k_lower and "number" in k_lower:
                row_un = v
            elif "class" in k_lower:
                row_class = v
            elif "group" in k_lower or "reactive" in k_lower:
                row_group = v

        # Validation Logic
        item_score = 0
        
        # UN Number check (exact or contained)
        if expected['un'] in str(row_un) or str(row_un) in expected['un']:
            item_score += points_per_chem * 0.33
        else:
            feedback_parts.append(f"{chem_name}: Incorrect UN (Expected {expected['un']}, Got {row_un})")

        # Class check (start match, e.g. '3' matches '3 - Flammable')
        clean_row_class = str(row_class).strip().split(' ')[0] # Handle "3 - Flammable" -> "3"
        if str(expected['class']) in str(row_class):
            item_score += points_per_chem * 0.33
        else:
            feedback_parts.append(f"{chem_name}: Incorrect Class (Expected {expected['class']}, Got {row_class})")

        # Group check (Fuzzy match)
        # Reactive groups can be long. We check if key words match.
        # e.g. "Acids, Strong Non-oxidizing" vs "Acids"
        if fuzzy_match(expected['group'], row_group, threshold=0.6):
            item_score += points_per_chem * 0.34
        else:
            feedback_parts.append(f"{chem_name}: Incorrect Group (Expected '{expected['group']}', Got '{row_group}')")
            
        score += item_score

    # Final tally
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": "; ".join(feedback_parts) if feedback_parts else "All chemicals correctly classified."
    }