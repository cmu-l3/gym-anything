#!/usr/bin/env python3
"""
Verifier for customer_journey_threading task.

Verifies:
1. Schema creation (TimelineEvent, NextEvent, StartsJourney)
2. Data Aggregation (4 events created)
3. Graph connectivity (Profile -> Event -> Event...)
4. Chronological ordering of the chain
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_customer_journey_threading(traj, env_info, task_info):
    """
    Verify the constructed customer journey graph.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Copy result JSON from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    analysis = result_data.get("analysis", {})
    score = 0
    feedback_parts = []
    
    # Criterion 1: Schema Creation (15 pts)
    if analysis.get("schema_exists"):
        score += 15
        feedback_parts.append("Schema classes created")
    else:
        feedback_parts.append("Missing required classes (TimelineEvent, NextEvent, StartsJourney)")

    # Criterion 2: Event Count (25 pts)
    # Expected 4 events (2 orders, 2 reviews)
    total_events = analysis.get("total_events_count", 0)
    if total_events == 4:
        score += 25
        feedback_parts.append("Correct number of TimelineEvents (4)")
    elif total_events > 0:
        score += 10
        feedback_parts.append(f"Partial events created ({total_events}/4)")
    else:
        feedback_parts.append("No TimelineEvents created")

    # Criterion 3: Profile Linked (20 pts)
    if analysis.get("starts_journey_edge_exists"):
        score += 20
        feedback_parts.append("Profile linked to timeline start")
    else:
        feedback_parts.append("Profile NOT linked to start of chain")

    # Criterion 4: Chain Structure (25 pts)
    chain_length = analysis.get("chain_length", 0)
    if chain_length == 4:
        score += 25
        feedback_parts.append("Full timeline chain connected")
    elif chain_length >= 2:
        score += 10
        feedback_parts.append(f"Partial chain connected ({chain_length}/4)")
    else:
        feedback_parts.append("Events not linked sequentially")

    # Criterion 5: Chronological Order (15 pts)
    if analysis.get("chain_sorted") and chain_length >= 2:
        score += 15
        feedback_parts.append("Events are sorted chronologically")
    elif chain_length >= 2:
        dates = analysis.get("chain_dates", [])
        feedback_parts.append(f"Events NOT sorted: {dates}")

    # Pass Threshold: 60 points
    passed = score >= 60

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "details": analysis
    }