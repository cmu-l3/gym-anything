#!/usr/bin/env python3
"""
Verifier for add_postgis_attribute_reconfigure task.
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_add_postgis_attribute(traj, env_info, task_info):
    """
    Verifies that:
    1. PostGIS column 'pop_density' exists and has valid data.
    2. GeoServer feature type is reconfigured to include the attribute.
    3. WFS service actually serves the attribute.
    4. User exported the WFS result to a file.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

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
    
    # 1. DB Column Exists (15 pts)
    if result.get('db_column_exists', False):
        score += 15
        feedback_parts.append("PostGIS column 'pop_density' created.")
    else:
        feedback_parts.append("PostGIS column 'pop_density' NOT found.")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}

    # 2. DB Data Populated & Plausible (25 pts)
    # Check stats
    stats = result.get('db_stats', {})
    non_null = stats.get('non_null_count', 0)
    avg_val = stats.get('avg_val', 0)
    max_val = stats.get('max_val', 0)
    
    # Expect at least 150 countries
    if non_null > 150:
        score += 15
        feedback_parts.append(f"Column populated ({non_null} rows).")
        
        # Plausibility check
        # Population density (people/km2) typically ranges 0-20,000 (Monaco/Macau are high, but most < 1000)
        # If calculation was done without converting area to km2 (i.e. left in m2), values would be 1e-6 smaller.
        # If calculation was done without geography cast (using degrees), values would be nonsense.
        
        # Valid range: avg between 10 and 500.
        if 5 <= avg_val <= 1000 and max_val < 100000:
            score += 10
            feedback_parts.append("Density values look plausible.")
        else:
            feedback_parts.append(f"Density values seem wrong (Avg: {avg_val:.4f}, Max: {max_val}). Check units (sq km vs sq m).")
    else:
        feedback_parts.append(f"Column empty or sparse ({non_null} rows populated).")

    # 3. GeoServer Configuration (20 pts)
    if result.get('gs_attribute_configured', False):
        score += 20
        feedback_parts.append("GeoServer feature type configured.")
    else:
        feedback_parts.append("GeoServer feature type NOT updated (reload feature type?).")

    # 4. WFS Service Live Check (20 pts)
    if result.get('wfs_serving_attribute', False):
        score += 20
        feedback_parts.append("WFS service exposing attribute.")
    else:
        feedback_parts.append("WFS service NOT exposing attribute (layer not saved/reloaded?).")

    # 5. Output File (20 pts)
    if result.get('output_file_exists', False):
        if result.get('output_file_has_content', False):
            score += 20
            feedback_parts.append("Output file created and valid.")
        elif result.get('output_file_valid', False):
            score += 10
            feedback_parts.append("Output file valid JSON but missing density attribute.")
        else:
            score += 5
            feedback_parts.append("Output file exists but invalid content.")
    else:
        feedback_parts.append("Output file not found.")

    passed = score >= 70 and result.get('wfs_serving_attribute', False)

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }