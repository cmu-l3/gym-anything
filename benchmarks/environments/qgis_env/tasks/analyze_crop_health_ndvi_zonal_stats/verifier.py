#!/usr/bin/env python3
"""
Verifier for analyze_crop_health_ndvi_zonal_stats task.
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_analyze_crop_health_ndvi_zonal_stats(traj, env_info, task_info):
    """
    Verify that NDVI was calculated and Zonal Statistics were aggregated.
    
    Criteria:
    1. NDVI Raster created and values are in valid NDVI range (-1 to 1). (50 pts)
    2. Vector output created with new statistics attribute. (50 pts)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function unavailable"}

    metadata = task_info.get('metadata', {})
    ground_truth = metadata.get('ground_truth_means', {})
    tolerance = metadata.get('tolerance', 0.1)

    try:
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/task_result.json", temp_file.name)
            with open(temp_file.name, 'r') as f:
                result = json.load(f)
        finally:
            os.unlink(temp_file.name)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}

    logger.info(f"Task result: {result}")

    score = 0
    feedback_parts = []
    
    # ---------------------------------------------------------
    # 1. Raster Verification (50 points)
    # ---------------------------------------------------------
    raster_exists = result.get('raster_exists', False)
    raster_stats = result.get('raster_stats', {})
    
    if raster_exists:
        score += 20
        feedback_parts.append("NDVI Raster created")
        
        if raster_stats.get('valid', False):
            # Check range
            if raster_stats.get('valid_range', False):
                score += 30
                feedback_parts.append("NDVI values in valid range (-1 to 1)")
            else:
                score += 10 # Partial credit if file exists but values are weird
                feedback_parts.append(f"NDVI values out of range (Min: {raster_stats.get('min'):.2f}, Max: {raster_stats.get('max'):.2f})")
        else:
            feedback_parts.append("Raster file invalid")
    else:
        feedback_parts.append("NDVI Raster NOT created")

    # ---------------------------------------------------------
    # 2. Vector Verification (50 points)
    # ---------------------------------------------------------
    vector_exists = result.get('vector_exists', False)
    vector_stats = result.get('vector_stats', {})
    
    if vector_exists:
        score += 10
        feedback_parts.append("Output vector file created")
        
        if vector_stats.get('valid', False):
            if vector_stats.get('has_mean_field', False):
                score += 20
                feedback_parts.append(f"Found statistics field: {vector_stats.get('field_name')}")
                
                # Verify Values against Ground Truth
                # Field A: ~0.77, Field B: ~0.25, Field C: ~-0.5
                extracted_values = vector_stats.get('values', {})
                matches = 0
                total_fields = len(ground_truth)
                
                for field_name, expected_val in ground_truth.items():
                    actual_val = extracted_values.get(field_name)
                    if actual_val is not None:
                        diff = abs(actual_val - expected_val)
                        if diff <= tolerance:
                            matches += 1
                        else:
                            logger.info(f"Field {field_name} mismatch: expected {expected_val}, got {actual_val}")
                
                if matches >= 2: # Allow some leniency
                    score += 20
                    feedback_parts.append(f"Zonal statistics values accurate ({matches}/{total_fields} matched)")
                elif matches > 0:
                    score += 10
                    feedback_parts.append(f"Zonal statistics values partially accurate ({matches}/{total_fields} matched)")
                else:
                    feedback_parts.append("Zonal statistics values do not match expected NDVI patterns")
            else:
                feedback_parts.append("No statistics/mean attribute found in vector output")
        else:
            feedback_parts.append("Vector file is invalid GeoJSON")
    else:
        feedback_parts.append("Output vector file NOT created")

    passed = score >= 70

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }