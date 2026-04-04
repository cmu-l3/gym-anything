#!/usr/bin/env python3
"""
Verifier for compute_trending_score task.
Verifies:
1. Schema: Hotels.TrendingScore property exists and is DOUBLE.
2. Logic: TrendingScore value matches the average of the 5 most recent reviews.
"""

import json
import os
import tempfile
import logging
from datetime import datetime

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def parse_orientdb_date(date_str):
    """
    Parse OrientDB date string. 
    Format is typically YYYY-MM-DD or YYYY-MM-DD HH:MM:SS depending on precision.
    DemoDB usually uses YYYY-MM-DD.
    """
    if not date_str:
        return datetime.min
    try:
        # Try full datetime
        return datetime.strptime(date_str, "%Y-%m-%d %H:%M:%S")
    except ValueError:
        try:
            # Try date only
            return datetime.strptime(date_str, "%Y-%m-%d")
        except ValueError:
            return datetime.min

def calculate_expected_score(reviews):
    """
    Calculate the expected Trending Score:
    - Sort reviews by Date descending.
    - Take top 5.
    - Average their Stars.
    """
    if not reviews:
        return None

    # Sort reviews: newest first
    # We need to handle potential string/datetime types
    sorted_reviews = sorted(
        reviews, 
        key=lambda r: parse_orientdb_date(r.get("Date")), 
        reverse=True
    )
    
    # Take top 5
    recent_reviews = sorted_reviews[:5]
    
    # Calculate average
    total_stars = sum(r.get("Stars", 0) for r in recent_reviews)
    count = len(recent_reviews)
    
    if count == 0:
        return None
        
    return total_stars / count

def verify_compute_trending_score(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    # Copy result file
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
            
    db_data = result.get("db_data", {})
    
    score = 0
    feedback = []
    
    # 1. Verify Schema (20 points)
    if db_data.get("schema_correct"):
        score += 20
        feedback.append("Schema check passed: 'TrendingScore' property exists.")
        
        # Check type (DOUBLE or FLOAT)
        prop_type = db_data.get("property_type", "").upper()
        if prop_type in ["DOUBLE", "FLOAT"]:
            score += 10
            feedback.append(f"Property type correct ({prop_type}).")
        else:
            feedback.append(f"Warning: Property type is '{prop_type}', expected DOUBLE.")
    else:
        feedback.append("Schema check failed: 'TrendingScore' property not found on Hotels class.")
        return {"passed": False, "score": 0, "feedback": " ".join(feedback)}

    # 2. Verify Logic (70 points)
    hotels_data = db_data.get("hotels_data", [])
    if not hotels_data:
        return {"passed": False, "score": score, "feedback": "No hotel data found to verify."}

    correct_counts = 0
    total_checked = 0
    
    for hotel in hotels_data:
        name = hotel.get("name")
        actual_score = hotel.get("trending_score")
        reviews = hotel.get("reviews", [])
        
        expected_score = calculate_expected_score(reviews)
        
        total_checked += 1
        
        # Comparison Logic
        matches = False
        if expected_score is None:
            # If expected is None, actual should be None or 0
            if actual_score is None or actual_score == 0:
                matches = True
        elif actual_score is not None:
            try:
                # Allow small floating point tolerance
                if abs(float(actual_score) - float(expected_score)) < 0.01:
                    matches = True
            except (ValueError, TypeError):
                matches = False
        
        if matches:
            correct_counts += 1
        else:
            # Add detail for the first failure only to avoid spam
            if len(feedback) < 5: 
                feedback.append(f"Mismatch for '{name}': Expected {expected_score}, Got {actual_score}.")

    # Scoring Logic
    # 70 points allocated for data correctness
    if total_checked > 0:
        accuracy = correct_counts / total_checked
        data_points = int(accuracy * 70)
        score += data_points
        feedback.append(f"Data verification: {correct_counts}/{total_checked} hotels correct.")
    
    passed = score >= 80
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }