#!/usr/bin/env python3
"""
Verifier for country_dashboard_materialization task.

Criteria:
1. Class 'CountryDashboard' exists (10 pts)
2. Properties exist with correct types (20 pts)
3. UNIQUE index exists on CountryName (10 pts)
4. Data is populated (>5 records) (10 pts)
5. Data accuracy check (Hotels count, Restaurant count, Avg Stars) (50 pts)
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_country_dashboard_materialization(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Retrieve result file
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    inspection = result.get("inspection", {})
    score = 0
    feedback_parts = []
    
    # --- Criterion 1: Class Existence (10 pts) ---
    if inspection.get("class_exists"):
        score += 10
        feedback_parts.append("Class 'CountryDashboard' created.")
    else:
        return {"passed": False, "score": 0, "feedback": "Class 'CountryDashboard' not found."}

    # --- Criterion 2: Properties (20 pts) ---
    props = inspection.get("properties", {})
    required_props = {
        "CountryName": "STRING",
        "HotelCount": "INTEGER",
        "AvgHotelStars": "DOUBLE",
        "RestaurantCount": "INTEGER"
    }
    
    props_score = 0
    for name, expected_type in required_props.items():
        if name in props:
            # Type check (loose check for numeric types as OrientDB maps them variably sometimes)
            actual_type = props[name].upper()
            if actual_type == expected_type:
                props_score += 5
            elif expected_type == "DOUBLE" and actual_type in ["FLOAT", "DECIMAL"]:
                 props_score += 5 # forgive float/double mismatch
            elif expected_type == "INTEGER" and actual_type in ["LONG", "SHORT"]:
                 props_score += 5 # forgive int size mismatch
            else:
                 feedback_parts.append(f"Property {name} type mismatch ({actual_type} vs {expected_type}).")
        else:
            feedback_parts.append(f"Missing property: {name}.")
    
    score += props_score
    if props_score == 20:
        feedback_parts.append("All properties correct.")

    # --- Criterion 3: Index (10 pts) ---
    indexes = inspection.get("indexes", [])
    index_found = False
    for idx in indexes:
        # Check if it covers CountryName and is UNIQUE
        # Note: OrientDB index fields might be reported as ["CountryName"]
        fields = idx.get("fields", [])
        if "CountryName" in fields and idx.get("type") == "UNIQUE":
            index_found = True
            break
        # Also check name-based convention just in case fields aren't populated in all versions
        if "CountryDashboard.CountryName" in idx.get("name") and idx.get("type") == "UNIQUE":
            index_found = True
            break
            
    if index_found:
        score += 10
        feedback_parts.append("Unique index on CountryName found.")
    else:
        feedback_parts.append("Missing UNIQUE index on CountryName.")

    # --- Criterion 4: Population Count (10 pts) ---
    record_count = inspection.get("record_count", 0)
    if record_count >= 5:
        score += 10
        feedback_parts.append(f"Table populated with {record_count} records.")
    else:
        feedback_parts.append(f"Insufficient records populated ({record_count} < 5).")

    # --- Criterion 5: Data Accuracy (50 pts) ---
    # We verify against the ground truth computed in the export script
    ground_truth = inspection.get("ground_truth", {})
    samples = inspection.get("data_samples", [])
    
    accuracy_score = 0
    # Evaluate up to 5 samples
    samples_to_check = [s for s in samples if s.get("CountryName") in ground_truth][:5]
    
    if not samples_to_check:
        feedback_parts.append("No valid samples matching ground truth countries found for accuracy check.")
    else:
        points_per_sample = 50 / len(samples_to_check)
        
        for sample in samples_to_check:
            country = sample.get("CountryName")
            gt = ground_truth.get(country)
            
            # Check Hotel Count
            h_ok = sample.get("HotelCount") == gt["h"]
            
            # Check Restaurant Count
            r_ok = sample.get("RestaurantCount") == gt["r"]
            
            # Check Avg Stars (tolerance 0.1)
            # Handle None/nulls gracefully
            s_val = sample.get("AvgHotelStars", 0) or 0
            gt_val = gt["avg"] or 0
            a_ok = abs(float(s_val) - float(gt_val)) < 0.1
            
            if h_ok and r_ok and a_ok:
                accuracy_score += points_per_sample
            else:
                feedback_parts.append(f"Data mismatch for {country} (Exp: H={gt['h']} R={gt['r']} A={gt['avg']:.2f}, Got: H={sample.get('HotelCount')} R={sample.get('RestaurantCount')} A={sample.get('AvgHotelStars')})")

    score += int(accuracy_score)
    if int(accuracy_score) == 50:
        feedback_parts.append("Data accuracy verified.")

    # Final result
    passed = (score >= 60) and (inspection.get("class_exists")) and (record_count >= 5)
    
    return {
        "passed": passed,
        "score": min(100, score),
        "feedback": " ".join(feedback_parts)
    }