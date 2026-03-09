#!/usr/bin/env python3
"""
Verifier for Hazardous Gas Evolution Profiling task.
Checks if the agent correctly identified gas byproducts using CAMEO Chemicals.
"""

import json
import csv
import os
import tempfile
import logging
from typing import List, Dict, Any

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_hazardous_gas_evolution_profiling(traj, env_info, task_info):
    """
    Verifies the content of the generated CSV report.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_results = metadata.get('expected_results', [])
    
    # Load result metadata from export_result.sh
    temp_result_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result_json.name)
        with open(temp_result_json.name, 'r') as f:
            task_result = json.load(f)
    except Exception as e:
        if os.path.exists(temp_result_json.name):
            os.unlink(temp_result_json.name)
        return {"passed": False, "score": 0, "feedback": f"Failed to read task result: {e}"}
    
    if os.path.exists(temp_result_json.name):
        os.unlink(temp_result_json.name)

    # Check existence
    if not task_result.get('output_exists', False):
        return {"passed": False, "score": 0, "feedback": "Output CSV file not found."}
    
    if not task_result.get('file_created_during_task', False):
        return {"passed": False, "score": 0, "feedback": "Output file was not created during the task session (anti-gaming check failed)."}

    # Copy the actual CSV file
    output_path = task_result.get('output_path', '/home/ga/Desktop/sensor_selection_report.csv')
    temp_csv = tempfile.NamedTemporaryFile(delete=False, suffix='.csv')
    
    try:
        copy_from_env(output_path, temp_csv.name)
        
        # Parse CSV
        rows = []
        with open(temp_csv.name, 'r', encoding='utf-8', errors='replace') as f:
            reader = csv.reader(f)
            header = next(reader, None)
            if header:
                # Normalize header for robustness
                header = [h.strip().lower() for h in header]
                
                # Map columns
                try:
                    area_idx = -1
                    gas_idx = -1
                    for i, col in enumerate(header):
                        if 'area' in col:
                            area_idx = i
                        elif 'gas' in col or 'evolved' in col or 'name' in col:
                            # Prefer 'evolved_gas_name' if multiple 'name' cols exist, but fallback is ok
                            if 'chemical' not in col: 
                                gas_idx = i
                    
                    if area_idx == -1 or gas_idx == -1:
                        # Fallback: assume fixed structure Area, ChemA, ChemB, Gas
                        area_idx = 0
                        gas_idx = 3
                        
                    for row in reader:
                        if len(row) > max(area_idx, gas_idx):
                            rows.append({
                                'area': row[area_idx].strip(),
                                'gas': row[gas_idx].strip().lower()
                            })
                except Exception as e:
                     return {"passed": False, "score": 10, "feedback": f"Error parsing CSV structure: {e}. Ensure headers are correct."}
            else:
                return {"passed": False, "score": 10, "feedback": "CSV file is empty or missing headers."}

    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read CSV file: {e}"}
    finally:
        if os.path.exists(temp_csv.name):
            os.unlink(temp_csv.name)

    # Scoring
    score = 20 # Base points for file existence and readability
    feedback_parts = ["File created and readable"]
    
    correct_identifications = 0
    total_scenarios = len(expected_results)
    
    for expected in expected_results:
        area_label = expected['area']
        keywords = expected['gas_keywords']
        
        # Find matching row
        found_gas = None
        for row in rows:
            # Flexible matching for "Area 1", "1", "Area 1:" etc.
            if area_label.lower() in row['area'].lower() or row['area'].strip() == area_label.split()[-1]:
                found_gas = row['gas']
                break
        
        if found_gas:
            # Check if any keyword is in the found gas string
            # Logic: If user writes "Chloramine gas", it matches "chloramine"
            # Logic: If user writes "Generates Chloramine", it matches "chloramine"
            is_match = any(k in found_gas for k in keywords)
            
            # Special check for Hydrogen vs Hydrogen Sulfide/Cyanide uniqueness
            # If expected is "Hydrogen" (Area 4), ensure they didn't write "Hydrogen Sulfide"
            if "hydrogen" in keywords and "sulfide" not in keywords and "cyanide" not in keywords:
                if "sulfide" in found_gas or "cyanide" in found_gas:
                    is_match = False
            
            if is_match:
                correct_identifications += 1
                feedback_parts.append(f"✓ {area_label}: Correct")
            else:
                feedback_parts.append(f"✗ {area_label}: Incorrect gas '{found_gas}' (Expected {keywords[0]})")
        else:
            feedback_parts.append(f"✗ {area_label}: Not found in CSV")

    # Calculate score
    # 20 pts base + (80 pts * fraction correct)
    scenario_points = 80.0 / total_scenarios if total_scenarios > 0 else 0
    score += int(correct_identifications * scenario_points)
    
    # Pass threshold: 74 as defined in description (4/5 correct + file structure)
    passed = score >= 74
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }