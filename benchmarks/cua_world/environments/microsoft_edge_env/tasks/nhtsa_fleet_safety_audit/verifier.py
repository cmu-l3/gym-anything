#!/usr/bin/env python3
"""
Verifier for NHTSA Fleet Safety Audit task.

Scoring Breakdown (100 points):
- Report created & modified correctly: 10 points
- All 3 target vehicles included in report: 15 points
- Safety Ratings (stars) included for vehicles: 20 points
- Recall Counts included for vehicles: 20 points
- Browser History shows navigation to NHTSA vehicle pages: 25 points
- Technical report downloaded: 10 points

Pass Threshold: 65 points
"""

import json
import os
import re
import tempfile
import logging

logger = logging.getLogger(__name__)

def verify_nhtsa_audit(traj, env_info, task_info):
    # 1. Setup
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function unavailable"}

    # Load result JSON from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/nhtsa_audit_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []

    # 2. Verify Report Existence (10 pts)
    report = result.get("report", {})
    if report.get("exists") and report.get("modified_after_start"):
        score += 10
        feedback.append("Report file created successfully.")
    else:
        feedback.append("Report file missing or not modified.")

    # 3. Verify Content - Vehicles (15 pts)
    # Expecting Camry, F-150, Wrangler
    vehicles_found = report.get("vehicles_found", [])
    unique_vehicles = set(vehicles_found)
    
    if len(unique_vehicles) >= 3:
        score += 15
        feedback.append("All 3 target vehicles found in report.")
    elif len(unique_vehicles) > 0:
        partial = 5 * len(unique_vehicles)
        score += partial
        feedback.append(f"Found {len(unique_vehicles)}/3 vehicles in report.")
    else:
        feedback.append("No target vehicles found in report content.")

    # 4. Verify Content - Ratings (20 pts)
    # We look for patterns like "5 stars", "Rating: 5", "Not Rated"
    content = report.get("content", "").lower()
    
    # Simple heuristic: Count occurrences of rating-like patterns
    # A perfect report has 3 ratings.
    # Pattern: (star|rating) ... (digit)
    rating_matches = re.findall(r'(?:star|rating|overall).*?(\d|not rated)', content)
    
    if len(rating_matches) >= 3:
        score += 20
        feedback.append("Safety ratings included for all vehicles.")
    elif len(rating_matches) > 0:
        score += 10
        feedback.append("Partial safety ratings found.")
    else:
        feedback.append("No safety ratings found in report.")

    # 5. Verify Content - Recalls (20 pts)
    # Pattern: recall ... (digit)
    recall_matches = re.findall(r'recalls?.*?\d+', content)
    
    if len(recall_matches) >= 3:
        score += 20
        feedback.append("Recall counts included for all vehicles.")
    elif len(recall_matches) > 0:
        score += 10
        feedback.append("Partial recall counts found.")
    else:
        feedback.append("No recall counts found in report.")

    # 6. Verify History (25 pts)
    history = result.get("history", {})
    visited_nhtsa = history.get("visited_nhtsa", False)
    visited_vehicles = history.get("visited_vehicles", [])
    
    if len(set(visited_vehicles)) >= 3:
        score += 25
        feedback.append("Browser history confirms navigation to all vehicle pages.")
    elif visited_nhtsa:
        # Partial credit for visiting site but maybe not deep linking or URL structure differed
        score += 10
        feedback.append("Browser history shows NHTSA visit, but specific vehicle pages not confirmed.")
    else:
        feedback.append("No NHTSA visits found in history.")

    # 7. Verify Download (10 pts)
    downloads = result.get("downloads", {})
    if downloads.get("has_nhtsa_download"):
        score += 10
        feedback.append("Technical report downloaded successfully.")
    else:
        feedback.append("No relevant technical report found in Downloads.")

    # Final logic
    passed = score >= 65
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }