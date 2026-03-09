#!/usr/bin/env python3
"""
Verifier for Nationality Friendship Projection Task.

Verifies:
1. Database Schema: Classes NationalityNode and NationalityLink exist.
2. Graph Data: 
   - 11 NationalityNodes with correct ProfileCounts.
   - 14 NationalityLinks with correct directions and FriendshipCounts.
3. Report File: Correctness of stats reported in the text file.
"""

import json
import base64
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_nationality_friendship_projection(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load expected values from metadata
    metadata = task_info.get('metadata', {})
    expected_spot_checks = metadata.get('spot_check_profiles', {})
    strongest_link = metadata.get('strongest_link', {"from": "French", "to": "German", "count": 2})

    # Retrieve result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []
    
    graph = result.get("graph_state", {})
    report = result.get("report_file", {})

    # --- CRITERION 1: Schema Existence (16 pts) ---
    if graph.get("nodes_class_exists"):
        score += 8
        feedback.append("NationalityNode class created.")
    else:
        feedback.append("NationalityNode class MISSING.")

    if graph.get("links_class_exists"):
        score += 8
        feedback.append("NationalityLink class created.")
    else:
        feedback.append("NationalityLink class MISSING.")

    # --- CRITERION 2: Vertex Data Verification (22 pts) ---
    nodes = graph.get("nodes", [])
    if len(nodes) == 11:
        score += 10
        feedback.append("Correct number of nationality nodes (11).")
    else:
        feedback.append(f"Incorrect node count: found {len(nodes)}, expected 11.")

    # Spot check profile counts
    correct_counts = 0
    checks_made = 0
    
    # Convert nodes list to dict for lookup
    node_map = {n.get("Name"): n.get("ProfileCount") for n in nodes if n.get("Name")}
    
    for country, expected_count in expected_spot_checks.items():
        checks_made += 1
        actual = node_map.get(country)
        if actual == expected_count:
            correct_counts += 1
        else:
            feedback.append(f"Incorrect count for {country}: expected {expected_count}, got {actual}.")
    
    if checks_made > 0 and correct_counts >= 4: # Allow small margin of error if major ones match
        score += 12
        feedback.append("Profile counts verified correct.")
    elif correct_counts > 0:
        score += int(12 * (correct_counts / checks_made))
        feedback.append(f"Partial credit for profile counts ({correct_counts}/{checks_made}).")

    # --- CRITERION 3: Edge Data Verification (34 pts) ---
    links = graph.get("links", [])
    
    # Check count
    if len(links) == 14:
        score += 10
        feedback.append("Correct number of nationality links (14).")
    else:
        feedback.append(f"Incorrect link count: found {len(links)}, expected 14.")

    # Check weights and direction
    # Expected: French -> German (2), all others (1)
    # Direction: Alphabetical
    
    strongest_found = False
    others_correct = 0
    direction_errors = 0
    
    for link in links:
        u = link.get("FromNat")
        v = link.get("ToNat")
        w = link.get("FriendshipCount")
        
        if not u or not v: 
            continue
            
        # Check direction (u should be alphabetically before v)
        if u > v:
            direction_errors += 1
            # Swap for logic checks
            u, v = v, u
            
        if u == strongest_link["from"] and v == strongest_link["to"]:
            if w == strongest_link["count"]:
                strongest_found = True
        elif w == 1:
            others_correct += 1

    if strongest_found:
        score += 10
        feedback.append("Strongest link (French-German) verified correct.")
    else:
        feedback.append("Strongest link incorrect or missing.")
        
    if others_correct >= 13:
        score += 8
        feedback.append("Other link weights verified.")
    else:
        score += int(8 * (others_correct / 13))
        feedback.append(f"Some link weights incorrect ({others_correct}/13).")
        
    if direction_errors == 0 and len(links) > 0:
        score += 6
        feedback.append("Edge directionality correct (alphabetical).")
    elif len(links) > 0:
        feedback.append(f"Edge directionality errors found ({direction_errors}).")

    # --- CRITERION 4: Report File (28 pts) ---
    if report.get("exists") and report.get("created_during_task"):
        score += 5
        feedback.append("Report file created.")
        
        try:
            content = base64.b64decode(report.get("content_base64", "")).decode('utf-8')
            lines = content.strip().split('\n')
            
            # Check for key phrases/stats in the content
            content_lower = content.lower()
            
            # Totals
            if "11" in content and ("total" in content_lower or "nationalities" in content_lower):
                score += 8
                feedback.append("Report: Node count correct.")
            
            if "14" in content and ("connection" in content_lower or "edge" in content_lower):
                score += 8
                feedback.append("Report: Connection count correct.")
                
            # Strongest link
            if "french" in content_lower and "german" in content_lower and "2" in content:
                score += 7
                feedback.append("Report: Strongest link identified.")
                
        except Exception:
            feedback.append("Could not parse report content.")
    else:
        feedback.append("Report file missing or not created during task.")

    return {
        "passed": score >= 60,
        "score": score,
        "feedback": " | ".join(feedback)
    }