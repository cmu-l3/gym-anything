#!/usr/bin/env python3
"""
Verifier for Global Parameter Formulas task.

Verification Strategy:
1. Primary: Verify global parameters exist in the Derby database with correct values/formulas.
2. Secondary: Verify the exported CSV file exists and contains correct data.
3. Tertiary: VLM verification of the workflow.
"""

import json
import os
import tempfile
import logging
import base64
import re
import csv
import io

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Expected values
EXPECTED_PARAMS = {
    "annual_production": {"val": 1000000.0, "type": "input"},
    "bottle_weight_g": {"val": 25.0, "type": "input"},
    "total_resin_kg": {"val": 25000.0, "type": "dependent"},
    "recycled_content_pct": {"val": 30.0, "type": "input"},
    "virgin_resin_kg": {"val": 17500.0, "type": "dependent"},
    "recycled_resin_kg": {"val": 7500.0, "type": "dependent"}
}

TRAJECTORY_PROMPT = """You are reviewing screenshots of an agent creating global parameters in openLCA.

The expected workflow:
1. Open the "Global Parameters" or "Parameters" editor (often from the Navigation tree or Database menu).
2. Create new parameters (entering names like 'annual_production', 'total_resin_kg').
3. Enter values for input parameters.
4. Enter formulas for dependent parameters (e.g., 'A * B').
5. Export the list to a file.

Assess:
- EDITOR_OPENED: Was the parameter editor visible?
- FORMULAS_ENTERED: Did you see formulas being typed or visible in the 'Formula' column?
- VALUES_CALCULATED: Did the 'Value' column show calculated numbers?
- EXPORT_ACTION: Was there an export action or file saving?

Return JSON:
{
  "editor_opened": true/false,
  "formulas_entered": true/false,
  "values_calculated": true/false,
  "export_action": true/false,
  "confidence": "low"/"medium"/"high"
}"""

def parse_derby_output(raw_output):
    """
    Parse raw text output from Derby ij query.
    Expected format is table-like with headers.
    """
    if not raw_output:
        return []
    
    params = []
    lines = raw_output.splitlines()
    # Skip headers and empty lines, looking for data rows
    # Derby output often looks like:
    # NAME           |VALUE          |FORMULA        |IS_IN&
    # ------------------------------------------------------
    # annual_product&|1.0E7          |NULL           |1
    
    # Simple regex extraction for now
    for line in lines:
        if line.strip().startswith('NAME') or line.strip().startswith('--'):
            continue
        if not line.strip():
            continue
            
        parts = [p.strip() for p in line.split('|')]
        if len(parts) >= 2:
            try:
                name = parts[0].strip()
                # Remove Derby truncation markers '&'
                if name.endswith('&'): name = name[:-1]
                
                val_str = parts[1].strip()
                if val_str.endswith('&'): val_str = val_str[:-1]
                
                formula = ""
                if len(parts) > 2:
                    formula = parts[2].strip()
                    if formula == 'NULL': formula = ""
                
                is_input = False
                if len(parts) > 3:
                    is_input = ('1' in parts[3] or 'true' in parts[3].lower())

                try:
                    val = float(val_str)
                except ValueError:
                    val = 0.0

                params.append({
                    "name": name,
                    "value": val,
                    "formula": formula,
                    "is_input": is_input
                })
            except Exception as e:
                pass # Skip malformed lines
    return params

def verify_global_parameter_formulas(traj, env_info, task_info):
    """Verify global parameter task."""
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    # Load result JSON
    temp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp.name)
        with open(temp.name) as f:
            result = json.load(f)
    except FileNotFoundError:
        return {"passed": False, "score": 0, "feedback": "Result file not found"}
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Cannot read result: {e}"}
    finally:
        if os.path.exists(temp.name):
            os.unlink(temp.name)

    score = 0
    feedback = []
    
    # ── Verify DB Content (Primary) ──
    db_raw_b64 = result.get("db_params_raw_b64", "")
    db_params = []
    if db_raw_b64:
        try:
            db_raw = base64.b64decode(db_raw_b64).decode('utf-8', errors='ignore')
            db_params = parse_derby_output(db_raw)
        except Exception as e:
            logger.warning(f"Failed to decode DB output: {e}")

    # Check for expected parameters in DB
    found_params_count = 0
    correct_values_count = 0
    formulas_present_count = 0
    
    for expected_name, expected_data in EXPECTED_PARAMS.items():
        found = False
        for p in db_params:
            # Flexible matching for names (case insensitive, ignore truncation)
            if expected_name.lower() in p['name'].lower():
                found = True
                found_params_count += 1
                
                # Check value (within 1% tolerance)
                if abs(p['value'] - expected_data['val']) < (expected_data['val'] * 0.01):
                    correct_values_count += 1
                else:
                    feedback.append(f"Param '{expected_name}' value mismatch: found {p['value']}, expected {expected_data['val']}")
                
                # Check formula presence for dependent params
                if expected_data['type'] == 'dependent':
                    if p['formula'] and len(p['formula']) > 2:
                        formulas_present_count += 1
                    else:
                        feedback.append(f"Param '{expected_name}' missing formula")
                break
        if not found:
            feedback.append(f"Missing parameter: {expected_name}")

    # Scoring for DB content (Max 60 pts)
    # 10 pts per parameter existing with correct value
    score += (correct_values_count * 10)
    
    # ── Verify CSV File (Secondary) ──
    csv_exists = result.get("csv_exists", False)
    csv_content_b64 = result.get("csv_content_b64", "")
    
    csv_score = 0
    if csv_exists:
        csv_score += 10 # File exists
        if result.get("csv_created_during_task", False):
            csv_score += 10 # Created fresh
            
        # Content check
        if csv_content_b64:
            try:
                csv_content = base64.b64decode(csv_content_b64).decode('utf-8', errors='ignore')
                # Simple check for keywords in CSV
                matches = 0
                for expected_name in EXPECTED_PARAMS.keys():
                    if expected_name in csv_content:
                        matches += 1
                if matches >= 6:
                    csv_score += 20
                elif matches >= 3:
                    csv_score += 10
            except:
                pass
    
    score += csv_score
    feedback.append(f"CSV Check: {csv_score} points")

    # ── VLM Verification (Tertiary) ──
    # Only if we are borderline or for extra confidence
    # (Assuming VLM utils are available via global scope injection or similar in framework)
    # Skipping actual VLM call implementation here to keep verifier self-contained, 
    # but the logic would go here adding up to 10 points.
    
    final_passed = score >= 60 and found_params_count >= 3
    
    return {
        "passed": final_passed,
        "score": min(100, score),
        "feedback": "; ".join(feedback)
    }