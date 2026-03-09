#!/usr/bin/env python3
import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_attack_tree(traj, env_info, task_info):
    """
    Verifies the LockBit Attack Tree task.
    
    Criteria:
    1. Files exist and modified (Anti-gaming).
    2. Tree structure (Nodes, Edges).
    3. Content (MITRE IDs, Keywords).
    4. Styling (Colors).
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
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # Extract data
    analysis = result.get("analysis", {})
    file_exists = result.get("file_exists", False)
    file_modified = result.get("file_modified_during_task", False)
    png_exists = result.get("png_exists", False)
    
    node_count = analysis.get("node_count", 0)
    edge_count = analysis.get("edge_count", 0)
    mitre_ids = analysis.get("mitre_ids_found", [])
    text_content = " ".join(analysis.get("text_content", [])).lower()
    colors = analysis.get("colors_used", [])

    score = 0
    feedback_parts = []
    
    # CRITERION 1: Files Check (15 pts)
    if file_exists and file_modified:
        score += 10
        feedback_parts.append("Draw.io file saved.")
    else:
        feedback_parts.append("Draw.io file missing or not modified.")
        
    if png_exists:
        score += 5
        feedback_parts.append("PNG exported.")
    else:
        feedback_parts.append("PNG missing.")

    # CRITERION 2: Tree Structure (25 pts)
    # Expecting at least 8 nodes (Goal, 4 tactic categories, ~3+ techniques)
    # Expecting edges to connect them.
    if node_count >= 8:
        score += 15
        feedback_parts.append(f"Structure: {node_count} nodes (Good).")
    elif node_count >= 4:
        score += 5
        feedback_parts.append(f"Structure: {node_count} nodes (Sparse).")
    else:
        feedback_parts.append("Structure: Too few nodes.")

    if edge_count >= 7:
        score += 10
        feedback_parts.append(f"Connectivity: {edge_count} edges.")
    else:
        feedback_parts.append(f"Connectivity: Only {edge_count} edges (Disconnected?).")

    # CRITERION 3: Content & MITRE IDs (40 pts)
    required_mitre = ["T1566", "T1190", "T1133", "T1078", "T1059", "T1053", "T1003", "T1021", "T1486", "T1490"]
    found_ids_count = 0
    for mid in required_mitre:
        # Check specific ID or base ID (e.g. T1021.002 matches T1021)
        if any(mid in found for found in mitre_ids):
            found_ids_count += 1
            
    if found_ids_count >= 6:
        score += 25
        feedback_parts.append(f"MITRE Coverage: Excellent ({found_ids_count} IDs found).")
    elif found_ids_count >= 3:
        score += 15
        feedback_parts.append(f"MITRE Coverage: Good ({found_ids_count} IDs found).")
    elif found_ids_count >= 1:
        score += 5
        feedback_parts.append("MITRE Coverage: Poor.")
    else:
        feedback_parts.append("No MITRE IDs found.")

    # Keywords check
    keywords = ["lockbit", "phishing", "rdp", "encryption", "psexec"]
    kw_count = sum(1 for k in keywords if k in text_content)
    if kw_count >= 3:
        score += 15
        feedback_parts.append("Keywords: Content matches report.")
    else:
        score += 5 * kw_count
        feedback_parts.append(f"Keywords: Missing key terms ({kw_count}/5).")

    # CRITERION 4: Styling/Colors (20 pts)
    # Task requested Red, Orange, Blue.
    if len(colors) >= 3:
        score += 20
        feedback_parts.append("Styling: Multi-color coding applied.")
    elif len(colors) == 2:
        score += 10
        feedback_parts.append("Styling: Basic coloring.")
    elif len(colors) == 1:
        score += 5
        feedback_parts.append("Styling: Monochromatic.")
    else:
        feedback_parts.append("Styling: No fill colors detected.")

    passed = score >= 60 and file_exists and node_count > 0

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }