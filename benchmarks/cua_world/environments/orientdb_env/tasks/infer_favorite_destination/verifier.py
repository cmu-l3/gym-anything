#!/usr/bin/env python3
"""
Verifier for infer_favorite_destination task.

Checks:
1. Schema: Profiles class has 'FavoriteDestination' property of type STRING.
2. Data Integrity: 'HasStayed' edge count has not decreased (anti-gaming).
3. Correctness: The stored 'FavoriteDestination' matches the calculated mode of visited countries for each profile.
"""

import json
import tempfile
import os
import logging
from collections import Counter

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def calculate_mode(items):
    """Return the most common item. In case of tie, return all tied items."""
    if not items:
        return None
    counts = Counter(items)
    max_freq = max(counts.values())
    return {k for k, v in counts.items() if v == max_freq}

def verify_infer_favorite_destination(traj, env_info, task_info):
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
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # --- Criterion 1: Schema Check (20 pts) ---
    schema = result.get('profiles_schema', {})
    props = {p['name']: p for p in schema.get('properties', [])}
    
    target_prop = props.get('FavoriteDestination')
    if target_prop:
        if target_prop.get('type') == 'STRING':
            score += 20
            feedback_parts.append("Schema property 'FavoriteDestination' (STRING) exists.")
        else:
            score += 10 # Partial credit for wrong type
            feedback_parts.append(f"Schema property exists but type is {target_prop.get('type')}, expected STRING.")
    else:
        feedback_parts.append("Schema property 'FavoriteDestination' NOT found on Profiles class.")

    # --- Criterion 2: Data Integrity / Anti-gaming (10 pts) ---
    initial_edges = int(result.get('initial_edge_count', 0))
    current_edges = int(result.get('edge_count', 0))
    
    if current_edges >= initial_edges:
        score += 10
        feedback_parts.append("Data integrity check passed (edges preserved).")
    else:
        feedback_parts.append(f"Data integrity warning: HasStayed edges decreased ({initial_edges} -> {current_edges}).")

    # --- Criterion 3: Data Correctness (70 pts) ---
    # Reconstruct graph
    profiles = result.get('profiles', [])
    edges = result.get('edges', [])
    hotels = {h['@rid']: h.get('Country') for h in result.get('hotels', [])}
    
    # Map Profile RID -> List of Visited Countries
    profile_visits = {p['@rid']: [] for p in profiles}
    
    for edge in edges:
        p_rid = edge.get('out')
        h_rid = edge.get('in')
        if p_rid in profile_visits and h_rid in hotels:
            country = hotels[h_rid]
            if country:
                profile_visits[p_rid].append(country)

    total_profiles = len(profiles)
    correct_count = 0
    processed_count = 0
    
    for p in profiles:
        rid = p['@rid']
        actual_val = p.get('FavoriteDestination')
        visits = profile_visits.get(rid, [])
        
        expected_modes = calculate_mode(visits)
        
        if not expected_modes:
            # Case: No visits
            # Expectation: actual_val should be None or empty string
            if not actual_val:
                correct_count += 1
            else:
                # Agent set a value where none should exist
                pass
        else:
            processed_count += 1
            # Case: Has visits
            # Expectation: actual_val should be in expected_modes
            if actual_val in expected_modes:
                correct_count += 1
            else:
                # Debug info for the first few failures
                if processed_count < 3:
                    feedback_parts.append(f"Profile {rid}: Expected {expected_modes}, got '{actual_val}'")

    if total_profiles > 0:
        accuracy = correct_count / total_profiles
        # Scale accuracy to 70 points
        data_score = int(accuracy * 70)
        score += data_score
        feedback_parts.append(f"Accuracy: {correct_count}/{total_profiles} profiles correct ({int(accuracy*100)}%)")
    else:
        feedback_parts.append("No profiles found to verify.")

    # Final Check
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }