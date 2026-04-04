#!/usr/bin/env python3
"""
Verifier for migrate_hotel_type_to_tags task.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_migrate_hotel_type_to_tags(traj, env_info, task_info):
    """
    Verifies that the Hotels class schema was refactored and data migrated/enriched correctly.
    
    Criteria:
    1. Schema: 'Tags' property exists and is EMBEDDEDSET (15 pts)
    2. Schema: 'Type' property is removed (10 pts)
    3. Data: Original types are preserved in Tags (25 pts)
    4. Logic: 'Palace' -> 'Luxury' tag added (15 pts)
    5. Logic: 'Resort' -> 'Resort' tag added (15 pts)
    6. Logic: 'Spa' -> 'Wellness' tag added (15 pts)
    7. Completeness: No empty tags found (5 pts)
    """
    
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result from container
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    if "error" in result:
        return {"passed": False, "score": 0, "feedback": f"Export error: {result['error']}"}

    score = 0
    feedback = []
    
    # 1. Schema Checks
    schema = result.get("schema", {})
    
    # Check Tags property
    if schema.get("has_tags_property"):
        prop_type = schema.get("tags_type")
        if prop_type == "EMBEDDEDSET":
            score += 15
            feedback.append("Schema: Tags (EMBEDDEDSET) created.")
        elif prop_type in ["LINKSET", "EMBEDDEDLIST"]:
            score += 10
            feedback.append(f"Schema: Tags created but type is {prop_type} (expected EMBEDDEDSET).")
        else:
            score += 5
            feedback.append(f"Schema: Tags created but incorrect type {prop_type}.")
    else:
        feedback.append("Schema: Tags property MISSING.")

    # Check Type property removal
    if not schema.get("has_type_property"):
        score += 10
        feedback.append("Schema: Legacy Type property removed.")
    else:
        feedback.append("Schema: Legacy Type property still exists.")

    # 2. Data Checks
    data_records = result.get("data", [])
    data_map = {r.get("Name"): r.get("Tags", []) for r in data_records}
    
    # Ensure Tags is a list (OrientDB might return null or empty)
    for k, v in data_map.items():
        if v is None: data_map[k] = []
        if not isinstance(data_map[k], list): data_map[k] = [v] # Handle single value edge case if migration failed to make it a set

    # Test Cases
    # Case 1: Copacabana Palace (Original: Historic) -> Expect: Historic, Luxury
    tags = data_map.get("Copacabana Palace", [])
    tags_lower = [t.lower() for t in tags]
    
    if "historic" in tags_lower:
        score += 8  # Part of the 25pts for preservation
        feedback.append("Data: Copacabana Palace kept 'Historic'.")
    else:
        feedback.append("Data: Copacabana Palace lost 'Historic'.")
        
    if "luxury" in tags_lower:
        score += 15
        feedback.append("Logic: Copacabana Palace added 'Luxury'.")
    else:
        feedback.append("Logic: Copacabana Palace missing 'Luxury'.")

    # Case 2: Terme di Saturnia Spa (Original: Luxury) -> Expect: Luxury, Wellness
    tags = data_map.get("Terme di Saturnia Spa", [])
    tags_lower = [t.lower() for t in tags]

    if "luxury" in tags_lower:
        score += 8
        feedback.append("Data: Terme di Saturnia Spa kept 'Luxury'.")
    else:
        feedback.append("Data: Terme di Saturnia Spa lost 'Luxury'.")
        
    if "wellness" in tags_lower:
        score += 15
        feedback.append("Logic: Terme di Saturnia Spa added 'Wellness'.")
    else:
        feedback.append("Logic: Terme di Saturnia Spa missing 'Wellness'.")

    # Case 3: Hotel Artemide (Original: Boutique) -> Expect: Boutique
    tags = data_map.get("Hotel Artemide", [])
    tags_lower = [t.lower() for t in tags]

    if "boutique" in tags_lower:
        score += 9
        feedback.append("Data: Hotel Artemide kept 'Boutique'.")
    else:
        feedback.append("Data: Hotel Artemide lost 'Boutique'.")
        
    # Case 4: Tivoli Ecoresort (Original: Resort) -> Expect: Resort
    tags = data_map.get("Tivoli Ecoresort Praia do Forte", [])
    tags_lower = [t.lower() for t in tags]
    
    if "resort" in tags_lower:
        score += 15
        feedback.append("Logic: Tivoli Ecoresort added/kept 'Resort'.")
    else:
        feedback.append("Logic: Tivoli Ecoresort missing 'Resort'.")

    # 3. Completeness
    empty_count = result.get("empty_tags_count", 0)
    if empty_count == 0:
        score += 5
        feedback.append("Completeness: All hotels have tags.")
    else:
        feedback.append(f"Completeness: {empty_count} hotels have empty tags.")

    # Cap score at 100
    score = min(score, 100)
    
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }