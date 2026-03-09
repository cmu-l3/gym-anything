#!/usr/bin/env python3
import json
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_agtech_component_library(traj, env_info, task_info):
    """
    Verifies the AgTech Component Library task.
    
    Criteria:
    1. Library file exists and contains at least 2 models (15 pts)
    2. Diagram file exists (10 pts)
    3. Hub Symbol Accuracy: Blue body, Red LED (Square/Ellipse implied by colors/labels) (20 pts)
    4. Probe Symbol Accuracy: Green body, Brown tip (Triangle implied) (20 pts)
    5. Topology: 1 Hub, 3 Probes (based on labels/count) (15 pts)
    6. Connectivity: Edges exist (10 pts)
    7. Grouping: Groups detected (10 pts)
    """
    
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result from container
    try:
        import tempfile
        temp = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
        copy_from_env("/tmp/task_result.json", temp.name)
        with open(temp.name, 'r') as f:
            data = json.load(f)
        os.unlink(temp.name)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {e}"}

    score = 0
    feedback = []

    # 1. Library File (15 pts)
    if data.get("lib_exists"):
        models = data.get("lib_models_count", 0)
        if models >= 2:
            score += 15
            feedback.append("Library created with valid models.")
        elif models > 0:
            score += 10
            feedback.append("Library created but fewer models than expected.")
        else:
            score += 5
            feedback.append("Library file exists but appears empty.")
    else:
        feedback.append("Library file not found.")

    # 2. Diagram File (10 pts)
    if data.get("diagram_exists"):
        score += 10
        feedback.append("Diagram file exists.")
    else:
        feedback.append("Diagram file not found.")

    # 3. Hub Symbol Accuracy (20 pts)
    # Expect Blue fill + Red fill + "Hub" label
    hub_score = 0
    if data.get("has_blue_fill"): hub_score += 10
    if data.get("has_red_fill"): hub_score += 5
    if data.get("hub_label_count", 0) >= 1: hub_score += 5
    score += hub_score
    if hub_score < 20:
        feedback.append(f"Hub symbol issues (Score: {hub_score}/20). Missing blue body, red LED, or labels.")

    # 4. Probe Symbol Accuracy (20 pts)
    # Expect Green fill + Brown fill + Triangle + "Probe" label
    probe_score = 0
    if data.get("has_green_fill"): probe_score += 5
    if data.get("has_brown_fill"): probe_score += 5
    if data.get("has_triangle"): probe_score += 5
    if data.get("probe_label_count", 0) >= 3: probe_score += 5
    score += probe_score
    if probe_score < 20:
        feedback.append(f"Probe symbol issues (Score: {probe_score}/20). Missing green body, brown tip (triangle), or labels.")

    # 5. Topology (15 pts)
    # Expect roughly 1 hub and 3 probes.
    # We check label counts. 
    topo_score = 0
    hubs = data.get("hub_label_count", 0)
    probes = data.get("probe_label_count", 0)
    
    if hubs >= 1: topo_score += 5
    if probes >= 3: topo_score += 10
    elif probes >= 1: topo_score += 5
    
    score += topo_score
    if topo_score < 15:
        feedback.append(f"Topology mismatch: Found {hubs} Hubs and {probes} Probes (Expected 1 Hub, 3 Probes).")

    # 6. Connectivity (10 pts)
    edges = data.get("edge_count", 0)
    if edges >= 3:
        score += 10
        feedback.append(f"Connectivity good ({edges} edges).")
    elif edges > 0:
        score += 5
        feedback.append(f"Partial connectivity ({edges} edges).")
    else:
        feedback.append("No connections found.")

    # 7. Grouping (10 pts)
    groups = data.get("diagram_groups_count", 0)
    # We expect at least 4 groups (1 hub + 3 probes)
    if groups >= 4:
        score += 10
        feedback.append(f"Grouping detected ({groups} groups).")
    elif groups > 0:
        score += 5
        feedback.append(f"Some grouping detected ({groups} groups), expected at least 4.")
    else:
        feedback.append("No grouped shapes detected. Symbols should be grouped.")

    # Final result
    passed = (score >= 70)
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }