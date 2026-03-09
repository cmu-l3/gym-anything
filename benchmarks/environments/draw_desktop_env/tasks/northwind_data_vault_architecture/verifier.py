#!/usr/bin/env python3
import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_northwind_data_vault_architecture(traj, env_info, task_info):
    """
    Verifies the Data Vault 2.0 diagram task.
    
    Criteria:
    1. Files exist (.drawio and .png).
    2. Correct number of Hubs, Links, Satellites created.
    3. Correct color coding applied (Blue/Red/Yellow).
    4. Metadata columns present (HashKey, LoadDate etc).
    5. Connectivity exists.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Retrieve result from container
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

    analysis = result.get("analysis", {})
    score = 0
    feedback = []

    # 1. File Existence (10 pts)
    if result.get("file_exists") and result.get("png_exists"):
        score += 10
        feedback.append("Files created successfully.")
    else:
        feedback.append("Missing .drawio or .png file.")
        return {"passed": False, "score": 0, "feedback": "Files missing"}

    # 2. Entity Creation (45 pts total)
    # Hubs (15 pts)
    hubs = analysis.get("hubs_found", 0)
    if hubs >= 3:
        score += 15
        feedback.append(f"Found {hubs} Hubs (Target: 3).")
    elif hubs > 0:
        score += 5
        feedback.append(f"Found {hubs} Hubs (Target: 3). Partial credit.")
    else:
        feedback.append("No Hubs found (label must contain 'Hub').")

    # Links (15 pts)
    links = analysis.get("links_found", 0)
    if links >= 2:
        score += 15
        feedback.append(f"Found {links} Links (Target: 2).")
    elif links > 0:
        score += 5
        feedback.append(f"Found {links} Links (Target: 2). Partial credit.")
    else:
        feedback.append("No Links found (label must contain 'Link').")

    # Satellites (15 pts)
    sats = analysis.get("sats_found", 0)
    if sats >= 3:
        score += 15
        feedback.append(f"Found {sats} Satellites (Target: 3).")
    elif sats > 0:
        score += 5
        feedback.append(f"Found {sats} Satellites (Target: 3). Partial credit.")
    else:
        feedback.append("No Satellites found (label must contain 'Sat').")

    # 3. Color Coding (20 pts)
    # We check if recognized entities have the correct color style
    correct_colors = (
        analysis.get("hub_colors_correct", 0) + 
        analysis.get("link_colors_correct", 0) + 
        analysis.get("sat_colors_correct", 0)
    )
    total_entities = hubs + links + sats
    
    if total_entities > 0:
        color_ratio = correct_colors / total_entities
        if color_ratio > 0.8:
            score += 20
            feedback.append("Excellent color coding.")
        elif color_ratio > 0.4:
            score += 10
            feedback.append("Some entities color coded correctly.")
        else:
            feedback.append("Color coding missing or incorrect.")

    # 4. Metadata Columns (15 pts)
    # Checks for HashKey, LoadDate, RecordSource text
    meta_count = analysis.get("metadata_columns_found", 0)
    if meta_count >= 5: # Arbitrary threshold, expecting at least one per entity roughly
        score += 15
        feedback.append("Metadata columns (HashKey/LoadDate) found.")
    elif meta_count > 0:
        score += 5
        feedback.append("Some metadata columns found.")
    else:
        feedback.append("No metadata columns (HashKey, LoadDate, RecordSource) found.")

    # 5. Connectivity (10 pts)
    edges = analysis.get("edges_count", 0)
    if edges >= 5:
        score += 10
        feedback.append(f"Diagram has {edges} connections.")
    elif edges > 0:
        score += 5
        feedback.append("Diagram has very few connections.")
    else:
        feedback.append("No connections drawn.")

    # Pass Threshold
    passed = score >= 60 and hubs >= 1 and links >= 1 and sats >= 1
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }