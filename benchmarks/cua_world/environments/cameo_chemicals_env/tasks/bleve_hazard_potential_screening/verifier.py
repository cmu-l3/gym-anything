#!/usr/bin/env python3
"""
Verifier for BLEVE Hazard Potential Screening Task.

Criteria:
1. File Creation (10 pts): CSV exists and was created during task.
2. Data Accuracy (40 pts): Correct Physical State and Flammability for 5 chemicals.
3. Classification Logic (50 pts): Correct Risk Tier assigned based on the rules.
   - TIER_1: Liquefied Gas + Flammable
   - TIER_2: Liquefied Gas + Non-Flammable
   - TIER_3: Liquid
"""

import json
import csv
import os
import tempfile
import logging
from typing import Dict, Any, List

# Setup logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_bleve_screening(traj: Dict[str, Any], env_info: Dict[str, Any], task_info: Dict[str, Any]) -> Dict[str, Any]:
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System Error: Copy function not available"}

    # Ground Truth Data
    ground_truth = task_info.get('metadata', {}).get('ground_truth', {})
    if not ground_truth:
        return {"passed": False, "score": 0, "feedback": "Configuration Error: Missing ground truth metadata"}

    # 1. Retrieve Result JSON
    temp_result_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result_json.name)
        with open(temp_result_json.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task status: {str(e)}"}
    finally:
        if os.path.exists(temp_result_json.name):
            os.unlink(temp_result_json.name)

    # 2. Check File Existence & Timestamp
    if not result_data.get('output_exists', False):
        return {"passed": False, "score": 0, "feedback": "Output CSV file not found."}
    
    if not result_data.get('file_created_during_task', False):
        return {"passed": False, "score": 0, "feedback": "Output file exists but was not modified during the task (Anti-gaming check failed)."}

    score = 10
    feedback = ["File created successfully."]
    passed = False

    # 3. Retrieve and Parse CSV
    temp_csv = tempfile.NamedTemporaryFile(delete=False, suffix='.csv')
    try:
        copy_from_env("/tmp/bleve_risk_assessment.csv", temp_csv.name)
        
        with open(temp_csv.name, 'r', encoding='utf-8') as f:
            # Handle potentially messy input (BOM, varying delimiters)
            content = f.read().strip()
            if not content:
                return {"passed": False, "score": score, "feedback": "Output file is empty."}
            
            # Simple line-based parsing to be robust against header casing
            lines = content.split('\n')
            if len(lines) < 2:
                return {"passed": False, "score": score, "feedback": "CSV file has insufficient rows (Header + 5 Data rows expected)."}

            # Parse Data
            # Expected header: Chemical, Physical_State, Flammable, Risk_Tier
            reader = csv.DictReader(lines)
            rows = list(reader)

            # Normalize headers if needed (lowercase everything for check)
            if not reader.fieldnames:
                 return {"passed": False, "score": score, "feedback": "Could not parse CSV headers."}
            
            headers_norm = [h.lower().strip() for h in reader.fieldnames]
            required_headers = ['chemical', 'physical_state', 'flammable', 'risk_tier']
            
            for req in required_headers:
                if req not in headers_norm:
                     return {"passed": False, "score": score, "feedback": f"Missing required column: {req}. Found: {reader.fieldnames}"}

            # Map actual headers to normalized keys for lookup
            header_map = {h.lower().strip(): h for h in reader.fieldnames}

            # Evaluation
            correct_data_count = 0
            correct_tier_count = 0
            total_items = len(ground_truth)
            processed_chemicals = set()

            for row in rows:
                # Find chemical name match
                chem_name_raw = row.get(header_map['chemical'], '').strip()
                
                # Fuzzy match chemical name
                matched_key = None
                for gt_key in ground_truth.keys():
                    if gt_key.lower() in chem_name_raw.lower() or chem_name_raw.lower() in gt_key.lower():
                        matched_key = gt_key
                        break
                
                if not matched_key:
                    continue
                
                processed_chemicals.add(matched_key)
                gt = ground_truth[matched_key]
                
                # Extract user values
                user_state = row.get(header_map['physical_state'], '').strip().lower()
                user_flam = row.get(header_map['flammable'], '').strip().lower()
                user_tier = row.get(header_map['risk_tier'], '').strip().upper()

                # Check Data (State + Flammability)
                # Allow some flexibility in state text (e.g. "gas" vs "liquefied gas" if strictly needed, but task asked for specific terms)
                # Task asked for "Liquefied Gas" or "Liquid".
                state_ok = gt['state'].lower() in user_state
                flam_ok = gt['flammable'].lower() == user_flam or (gt['flammable'].lower() == 'yes' and user_flam == 'true') or (gt['flammable'].lower() == 'no' and user_flam == 'false')

                if state_ok and flam_ok:
                    correct_data_count += 1
                else:
                    feedback.append(f"{matched_key}: Data mismatch (Expected {gt['state']}/{gt['flammable']}, Got {user_state}/{user_flam})")

                # Check Classification Tier
                if user_tier == gt['tier']:
                    correct_tier_count += 1
                else:
                    feedback.append(f"{matched_key}: Wrong Tier (Expected {gt['tier']}, Got {user_tier})")

            # Scoring Calculation
            # 40 points for data extraction (8 pts per chemical)
            data_score = (correct_data_count / total_items) * 40
            
            # 50 points for classification (10 pts per chemical)
            tier_score = (correct_tier_count / total_items) * 50

            score += data_score + tier_score

            feedback.append(f"Processed {len(processed_chemicals)}/{total_items} chemicals.")
            if len(processed_chemicals) < total_items:
                missing = set(ground_truth.keys()) - processed_chemicals
                feedback.append(f"Missing chemicals: {', '.join(missing)}")

            # Pass Threshold
            if score >= 95: # Strict threshold for safety tasks
                passed = True
            
            return {
                "passed": passed,
                "score": int(score),
                "feedback": " ".join(feedback)
            }

    except Exception as e:
        return {"passed": False, "score": score, "feedback": f"Error verifying CSV content: {str(e)}"}
    finally:
        if os.path.exists(temp_csv.name):
            os.unlink(temp_csv.name)