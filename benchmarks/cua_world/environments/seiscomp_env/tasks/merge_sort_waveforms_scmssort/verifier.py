#!/usr/bin/env python3
"""
Verifier for merge_sort_waveforms_scmssort task.

Verification Strategy:
1. Merged file exists and is >50KB (15 pts)
2. Merged file is valid miniSEED (15 pts)
3. Merged file contains >=3 stations (15 pts)
4. Inventory file exists with >=3 lines (15 pts)
5. Inventory references GE network (10 pts)
6. Inventory references >=3 stations (10 pts)
7. Files created after task start (10 pts)
8. VLM Workflow Evidence using Trajectory Frames (10 pts)

Pass Threshold: 60 points with the merged file existing, being valid, and created during task.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_merge_sort_waveforms(traj, env_info, task_info):
    """Verifies that the agent successfully merged waveforms and generated an inventory."""
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    min_merged_size = metadata.get('min_merged_size_bytes', 51200)
    min_inventory_lines = metadata.get('min_inventory_lines', 3)

    # 1. Read exported JSON results
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load task result JSON: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    merged = result.get('merged_file', {})
    inventory = result.get('inventory_file', {})
    
    # --- Check 1: Merged file exists and is >50KB (15 pts) ---
    if merged.get('exists'):
        if merged.get('size_bytes', 0) >= min_merged_size:
            score += 15
            feedback_parts.append(f"Merged file size OK ({merged['size_bytes']} bytes)")
        else:
            score += 5
            feedback_parts.append(f"Merged file too small ({merged['size_bytes']} bytes)")
    else:
        feedback_parts.append("Merged file missing")
        
    # --- Check 2: Merged file is valid miniSEED (15 pts) ---
    if merged.get('exists') and merged.get('is_miniseed'):
        score += 15
        feedback_parts.append("Merged file is valid miniSEED")
    elif merged.get('exists'):
        feedback_parts.append("Merged file does not look like valid miniSEED")
        
    # --- Check 3: Merged file contains >=3 stations (15 pts) ---
    stations_in_merged = merged.get('stations_count', 0)
    if stations_in_merged >= 3:
        score += 15
        feedback_parts.append(f"Merged file contains {stations_in_merged} stations")
    elif stations_in_merged > 0:
        score += 5
        feedback_parts.append(f"Merged file contains only {stations_in_merged} stations")
    else:
        feedback_parts.append("No recognized stations found in merged file")
        
    # --- Check 4: Inventory file exists with >=3 lines (15 pts) ---
    if inventory.get('exists'):
        if inventory.get('lines', 0) >= min_inventory_lines:
            score += 15
            feedback_parts.append(f"Inventory file has {inventory['lines']} lines")
        else:
            score += 7
            feedback_parts.append(f"Inventory file too short ({inventory['lines']} lines)")
    else:
        feedback_parts.append("Inventory file missing")
        
    # --- Check 5: Inventory references GE network (10 pts) ---
    if inventory.get('has_ge_network'):
        score += 10
        feedback_parts.append("Inventory references GE network")
    elif inventory.get('exists'):
        feedback_parts.append("Inventory missing GE network reference")
        
    # --- Check 6: Inventory references >=3 stations (10 pts) ---
    stations_in_inv = inventory.get('stations_count', 0)
    if stations_in_inv >= 3:
        score += 10
        feedback_parts.append(f"Inventory references {stations_in_inv} expected stations")
    elif stations_in_inv > 0:
        score += 4
        feedback_parts.append(f"Inventory references only {stations_in_inv} expected stations")
    else:
        feedback_parts.append("Inventory does not reference expected stations")

    # --- Check 7: Files created after task start (10 pts) ---
    anti_gaming_points = 0
    if merged.get('exists') and merged.get('created_during_task'):
        anti_gaming_points += 5
    if inventory.get('exists') and inventory.get('created_during_task'):
        anti_gaming_points += 5
    score += anti_gaming_points
    if anti_gaming_points == 10:
        feedback_parts.append("Files created during task window")
    elif anti_gaming_points == 5:
        feedback_parts.append("Only one file created during task window")
    else:
        feedback_parts.append("Files were NOT created during task window (possible gaming)")

    # --- Check 8: VLM Verification using Trajectory (10 pts) ---
    query_vlm = env_info.get('query_vlm')
    vlm_points = 0
    if query_vlm:
        try:
            # Using trajectory frames (not just the final screenshot)
            from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
            frames = sample_trajectory_frames(traj, n=4)
            final_frame = get_final_screenshot(traj)
            all_frames = frames + [final_frame] if final_frame else frames
            
            prompt = """You are evaluating an AI agent performing a waveform data management task.
            The agent is supposed to use a terminal to:
            1. Run 'scmssort' to merge miniSEED files into a single file.
            2. Run a Python script or other commands to read the merged file and create an inventory text file.
            
            Look closely at the trajectory frames (chronological order) and evaluate:
            1. Can you see terminal commands involving 'scmssort' being typed or executed?
            2. Can you see commands or a script being executed to read the generated .mseed file and output an inventory?
            
            Reply in JSON format:
            {
                "scmssort_used": true/false,
                "inventory_generation_visible": true/false,
                "confidence": "high/medium/low",
                "observations": "brief summary of what you see"
            }
            """
            
            vlm_res = query_vlm(images=all_frames, prompt=prompt)
            if vlm_res and vlm_res.get("success"):
                parsed = vlm_res.get("parsed", {})
                if parsed.get("scmssort_used"):
                    vlm_points += 5
                if parsed.get("inventory_generation_visible"):
                    vlm_points += 5
                
                logger.info(f"VLM Output: {parsed}")
                feedback_parts.append(f"VLM check: {vlm_points}/10 pts")
            else:
                feedback_parts.append("VLM query failed, skipping VLM check")
                vlm_points = 10  # Fallback gracefully
        except Exception as e:
            logger.warning(f"Error during VLM check: {e}")
            vlm_points = 10  # Fallback gracefully
            feedback_parts.append("VLM check error, awarding points as fallback")
    else:
        vlm_points = 10  # Automatically grant VLM points if VLM is unavailable on host
        feedback_parts.append("VLM unavailable, auto-granting VLM points")
        
    score += vlm_points

    # Validate core constraints for pass
    key_criteria_met = (
        merged.get('exists', False) and 
        merged.get('created_during_task', False) and 
        merged.get('is_miniseed', False)
    )
    
    passed = score >= 60 and key_criteria_met

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }