#!/usr/bin/env python3
"""
Verifier for shortest_path_social_network task.
Compares agent's JSON output against Ground Truth calculated from the database state.
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import query_vlm, get_final_screenshot, sample_trajectory_frames

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_shortest_path_social_network(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Retrieve Result JSON (contains both Agent Output and Ground Truth)
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result_final.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result file: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    agent_output = result.get("agent_output", {})
    ground_truth = result.get("ground_truth", {})
    task_meta = result.get("task_info", {})

    score = 0
    feedback = []

    # --- Criterion 1: File Existence & Validity (10 pts) ---
    if not task_meta.get("output_exists"):
        return {"passed": False, "score": 0, "feedback": "Output file not found"}
    
    if not agent_output:
        return {"passed": False, "score": 0, "feedback": "Output file is empty or invalid JSON"}
    
    score += 10
    feedback.append("File exists and is valid JSON")

    # --- Criterion 2: Anti-Gaming (10 pts) ---
    if task_meta.get("file_created_during_task"):
        score += 10
        feedback.append("File created during task window")
    else:
        feedback.append("WARNING: File timestamp predates task start")

    # --- Criterion 3: Path to Schafer (20 pts) ---
    # Expected: 3 hops, specific path
    a_schafer = agent_output.get("path_to_schafer", {})
    g_schafer = ground_truth.get("path_to_schafer", {})
    
    if a_schafer.get("hops") == g_schafer.get("hops"):
        score += 10
        # Check path content (exact match)
        a_path = [e.lower().strip() for e in a_schafer.get("path_emails", [])]
        g_path = [e.lower().strip() for e in g_schafer.get("path_emails", [])]
        if a_path == g_path:
            score += 10
            feedback.append(f"Schafer path correct ({g_schafer['hops']} hops)")
        else:
            feedback.append(f"Schafer hops correct but path mismatch")
    else:
        feedback.append(f"Schafer path hops incorrect (Got {a_schafer.get('hops')}, Expected {g_schafer.get('hops')})")

    # --- Criterion 4: Path to Petrakis (20 pts) ---
    # Expected: 4 hops
    a_petrakis = agent_output.get("path_to_petrakis", {})
    g_petrakis = ground_truth.get("path_to_petrakis", {})
    
    if a_petrakis.get("hops") == g_petrakis.get("hops"):
        score += 10
        a_path = [e.lower().strip() for e in a_petrakis.get("path_emails", [])]
        g_path = [e.lower().strip() for e in g_petrakis.get("path_emails", [])]
        if a_path == g_path:
            score += 10
            feedback.append(f"Petrakis path correct ({g_petrakis['hops']} hops)")
        else:
            feedback.append(f"Petrakis hops correct but path mismatch")
    else:
        feedback.append(f"Petrakis path hops incorrect (Got {a_petrakis.get('hops')}, Expected {g_petrakis.get('hops')})")

    # --- Criterion 5: Connectivity Check (10 pts) ---
    # Expected: False
    a_exists = agent_output.get("path_to_tanaka_exists")
    g_exists = ground_truth.get("path_to_tanaka_exists")
    
    # Handle string 'true'/'false' from JSON
    if isinstance(a_exists, str):
        a_exists = a_exists.lower() == 'true'
        
    if a_exists == g_exists:
        score += 10
        feedback.append(f"Tanaka connectivity correct ({str(g_exists)})")
    else:
        feedback.append(f"Tanaka connectivity incorrect (Got {a_exists}, Expected {g_exists})")

    # --- Criterion 6: Friends of Friends (20 pts) ---
    # Expected: Set match
    a_fof = set([e.lower().strip() for e in agent_output.get("friends_of_friends", [])])
    g_fof = set([e.lower().strip() for e in ground_truth.get("friends_of_friends", [])])
    
    if a_fof == g_fof:
        score += 20
        feedback.append(f"Friends of Friends correct ({len(g_fof)} emails)")
    else:
        # Partial credit
        intersection = a_fof.intersection(g_fof)
        if len(intersection) > 0 and len(a_fof) <= len(g_fof) + 2:
            partial = int(20 * (len(intersection) / len(g_fof)))
            score += partial
            feedback.append(f"Friends of Friends partially correct ({len(intersection)}/{len(g_fof)} found)")
        else:
            feedback.append("Friends of Friends incorrect")

    # --- Criterion 7: VLM Check (10 pts) ---
    # Verify agent actually used the UI (Studio or similar)
    frames = sample_trajectory_frames(traj, n=3)
    final_screen = get_final_screenshot(traj)
    
    vlm_prompt = """
    Is the user interacting with OrientDB Studio (a web interface with a graph/database look)?
    Look for:
    - 'OrientDB Studio' logo or header
    - A graph visualization (nodes and lines)
    - SQL query editor
    - JSON results
    
    Answer JSON: {"using_orientdb": true/false}
    """
    
    vlm_score = 0
    try:
        # Check just one frame to save tokens/time, or final
        res = query_vlm(prompt=vlm_prompt, image=final_screen)
        if res.get("parsed", {}).get("using_orientdb", False):
            vlm_score = 10
        else:
            # Fallback to checking a mid-trajectory frame
            if frames:
                res = query_vlm(prompt=vlm_prompt, image=frames[0])
                if res.get("parsed", {}).get("using_orientdb", False):
                    vlm_score = 10
    except Exception:
        pass # VLM fail shouldn't crash verifier
        
    if vlm_score > 0:
        score += 10
        feedback.append("VLM verified OrientDB usage")
    else:
        feedback.append("VLM could not verify OrientDB usage")

    return {
        "passed": score >= 60,
        "score": score,
        "feedback": " | ".join(feedback)
    }