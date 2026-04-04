#!/usr/bin/env python3
import json
import os
import tempfile
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

def verify_watergate_scandal_link_map(traj, env_info, task_info):
    """
    Verifies the Watergate Link Map task using file analysis and VLM.
    """
    # 1. Setup
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System Error: Copy function missing"}

    # 2. Retrieve JSON result from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Could not retrieve task results: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 3. Scoring Criteria
    score = 0
    feedback = []
    
    # Metadata targets
    metadata = task_info.get('metadata', {})
    required_actors = [a.lower() for a in metadata.get('required_actors', [])]
    
    # Criterion A: Files Exist & Fresh (10 pts)
    if result.get('drawio_exists') and result.get('file_fresh'):
        score += 10
        feedback.append("Draw.io file saved and modified.")
    else:
        feedback.append("Draw.io file missing or not saved.")
        
    if result.get('png_exists') and result.get('png_size', 0) > 2000:
        score += 10
        feedback.append("Valid PNG export found.")
    else:
        feedback.append("PNG export missing or empty.")

    # Criterion B: Actors Mapped (30 pts)
    # We check how many of the required actors were found in the XML
    found_actors = result.get('actors_found', [])
    # Filter aliases (e.g., 'operative' might match 'operatives' group, not a person)
    # The extraction script separates them fairly well, but let's be lenient.
    
    match_count = len(found_actors)
    if match_count >= 7:
        score += 30
        feedback.append(f"Excellent: Found {match_count} key actors.")
    elif match_count >= 4:
        score += 15
        feedback.append(f"Good: Found {match_count} key actors.")
    elif match_count > 0:
        score += 5
        feedback.append(f"Weak: Only found {match_count} actors.")
    else:
        feedback.append("No key actors found in diagram text.")

    # Criterion C: Organization Groups (15 pts)
    found_groups = result.get('groups_found', [])
    # We look for "white house", "creep", "operative"
    if len(found_groups) >= 2:
        score += 15
        feedback.append("Organization grouping detected.")
    elif len(found_groups) == 1:
        score += 7
        feedback.append("Partial organization grouping detected.")
    else:
        feedback.append("No clear organization groups found (White House, CREEP, etc).")

    # Criterion D: Connections & Labels (25 pts)
    edge_count = result.get('edge_count', 0)
    label_count = result.get('labeled_edge_count', 0)
    
    if edge_count >= 5:
        score += 15
        feedback.append(f"Found {edge_count} connections.")
    elif edge_count >= 2:
        score += 5
        feedback.append(f"Found {edge_count} connections (sparse).")
        
    if label_count >= 3:
        score += 10
        feedback.append("Connections are labeled.")
    elif label_count > 0:
        score += 5
        feedback.append("Some connection labels missing.")

    # Criterion E: VLM Visual Verification (10 pts)
    # File analysis is good for text, but VLM confirms it looks like a network map
    vlm_score = 0
    try:
        final_screen = get_final_screenshot(traj)
        if final_screen:
            response = query_vlm(
                images=[final_screen],
                prompt="""Analyze this draw.io diagram. 
                1. Does it look like a network diagram or org chart with boxes and arrows?
                2. Are there groupings or containers separating different teams?
                3. Is it non-empty?
                Answer yes/no for each."""
            )
            resp_text = str(response).lower()
            if "yes" in resp_text:
                vlm_score = 10
                feedback.append("VLM confirms visual diagram structure.")
            else:
                feedback.append("VLM could not confirm diagram structure.")
    except Exception:
        # Fallback if VLM fails/not avail, give points if file checks passed high bar
        if score > 60:
            vlm_score = 10
    
    score += vlm_score

    # Final tally
    passed = score >= 65
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }