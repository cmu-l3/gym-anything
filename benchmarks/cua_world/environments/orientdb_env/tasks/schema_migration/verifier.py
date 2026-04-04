#!/usr/bin/env python3
"""
Verifier for Schema Migration Task.
Checks schema changes (properties, constraints, indexes) and data backfill correctness.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_schema_migration(traj, env_info, task_info):
    """
    Verifies that the agent performed the schema migration and data backfill correctly.
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
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    schema = result.get("schema", {})
    classes = {c["name"]: c for c in schema.get("classes", [])}
    data_stats = result.get("data_stats", {})
    
    score = 0
    feedback = []
    
    # ---------------------------------------------------------
    # 1. Verify Property Creation (24 points)
    # ---------------------------------------------------------
    # Restaurants.Rating (DOUBLE)
    rest_class = classes.get("Restaurants", {})
    rest_props = {p["name"]: p for p in rest_class.get("properties", [])}
    
    if "Rating" in rest_props:
        p_type = rest_props["Rating"].get("type")
        if p_type == "DOUBLE":
            score += 12
            feedback.append("✓ Restaurants.Rating created (DOUBLE)")
        else:
            score += 6
            feedback.append(f"⚠ Restaurants.Rating created but wrong type ({p_type})")
    else:
        feedback.append("✗ Restaurants.Rating property missing")

    # Hotels.Capacity (INTEGER)
    hotel_class = classes.get("Hotels", {})
    hotel_props = {p["name"]: p for p in hotel_class.get("properties", [])}
    
    if "Capacity" in hotel_props:
        p_type = hotel_props["Capacity"].get("type")
        if p_type == "INTEGER":
            score += 12
            feedback.append("✓ Hotels.Capacity created (INTEGER)")
        else:
            score += 6
            feedback.append(f"⚠ Hotels.Capacity created but wrong type ({p_type})")
    else:
        feedback.append("✗ Hotels.Capacity property missing")

    # ---------------------------------------------------------
    # 2. Verify Constraints (28 points)
    # ---------------------------------------------------------
    # Hotels.Name MANDATORY (12 pts)
    if "Name" in hotel_props:
        if hotel_props["Name"].get("mandatory") is True:
            score += 12
            feedback.append("✓ Hotels.Name is MANDATORY")
        else:
            feedback.append("✗ Hotels.Name is NOT MANDATORY")
    else:
        feedback.append("✗ Hotels.Name property not found (unexpected)")

    # Hotels.Stars MIN/MAX (16 pts)
    if "Stars" in hotel_props:
        stars = hotel_props["Stars"]
        min_val = stars.get("min")
        max_val = stars.get("max")
        
        # Check MIN
        if str(min_val) == "1":
            score += 8
            feedback.append("✓ Hotels.Stars MIN=1")
        else:
            feedback.append(f"✗ Hotels.Stars MIN incorrect (expected 1, got {min_val})")
            
        # Check MAX
        if str(max_val) == "5":
            score += 8
            feedback.append("✓ Hotels.Stars MAX=5")
        else:
            feedback.append(f"✗ Hotels.Stars MAX incorrect (expected 5, got {max_val})")
    else:
        feedback.append("✗ Hotels.Stars property not found")

    # ---------------------------------------------------------
    # 3. Verify Composite Index (15 points)
    # ---------------------------------------------------------
    # Look for Hotels_Country_Stars_idx
    hotel_indexes = hotel_class.get("indexes", [])
    index_found = False
    for idx in hotel_indexes:
        if idx["name"] == "Hotels_Country_Stars_idx":
            index_found = True
            # Verify fields and type
            fields = idx.get("fields", [])
            idx_type = idx.get("type", "")
            
            if "Country" in fields and "Stars" in fields:
                if idx_type == "NOTUNIQUE":
                    score += 15
                    feedback.append("✓ Composite index created correctly")
                else:
                    score += 10
                    feedback.append(f"⚠ Index fields correct, but type is {idx_type} (expected NOTUNIQUE)")
            else:
                score += 5
                feedback.append(f"⚠ Index exists but fields mismatch: {fields}")
            break
    
    if not index_found:
        feedback.append("✗ Composite index 'Hotels_Country_Stars_idx' not found")

    # ---------------------------------------------------------
    # 4. Verify Data Backfill (33 points)
    # ---------------------------------------------------------
    # Restaurants Backfill (11 pts)
    r_stats = data_stats.get("restaurants", {})
    if r_stats.get("total", 0) > 0 and r_stats.get("total") == r_stats.get("with_correct_rating"):
        score += 11
        feedback.append("✓ Restaurants backfill correct")
    else:
        feedback.append(f"✗ Restaurants backfill incomplete ({r_stats.get('with_correct_rating')}/{r_stats.get('total')})")

    # Hotels 5-star Backfill (11 pts)
    h5_stats = data_stats.get("hotels_5star", {})
    if h5_stats.get("total", 0) > 0 and h5_stats.get("total") == h5_stats.get("with_correct_capacity"):
        score += 11
        feedback.append("✓ Hotels (5-star) backfill correct")
    else:
        feedback.append(f"✗ Hotels (5-star) backfill incomplete ({h5_stats.get('with_correct_capacity')}/{h5_stats.get('total')})")

    # Hotels Other Backfill (11 pts)
    ho_stats = data_stats.get("hotels_other", {})
    if ho_stats.get("total", 0) > 0 and ho_stats.get("total") == ho_stats.get("with_correct_capacity"):
        score += 11
        feedback.append("✓ Hotels (others) backfill correct")
    else:
        feedback.append(f"✗ Hotels (others) backfill incomplete ({ho_stats.get('with_correct_capacity')}/{ho_stats.get('total')})")

    # ---------------------------------------------------------
    # Final Calculation
    # ---------------------------------------------------------
    # Pass threshold: 60 points AND at least one property added AND index created
    property_added = ("Rating" in rest_props) or ("Capacity" in hotel_props)
    
    passed = (score >= 60) and property_added and index_found
    
    return {
        "passed": passed,
        "score": score,
        "feedback": "\n".join(feedback)
    }