#!/usr/bin/env python3
"""
Verifier for Odoo CRM Task: Segment Opportunities by Region
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_segment_opportunities_by_region(traj, env_info, task_info):
    """
    Verifies if opportunities were correctly tagged based on customer country.
    
    Criteria:
    1. Opportunities with Belgian customers (BE) must have tag "Region: Europe".
    2. Opportunities with US customers (US) must have tag "Region: North America".
    3. No incorrect tags should be applied (e.g., US tag on BE customer).
    """
    
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result file: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    if "error" in result:
        return {"passed": False, "score": 0, "feedback": f"Error during data export: {result['error']}"}

    opportunities = result.get("opportunities", [])
    if not opportunities:
        return {"passed": False, "score": 0, "feedback": "No target opportunities found in database."}

    # Scoring counters
    score = 0
    max_score = 100
    
    # We expect 4 specific opportunities based on setup
    # 2 BE -> Region: Europe
    # 2 US -> Region: North America
    
    correct_tagging_count = 0
    incorrect_tagging_count = 0
    total_checked = 0

    feedback_details = []

    for opp in opportunities:
        name = opp['name']
        country = opp['country_code']
        tags = opp['tags']
        
        # Normalize tags to set for easier checking
        tags_set = set(tags)
        
        is_correct = False
        error_msg = ""

        if country == "BE":
            total_checked += 1
            if "Region: Europe" in tags_set:
                # Check for contradiction
                if "Region: North America" in tags_set:
                    error_msg = "Has BOTH Europe and North America tags."
                    incorrect_tagging_count += 1
                else:
                    is_correct = True
                    correct_tagging_count += 1
            else:
                error_msg = "Missing 'Region: Europe' tag."
        
        elif country == "US":
            total_checked += 1
            if "Region: North America" in tags_set:
                if "Region: Europe" in tags_set:
                    error_msg = "Has BOTH Europe and North America tags."
                    incorrect_tagging_count += 1
                else:
                    is_correct = True
                    correct_tagging_count += 1
            else:
                error_msg = "Missing 'Region: North America' tag."
        
        else:
            # Ignore opportunities not part of the seed set (though setup script cleans others)
            continue

        status = "CORRECT" if is_correct else "INCORRECT"
        feedback_details.append(f"[{status}] {name} ({country}): {tags} {error_msg}")

    # Calculate Score
    # We have 4 opportunities to check. Each worth 25 points.
    if total_checked > 0:
        points_per_opp = 100 / total_checked
        score = int(correct_tagging_count * points_per_opp)
    
    # Penalize for bad tags (safety check, though logic above captures it)
    # The logic above already counts incorrect/conflicting tags as 0 points for that opp.

    passed = (score >= 80) # Allow minimal margin, but realistically this is binary for each opp

    feedback_str = "\n".join(feedback_details)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": f"Tagging Results:\n{feedback_str}"
    }