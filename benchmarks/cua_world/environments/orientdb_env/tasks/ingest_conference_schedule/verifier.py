#!/usr/bin/env python3
"""
Verifier for ingest_conference_schedule task.
"""
import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_ingest_conference_schedule(traj, env_info, task_info):
    """
    Verify that the conference schedule was correctly ingested into OrientDB.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Copy result JSON from container
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    db_state = result.get("db_state", {})
    schema = db_state.get("schema", [])
    counts = db_state.get("counts", {})
    topology = db_state.get("topology", {})
    
    score = 0
    feedback = []

    # Criterion 1: Schema Creation (20 pts)
    required_classes = ["Conferences", "Sessions", "HostedAt", "HasSession", "PresentedBy"]
    missing_classes = [c for c in required_classes if c not in schema]
    
    if not missing_classes:
        score += 20
        feedback.append("Schema created correctly.")
    else:
        feedback.append(f"Missing classes: {', '.join(missing_classes)}")
        # If major classes are missing, it's hard to get other points, but we continue checking

    # Criterion 2: Vertex Counts (20 pts)
    # Expected: 2 Conferences, 4 Sessions
    conf_count = counts.get("Conferences", 0)
    sess_count = counts.get("Sessions", 0)
    
    if conf_count == 2:
        score += 10
        feedback.append("Correct number of Conferences (2).")
    else:
        feedback.append(f"Incorrect Conference count: {conf_count} (expected 2).")
        
    if sess_count == 4:
        score += 10
        feedback.append("Correct number of Sessions (4).")
    else:
        feedback.append(f"Incorrect Session count: {sess_count} (expected 4).")

    # Criterion 3: Topology - Conference to Hotel (30 pts)
    # Check specific links
    conf_links = topology.get("conf_hotel_links", [])
    # We expect 'Global Graph Summit 2026' -> 'Hotel Artemide'
    # And 'Travel Tech World' -> 'The Savoy'
    
    found_artemide = False
    found_savoy = False
    
    for link in conf_links:
        c = link.get("conf", "")
        h = link.get("hotel", "")
        if c == "Global Graph Summit 2026" and h == "Hotel Artemide":
            found_artemide = True
        if c == "Travel Tech World" and h == "The Savoy":
            found_savoy = True
            
    if found_artemide: score += 15
    if found_savoy: score += 15
    
    if found_artemide and found_savoy:
        feedback.append("Conference venues linked correctly.")
    else:
        feedback.append("Some conference venue links are missing or incorrect.")

    # Criterion 4: Topology - Session to Speaker (30 pts)
    # Check a couple of samples
    # 'Scaling OrientDB Clusters' -> 'luca.rossi@example.com'
    # 'Recommender Systems 101' -> 'david.jones@example.com'
    
    sess_links = topology.get("session_speaker_links", [])
    found_luca = False
    found_david = False
    
    for link in sess_links:
        s = link.get("session", "")
        e = link.get("email", "")
        if s == "Scaling OrientDB Clusters" and e == "luca.rossi@example.com":
            found_luca = True
        if s == "Recommender Systems 101" and e == "david.jones@example.com":
            found_david = True
            
    if found_luca: score += 15
    if found_david: score += 15
    
    if found_luca and found_david:
        feedback.append("Session speakers linked correctly.")
    else:
        feedback.append("Some session speaker links are missing or incorrect.")

    # Pass logic
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback),
        "details": db_state
    }