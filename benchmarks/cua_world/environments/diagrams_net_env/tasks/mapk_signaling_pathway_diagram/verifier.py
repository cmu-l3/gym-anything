#!/usr/bin/env python3
import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

def verify_mapk_signaling_pathway_diagram(traj, env_info, task_info):
    """
    Verifies the MAPK Signaling Pathway Diagram task.
    
    Criteria:
    1. File Modification (Anti-Gaming): Diagram file modified after start.
    2. Content Verification (XML Parse):
       - Presence of 10 specific molecules.
       - Edges connecting them.
       - Legend and Phosphorylation labels.
    3. Export Verification: PNG file exists and has size > 0.
    4. VLM Verification: Trajectory analysis to ensure manual work was done.
    """
    
    # 1. Setup & Data Loading
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env missing"}

    # Load result JSON from container
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, "r") as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result data: {str(e)}"}
    finally:
        if os.path.exists(temp_result.name):
            os.remove(temp_result.name)

    # 2. Extract Metrics
    file_modified = result_data.get("file_modified", False)
    export_exists = result_data.get("export_exists", False)
    export_size = result_data.get("export_size", 0)
    
    xml_data = result_data.get("xml_analysis", {})
    found_molecules = xml_data.get("found_molecules", [])
    edge_count = xml_data.get("edge_count", 0)
    phosphorylation_label = xml_data.get("phosphorylation_label", False)
    legend_detected = xml_data.get("legend_detected", False)
    
    required_molecules = task_info.get("metadata", {}).get("required_molecules", [])

    # 3. Scoring Logic
    score = 0
    feedback = []

    # Criterion A: Anti-Gaming (5 pts)
    if file_modified:
        score += 5
        feedback.append("File modified.")
    else:
        feedback.append("File NOT modified (Anti-gaming check failed).")

    # Criterion B: Export (10 pts)
    if export_exists and export_size > 1000:  # >1KB to ensure not empty
        score += 10
        feedback.append("PNG export found.")
    else:
        feedback.append("PNG export missing or empty.")

    # Criterion C: Molecule Content (50 pts, 5 per molecule)
    molecule_score = 0
    missing_mols = []
    for mol in required_molecules:
        # Case insensitive partial match is handled in export_result.sh, we just check list
        if mol in found_molecules:
            molecule_score += 5
        else:
            missing_mols.append(mol)
    
    score += molecule_score
    if not missing_mols:
        feedback.append("All 10 molecules found.")
    else:
        feedback.append(f"Missing molecules: {', '.join(missing_mols)}.")

    # Criterion D: Connections (10 pts)
    # Start file has 1 edge (membrane line). We expect at least 8 more for the cascade.
    if edge_count >= 9:
        score += 10
        feedback.append(f"Sufficient connections found ({edge_count}).")
    elif edge_count >= 4:
        score += 5
        feedback.append(f"Partial connections found ({edge_count}).")
    else:
        feedback.append("Insufficient connections.")

    # Criterion E: Details (Legend & Labels) (10 pts)
    if phosphorylation_label:
        score += 5
        feedback.append("Phosphorylation label found.")
    if legend_detected:
        score += 5
        feedback.append("Legend found.")

    # Criterion F: VLM Trajectory Verification (15 pts)
    # We check if the agent actually built the diagram
    vlm_score = 0
    try:
        frames = sample_trajectory_frames(traj, n=4)
        if frames:
            prompt = (
                "These are screenshots of a user using draw.io to create a biological pathway diagram. "
                "Did the user progressively add shapes and arrows to build a flowchart-like diagram? "
                "Answer yes or no."
            )
            vlm_resp = query_vlm(images=frames, prompt=prompt)
            if vlm_resp and "yes" in str(vlm_resp).lower():
                vlm_score = 15
                feedback.append("VLM confirms active diagramming workflow.")
            else:
                feedback.append("VLM could not confirm active diagramming.")
        else:
            feedback.append("No trajectory frames available for VLM.")
    except Exception as e:
        feedback.append(f"VLM check failed: {str(e)}")
    
    score += vlm_score

    # 4. Final Decision
    # Pass if score >= 60 AND critical content (at least 5 molecules) is present
    passed = (score >= 60) and (molecule_score >= 25)

    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }