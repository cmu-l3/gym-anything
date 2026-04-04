#!/usr/bin/env python3
"""
Verifier for distance_to_coast_south_america task.
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_distance_to_coast_south_america(traj, env_info, task_info):
    """
    Verify the South American cities distance calculation task.
    
    Criteria:
    1. Output CSV exists and is newly created.
    2. CSV is valid and contains Name and Distance columns.
    3. Row count reflects filtering (approx 40-60 cities for SA in simple dataset).
    4. Data filtering: Should NOT contain Paris or Tokyo.
    5. Accuracy: Check distances for known cities against benchmarks.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function unavailable"}

    metadata = task_info.get('metadata', {})
    benchmarks = metadata.get('benchmark_cities', {})

    # Load result
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    logger.info(f"Task result: {result}")

    score = 0
    feedback_parts = []
    
    # 1. File Existence & Freshness (20 pts)
    if result.get("file_exists") and result.get("is_new"):
        score += 20
        feedback_parts.append("New output file found")
    elif result.get("file_exists"):
        score += 10
        feedback_parts.append("Output file found (timestamp unclear)")
    else:
        return {"passed": False, "score": 0, "feedback": "Output file not found"}

    # 2. CSV Validity & Schema (20 pts)
    if result.get("valid_csv"):
        score += 10
        if result.get("has_name_col") and result.get("has_dist_col"):
            score += 10
            feedback_parts.append("Valid CSV with required columns")
        else:
            feedback_parts.append("CSV missing required columns (Name or Distance)")
    else:
        feedback_parts.append("Invalid CSV format")

    # 3. Filtering Correctness (20 pts)
    row_count = result.get("row_count", 0)
    has_non_sa = result.get("has_non_sa_cities", False)
    
    # In ne_10m_populated_places_simple, SA has roughly 40-50 cities. Global is ~240.
    # Acceptable range 10-100 to allow for different filtering methods (e.g. strict continent vs bounding box)
    if 10 <= row_count <= 100 and not has_non_sa:
        score += 20
        feedback_parts.append(f"Row count reasonable ({row_count}) and filtered correctly")
    elif row_count > 150:
        feedback_parts.append(f"Row count too high ({row_count}), likely didn't filter for South America")
    elif has_non_sa:
        feedback_parts.append("Found non-South American cities (e.g. Paris/Tokyo) in output")
    else:
        score += 5 # Partial credit if count is weird but no obvious bad cities
        feedback_parts.append(f"Row count {row_count} unexpected")

    # 4. Data Accuracy (40 pts)
    samples = result.get("city_samples", {})
    valid_samples = 0
    total_checks = 0
    
    for city, bounds in benchmarks.items():
        if city in samples:
            val = samples[city]
            # Check if value is reasonable (km)
            # Some might export meters. If value > 10000, assumes meters and divides by 1000
            if val > 10000: 
                val = val / 1000.0
                
            if bounds["min_km"] <= val <= bounds["max_km"]:
                valid_samples += 1
                feedback_parts.append(f"{city}: {val:.1f}km (OK)")
            else:
                feedback_parts.append(f"{city}: {val:.1f}km (Out of range {bounds['min_km']}-{bounds['max_km']})")
            total_checks += 1
    
    if total_checks > 0:
        accuracy_score = (valid_samples / total_checks) * 40
        score += int(accuracy_score)
    else:
        feedback_parts.append("No benchmark cities found in output to verify accuracy")

    passed = score >= 65 and result.get("file_exists")
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }