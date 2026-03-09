#!/usr/bin/env python3
"""
Verifier for supply_chain_hub_lines task.
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_supply_chain_hub_lines(traj, env_info, task_info):
    """
    Verify supply chain hub analysis results.
    
    Scoring Criteria:
    1. Output file exists & new (10 pts)
    2. Valid GeoJSON & LineStrings (10 pts)
    3. Correct feature count (6 lines) (20 pts)
    4. Geometric Connectivity (lines connect Stores to Warehouses) (30 pts)
    5. Optimality (lines connect to the NEAREST warehouse) (20 pts)
    6. Attribute Transfer (HubName present) (10 pts)
    
    Pass Threshold: 60 points
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function unavailable"}

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
    analysis = result.get('analysis', {})
    
    # 1. File Existence & Freshness (10 pts)
    if result.get('file_exists') and result.get('file_new'):
        score += 10
        feedback_parts.append("New output file created")
    elif result.get('file_exists'):
        score += 5
        feedback_parts.append("Output file exists (but timestamp check failed/ambiguous)")
    else:
        return {"passed": False, "score": 0, "feedback": "Output file not found"}

    # 2. Format Validity (10 pts)
    if analysis.get('valid_geojson') and analysis.get('all_linestrings'):
        score += 10
        feedback_parts.append("Valid GeoJSON Lines")
    elif analysis.get('valid_geojson'):
        score += 5
        feedback_parts.append("Valid GeoJSON but wrong geometry type")
    else:
        feedback_parts.append("Invalid GeoJSON")

    # 3. Feature Count (20 pts)
    count = analysis.get('feature_count', 0)
    expected = 6
    if count == expected:
        score += 20
        feedback_parts.append(f"Correct feature count ({count})")
    elif count > 0:
        partial = int(20 * (count / expected))
        score += partial
        feedback_parts.append(f"Partial feature count: {count}/{expected}")
    else:
        feedback_parts.append("Empty output")

    # 4. Geometric Connectivity (30 pts)
    valid_conn = analysis.get('valid_connections_count', 0)
    if valid_conn == expected:
        score += 30
        feedback_parts.append("All stores connected to warehouses")
    elif valid_conn > 0:
        partial = int(30 * (valid_conn / expected))
        score += partial
        feedback_parts.append(f"Partial connectivity: {valid_conn}/{expected}")

    # 5. Optimality (20 pts)
    optimal = analysis.get('optimal_connections_count', 0)
    if optimal == expected:
        score += 20
        feedback_parts.append("All routes optimal (nearest hub)")
    elif optimal > 0:
        partial = int(20 * (optimal / expected))
        score += partial
        feedback_parts.append(f"Partial optimality: {optimal}/{expected}")

    # 6. Attributes (10 pts)
    if analysis.get('has_hub_attribute'):
        score += 10
        feedback_parts.append("Hub attributes transferred")
    else:
        feedback_parts.append("Missing hub attributes")

    passed = score >= 60

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }