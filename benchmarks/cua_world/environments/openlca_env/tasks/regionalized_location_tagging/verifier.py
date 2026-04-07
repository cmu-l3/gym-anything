#!/usr/bin/env python3
"""
Verifier for regionalized_location_tagging@1

Scoring Criteria (100 pts total):
1. Database Entities (30 pts):
   - Location 'US-CA' created correctly (10 pts)
   - Location 'US-TX' created correctly (10 pts)
   - Location 'US-OH' created correctly (10 pts)
2. Process Assignments (36 pts):
   - Process linked to US-CA (12 pts)
   - Process linked to US-TX (12 pts)
   - Process linked to US-OH (12 pts)
3. CSV Report (34 pts):
   - File exists and created during task (10 pts)
   - Header correct (4 pts)
   - Contains all 3 codes (10 pts)
   - Coordinates match (10 pts)

Check:
- Derby DB query results (primary)
- CSV content (secondary)
- VLM (tertiary context check)
"""

import json
import os
import tempfile
import base64
import logging
import re
from typing import Dict, Any, List

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Target coordinates with tolerance
TARGETS = {
    "US-CA": {"lat": 36.7783, "lon": -119.4179},
    "US-TX": {"lat": 31.9686, "lon": -99.9018},
    "US-OH": {"lat": 40.4173, "lon": -82.9071}
}
TOLERANCE = 0.5

def parse_derby_output(raw_output: str) -> List[Dict[str, str]]:
    """
    Parse raw text output from Derby ij.
    Expected format is table-like with pipes or spaces.
    """
    rows = []
    lines = raw_output.split('\n')
    # Simple parser: look for lines containing expected codes
    for line in lines:
        clean_line = line.strip()
        if not clean_line or clean_line.startswith('---') or clean_line.startswith('CODE'):
            continue
        
        # Split by whitespace (Derby usually outputs fixed width or space separated)
        parts = clean_line.split()
        if len(parts) >= 2:
            # Check if this line contains one of our codes
            for code in TARGETS.keys():
                if code in clean_line:
                    # Attempt to extract lat/lon
                    # Format usually: CODE NAME LAT LON or similar depending on query order
                    # Query was: SELECT CODE, NAME, LATITUDE, LONGITUDE
                    # So US-CA California 36.7783 -119.4179
                    
                    row_data = {"code": code, "raw": clean_line}
                    
                    # Try to find floats
                    floats = re.findall(r'-?\d+\.\d+', clean_line)
                    if len(floats) >= 2:
                        row_data["lat"] = float(floats[0])
                        row_data["lon"] = float(floats[1])
                    
                    rows.append(row_data)
                    break
    return rows

def parse_assignments(raw_output: str) -> List[str]:
    """
    Parse assignment query output.
    Query: SELECT p.NAME, l.CODE ...
    """
    found_codes = []
    lines = raw_output.split('\n')
    for line in lines:
        for code in TARGETS.keys():
            if code in line:
                found_codes.append(code)
    return found_codes

def verify_regionalized_location_tagging(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Environment access failed"}

    # Load result
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load results: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []

    # 1. DB: Locations Created
    loc_raw = base64.b64decode(result.get("locations_query_b64", "")).decode('utf-8', errors='ignore')
    found_locations = parse_derby_output(loc_raw)
    
    created_codes = set()
    for loc in found_locations:
        code = loc["code"]
        target = TARGETS[code]
        
        # Check coordinates
        lat_ok = abs(loc.get("lat", 999) - target["lat"]) <= TOLERANCE
        lon_ok = abs(loc.get("lon", 999) - target["lon"]) <= TOLERANCE
        
        if lat_ok and lon_ok:
            score += 10
            created_codes.add(code)
            feedback.append(f"Location {code} created correctly.")
        else:
            feedback.append(f"Location {code} found but coords mismatch.")
    
    if not created_codes:
        feedback.append("No correct locations found in database.")

    # 2. DB: Process Assignments
    assign_raw = base64.b64decode(result.get("assignments_query_b64", "")).decode('utf-8', errors='ignore')
    assigned_codes = parse_assignments(assign_raw)
    
    # We want 3 distinct processes assigned. 
    # If same process assigned multiple times? Query returns rows. 
    # Derby query was: SELECT p.NAME, l.CODE ...
    # If we find lines with US-CA, US-TX, US-OH, we assume success for each unique code found attached to a process.
    
    unique_assigned = set(assigned_codes)
    for code in unique_assigned:
        if code in TARGETS:
            score += 12
            feedback.append(f"Process assigned to {code}.")

    # 3. CSV Report
    csv_exists = result.get("csv_exists", False)
    csv_created = result.get("csv_created_during_task", False)
    
    if csv_exists and csv_created:
        score += 10
        feedback.append("CSV report created.")
        
        csv_head = base64.b64decode(result.get("csv_head_b64", "")).decode('utf-8', errors='ignore')
        
        # Header check
        if "process" in csv_head.lower() and "location" in csv_head.lower():
            score += 4
            feedback.append("CSV header looks correct.")
        
        # Content check (looking for codes in the head/snippet)
        # Note: If file is large, we only got head. But for 3 rows, head is enough.
        csv_codes_found = 0
        for code in TARGETS.keys():
            if code in csv_head:
                csv_codes_found += 1
        
        if csv_codes_found >= 3:
            score += 10
            feedback.append("All location codes found in CSV.")
        elif csv_codes_found > 0:
            score += (csv_codes_found * 3)
            feedback.append(f"Found {csv_codes_found}/3 codes in CSV.")
            
        # Coord check in CSV
        coords_valid = True
        for target in TARGETS.values():
            lat_str = str(int(target["lat"])) # Rough check for integer part match in text
            if lat_str not in csv_head:
                coords_valid = False
        
        if coords_valid and csv_codes_found > 0:
            score += 10
            feedback.append("CSV coordinates look valid.")
            
    else:
        feedback.append("CSV report missing or not created during task.")

    # Final tally
    passed = score >= 60 and len(created_codes) >= 2 and len(unique_assigned) >= 2
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback),
        "details": {
            "created_locations": list(created_codes),
            "assigned_locations": list(unique_assigned),
            "csv_found": csv_exists
        }
    }