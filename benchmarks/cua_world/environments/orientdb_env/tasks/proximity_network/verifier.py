#!/usr/bin/env python3
"""
Verifier for Proximity Network task.

Checks:
1. Schema: NearBy edge class exists with Distance (DOUBLE) and City (STRING).
2. Data: Edges link Hotels and Restaurants in the same city.
3. Accuracy: Distance property matches Haversine calculation (Lat/Lon).
4. Report: File exists and lists the pairs.
"""

import json
import math
import os
import base64
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def haversine_km(lat1, lon1, lat2, lon2):
    """Calculate the great circle distance in kilometers between two points."""
    R = 6371  # Earth radius in km
    dlat = math.radians(lat2 - lat1)
    dlon = math.radians(lon2 - lon1)
    a = (math.sin(dlat / 2) ** 2 +
         math.cos(math.radians(lat1)) * math.cos(math.radians(lat2)) *
         math.sin(dlon / 2) ** 2)
    c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a))
    return R * c

def verify_proximity_network(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result JSON
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

    score = 0
    feedback_parts = []
    
    # --- 1. Schema Verification (20 pts) ---
    schema = result.get('schema', {})
    classes = {c['name']: c for c in schema.get('classes', [])}
    nearby_cls = classes.get('NearBy')
    
    schema_ok = False
    if nearby_cls:
        super_cls = nearby_cls.get('superClass', '') or nearby_cls.get('superClasses', [])
        if 'E' in super_cls or super_cls == 'E':
            props = {p['name']: p['type'] for p in nearby_cls.get('properties', [])}
            if props.get('Distance') == 'DOUBLE' and props.get('City') == 'STRING':
                score += 20
                feedback_parts.append("Schema Correct (NearBy extends E, props valid)")
                schema_ok = True
            else:
                feedback_parts.append(f"NearBy properties incorrect. Found: {props}")
                score += 10 # Partial credit for class existence
        else:
            feedback_parts.append("NearBy class exists but does not extend E")
            score += 5
    else:
        feedback_parts.append("NearBy class not found")

    # --- 2. Edge Data Verification (60 pts) ---
    edges_result = result.get('edges_data', {}).get('result', [])
    
    valid_edges_count = 0
    accurate_distances = 0
    correct_city_match = 0
    
    # We expect roughly 11 pairs based on the dataset
    expected_pairs_min = 8
    
    for edge in edges_result:
        # Check 1: City Consistency
        h_city = edge.get('HotelCity')
        r_city = edge.get('RestCity')
        e_city = edge.get('City')
        
        if h_city and r_city and h_city == r_city and e_city == h_city:
            correct_city_match += 1
        
        # Check 2: Distance Accuracy
        try:
            h_lat = float(edge.get('HotelLat', 0))
            h_lon = float(edge.get('HotelLon', 0))
            r_lat = float(edge.get('RestLat', 0))
            r_lon = float(edge.get('RestLon', 0))
            stored_dist = float(edge.get('Distance', -1))
            
            calc_dist = haversine_km(h_lat, h_lon, r_lat, r_lon)
            
            # Allow 20% tolerance (approximate calculation vs precise)
            if stored_dist > 0 and abs(stored_dist - calc_dist) / (calc_dist + 0.001) < 0.2:
                accurate_distances += 1
            else:
                pass # print(f"Dist mismatch: Stored {stored_dist}, Calc {calc_dist}")
                
            valid_edges_count += 1
        except (ValueError, TypeError):
            continue

    # Scoring Edges
    if valid_edges_count >= expected_pairs_min:
        score += 15
        feedback_parts.append(f"Found {valid_edges_count} valid edges")
    elif valid_edges_count > 0:
        score += 5
        feedback_parts.append(f"Found {valid_edges_count} edges (expected >={expected_pairs_min})")
    
    if correct_city_match >= expected_pairs_min:
        score += 10
        feedback_parts.append("City properties match correctly")
        
    if accurate_distances >= expected_pairs_min:
        score += 35
        feedback_parts.append(f"Distance calculations accurate for {accurate_distances} edges")
    elif accurate_distances > 0:
        score += 10
        feedback_parts.append(f"Some distances accurate ({accurate_distances})")
    else:
        feedback_parts.append("Distance calculations missing or inaccurate")

    # --- 3. Report Verification (20 pts) ---
    report = result.get('report', {})
    if report.get('exists') and report.get('created_during_task'):
        try:
            content = base64.b64decode(report.get('content_base64', '')).decode('utf-8', errors='ignore')
            lines = [l for l in content.split('\n') if l.strip()]
            
            # Check for format "City | Hotel -> Rest | Dist"
            valid_lines = 0
            has_total = False
            for line in lines:
                if '->' in line and '|' in line:
                    valid_lines += 1
                if 'Total pairs:' in line:
                    has_total = True
            
            if valid_lines >= expected_pairs_min:
                score += 10
                feedback_parts.append("Report content valid")
            if has_total:
                score += 10
                feedback_parts.append("Report summary present")
                
        except Exception:
            feedback_parts.append("Report file could not be parsed")
    else:
        feedback_parts.append("Report file not created or not updated")

    # Final check
    passed = score >= 60 and schema_ok and valid_edges_count >= expected_pairs_min

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }