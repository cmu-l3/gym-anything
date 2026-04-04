#!/usr/bin/env python3
"""
Verifier for normalize_amenities_graph task.

Scoring Breakdown:
1. Schema Correctness (30 pts)
   - Amenity class exists (10)
   - HasAmenity class exists (10)
   - Amenity.Name is UNIQUE (10)
2. Data Integrity (40 pts)
   - Correct number of Amenity vertices (8) (20)
   - Correct number of HasAmenity edges (19) (20)
3. Specific Verification (20 pts)
   - "The Plaza Hotel" has correct amenities linked (20)
4. Cleanup (10 pts)
   - Hotels.Amenities property dropped (10)
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_normalize_amenities_graph(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_amenity_count = metadata.get('expected_amenity_count', 8)
    expected_edge_count = metadata.get('expected_edge_count', 19)
    expected_plaza = set(metadata.get('expected_hotel_amenities', ["WiFi", "Gym", "Spa", "Concierge"]))

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

    score = 0
    feedback_parts = []
    
    # 1. Schema Verification (30 pts)
    if result.get("amenity_class_exists"):
        score += 10
        feedback_parts.append("Amenity class created")
    else:
        feedback_parts.append("Amenity class missing")

    if result.get("hasamenity_class_exists"):
        score += 10
        feedback_parts.append("HasAmenity edge created")
    else:
        feedback_parts.append("HasAmenity edge missing")

    if result.get("amenity_name_unique"):
        score += 10
        feedback_parts.append("Amenity.Name is UNIQUE")
    else:
        feedback_parts.append("Amenity.Name NOT unique")

    # 2. Data Integrity (40 pts)
    # Amenity Count
    actual_amenities = result.get("amenity_count", 0)
    if actual_amenities == expected_amenity_count:
        score += 20
        feedback_parts.append(f"Amenity count correct ({actual_amenities})")
    elif actual_amenities > 0:
        # Partial credit if close? No, graph migration is strict.
        feedback_parts.append(f"Amenity count mismatch: expected {expected_amenity_count}, got {actual_amenities}")
    else:
        feedback_parts.append("No Amenity vertices found")

    # Edge Count
    actual_edges = result.get("edge_count", 0)
    if actual_edges == expected_edge_count:
        score += 20
        feedback_parts.append(f"Edge count correct ({actual_edges})")
    elif actual_edges > 0:
        # Check tolerance (maybe they doubled up edges?)
        feedback_parts.append(f"Edge count mismatch: expected {expected_edge_count}, got {actual_edges}")
    else:
        feedback_parts.append("No HasAmenity edges found")

    # 3. Specific Verification (20 pts)
    actual_plaza = set(result.get("plaza_amenities", []))
    if actual_plaza == expected_plaza:
        score += 20
        feedback_parts.append("The Plaza Hotel amenities correct")
    else:
        feedback_parts.append(f"The Plaza Hotel amenities incorrect: expected {expected_plaza}, got {actual_plaza}")

    # 4. Cleanup (10 pts)
    if not result.get("amenities_property_exists"):
        score += 10
        feedback_parts.append("Hotels.Amenities property dropped")
    else:
        feedback_parts.append("Hotels.Amenities property NOT dropped")

    passed = score >= 85
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }