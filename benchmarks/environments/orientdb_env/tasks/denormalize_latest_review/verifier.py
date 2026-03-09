#!/usr/bin/env python3
"""
Verifier for denormalize_latest_review task.
"""

import json
import os
import tempfile
import datetime
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_denormalize_latest_review(traj, env_info, task_info):
    """
    Verifies that the LatestReview property was created and populated correctly.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Retrieve result file
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

    if result.get("error"):
        return {"passed": False, "score": 0, "feedback": f"Export error: {result['error']}"}

    score = 0
    feedback = []
    
    # 1. Schema Verification (30 pts)
    schema = result.get("schema_check", {})
    if schema.get("property_exists"):
        score += 20
        feedback.append("Property 'LatestReview' exists.")
        
        p_type = schema.get("property_type")
        if p_type in ["EMBEDDED", "EMBEDDEDMAP"]:
            score += 10
            feedback.append(f"Property type is correct ({p_type}).")
        else:
            feedback.append(f"Incorrect property type: {p_type} (Expected EMBEDDED or EMBEDDEDMAP).")
    else:
        feedback.append("Property 'LatestReview' was NOT created on Hotels class.")

    # 2. Data Verification (70 pts)
    data = result.get("data_check", {})
    actual = data.get("actual_value")
    expected = data.get("expected_value")

    if actual is None:
        feedback.append("No data found in 'LatestReview' for test hotel.")
    elif isinstance(actual, dict):
        # Check structure
        keys = set(k.lower() for k in actual.keys())
        required_keys = {"stars", "text", "date"}
        
        if required_keys.issubset(keys):
            score += 20
            feedback.append("Embedded object structure is correct.")
            
            # Content verification
            if expected:
                # Compare fields loosely (handling potential type diffs like strings vs dates)
                # Note: Date formats might differ, so we look for equality or substring match
                matches = 0
                total_fields = 0
                
                # Check Stars
                if str(actual.get("stars")) == str(expected.get("stars")):
                    matches += 1
                total_fields += 1
                
                # Check Text (exact match)
                if actual.get("text") == expected.get("text"):
                    matches += 1
                total_fields += 1
                
                # Check Date
                act_date = str(actual.get("date"))
                exp_date = str(expected.get("date"))
                if act_date.split(" ")[0] == exp_date.split(" ")[0]: # Compare YYYY-MM-DD
                    matches += 1
                total_fields += 1
                
                if matches == total_fields:
                    score += 50
                    feedback.append("Data content matches exactly (correct latest review).")
                else:
                    # Partial credit for data presence but wrong values (maybe not sorted by date?)
                    score += 20
                    feedback.append(f"Data present but values mismatch. Actual: {actual}, Expected: {expected}")
            else:
                # Fallback if expected data missing (shouldn't happen with robust setup)
                score += 50
                feedback.append("Data present (Ground truth missing for comparison).")
        else:
            feedback.append(f"Missing required fields. Found: {list(actual.keys())}")
    else:
        feedback.append(f"Invalid data format in 'LatestReview'. Expected JSON object, got: {type(actual)}")

    passed = score >= 70
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }