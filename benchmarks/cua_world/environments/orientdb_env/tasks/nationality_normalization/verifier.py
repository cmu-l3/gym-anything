#!/usr/bin/env python3
"""
Verifier for nationality_normalization task.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_nationality_normalization(traj, env_info, task_info):
    """
    Verifies that:
    1. IsCitizenOf edge class exists.
    2. Edges correctly map Nationalities (adj) to Countries (noun).
    3. Orphans (like 'Mexican') are NOT connected to nonexistent countries.
    4. Audit report exists and identifies unmapped users.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load results
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
    feedback = []
    
    # 1. Edge Class Creation (10 pts)
    if result.get("class_is_citizen_of_exists", False):
        score += 10
        feedback.append("IsCitizenOf edge class created.")
    else:
        feedback.append("IsCitizenOf edge class NOT created.")
        return {"passed": False, "score": 0, "feedback": "\n".join(feedback)}

    # Parse Edge Data
    edge_result_raw = result.get("edge_data", {}).get("result", [])
    # Normalize list of dicts: [{'nat': 'American', 'country': 'United States', 'email': '...'}]
    edges = []
    for entry in edge_result_raw:
        edges.append({
            "nat": entry.get("nat"),
            "country": entry.get("country"),
            "email": entry.get("email")
        })

    # 2. Verify Mappings (50 pts total)
    # Define expectations: (Nationality -> Country Name)
    required_mappings = [
        ("American", "United States"),
        ("British", "United Kingdom"),
        ("Dutch", "Netherlands")
    ]
    
    mapping_score = 0
    points_per_mapping = 50 / len(required_mappings) # ~16.6 pts each
    
    for req_nat, req_country in required_mappings:
        # Check if we have at least one edge matching this criteria
        match = any(e["nat"] == req_nat and e["country"] == req_country for e in edges)
        if match:
            mapping_score += points_per_mapping
            feedback.append(f"Correctly mapped '{req_nat}' -> '{req_country}'.")
        else:
            # Check if they mapped it to something else (wrong)
            wrong_match = [e["country"] for e in edges if e["nat"] == req_nat]
            if wrong_match:
                feedback.append(f"Incorrect mapping for '{req_nat}': linked to {wrong_match}.")
            else:
                feedback.append(f"Missing mapping for '{req_nat}'.")
    
    score += int(mapping_score)

    # 3. Verify Orphan Handling (20 pts)
    # Carlos (Mexican) should NOT have an edge because "Mexico" doesn't exist in Countries.
    carlos_edges_raw = result.get("carlos_edges", {}).get("result", [{}])[0].get("cnt", 0)
    
    if carlos_edges_raw == 0:
        score += 20
        feedback.append("Correctly handled orphan: 'Mexican' profile has no edges.")
    else:
        feedback.append(f"Incorrect orphan handling: 'Mexican' profile has {carlos_edges_raw} edges (should be 0).")

    # 4. Verify Report (20 pts)
    report_exists = result.get("report_exists", False)
    report_content = result.get("report_content", "")
    
    if report_exists:
        if "Mexican" in report_content or "carlos" in report_content.lower():
            score += 20
            feedback.append("Audit report exists and correctly identifies the unmapped nationality.")
        else:
            score += 10
            feedback.append("Audit report exists but does not clearly identify 'Mexican' or 'Carlos' as unmapped.")
    else:
        feedback.append("Audit report file not found.")

    passed = (score >= 70)
    return {
        "passed": passed,
        "score": score,
        "feedback": "\n".join(feedback)
    }