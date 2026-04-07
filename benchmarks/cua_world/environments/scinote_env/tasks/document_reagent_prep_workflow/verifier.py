#!/usr/bin/env python3
"""Verifier for document_reagent_prep_workflow task."""

import json
import tempfile
import os

def check_assignments_vlm(traj, env_info):
    """Fallback to VLM if database schema for assignments couldn't be automatically queried."""
    from gym_anything.vlm import sample_trajectory_frames, query_vlm
    
    frames = sample_trajectory_frames(traj, n=8)
    if not frames:
        return False

    prompt = """
    Review these screenshots from an agent documenting a reagent preparation workflow in SciNote ELN.
    
    TASK: Did the agent successfully assign the 4 chemical ingredients (NaCl, KCl, Na2HPO4, KH2PO4) to the "Prepare 10x PBS Stock" task?
    
    Look for:
    - An "Assigned items" section within the task view showing inventory items.
    - A modal or side panel where inventory items from "Chemical Storage" were selected.
    - Mentions of the specific chemicals being linked or assigned.
    
    Respond in strict JSON format:
    {
        "ingredients_assigned": true/false,
        "confidence": "high/medium/low",
        "reasoning": "Briefly explain what UI evidence proves or disproves the assignment."
    }
    """
    
    query_func = env_info.get('query_vlm')
    if not query_func:
        return False
        
    result = query_func(prompt=prompt, images=frames)
    if not result.get("success"):
        return False
        
    parsed = result.get("parsed", {})
    return parsed.get("ingredients_assigned", False)


def verify_reagent_prep_workflow(traj, env_info, task_info):
    """Verify that the full workflow (Task -> Assignment -> QC Result -> New Item) was completed."""

    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/reagent_prep_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    task_found = result.get('task_found', False)
    result_text = result.get('result_text', '').lower()
    output_found = result.get('output_item_found', False)
    assigned_count = result.get('assigned_count', 0)
    assigned_ingredients = result.get('assigned_ingredients', [])
    
    initial_stock = result.get('initial_stock_count', 0)
    current_stock = result.get('current_stock_count', 0)

    # Criterion 1 (20 pts): Task Created
    if task_found:
        score += 20
        feedback_parts.append("Task 'Prepare 10x PBS Stock' found")
    else:
        feedback_parts.append("Task 'Prepare 10x PBS Stock' NOT found")

    # Criterion 2 (20 pts): Result text contains pH data
    ph_found = "ph" in result_text and "7.4" in result_text
    if ph_found:
        score += 20
        feedback_parts.append("pH 7.4 recorded in task results")
    elif task_found:
        feedback_parts.append(f"pH data missing from results (found: '{result_text[:50]}...')")
    else:
        feedback_parts.append("Cannot check pH (task not found)")

    # Criterion 3 (20 pts): Final Output Item Created
    if output_found and (current_stock > initial_stock):
        score += 20
        feedback_parts.append("Final '10x PBS' item successfully added to Stock Solutions")
    else:
        feedback_parts.append("Final '10x PBS' item NOT found in Stock Solutions")

    # Criterion 4 (40 pts): Inventory Assigned
    assignments_verified = False
    if assigned_count >= 4:
        # Check if the right ingredients were assigned
        matches = sum(1 for ing in assigned_ingredients if any(c in ing for c in ['NaCl', 'KCl', 'Na2HPO4', 'KH2PO4']))
        if matches >= 4:
            assignments_verified = True
            score += 40
            feedback_parts.append("4 Chemical ingredients verified via database assignments")
        else:
            score += 20
            feedback_parts.append(f"Items assigned, but name match failed. Items: {assigned_ingredients}")
            
    # Fallback to VLM if DB query couldn't resolve the link table (schema variations)
    if not assignments_verified and task_found:
        vlm_verified = check_assignments_vlm(traj, env_info)
        if vlm_verified:
            assignments_verified = True
            score += 40
            feedback_parts.append("Ingredient assignment verified via VLM trajectory analysis")
        else:
            feedback_parts.append("Ingredient assignments not detected in database or trajectory")

    # Must accomplish the core flow: Task + Assignments + Final Item
    passed = task_found and output_found and assignments_verified

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "subscores": {
            "task_created": task_found,
            "ph_recorded": ph_found,
            "output_item_created": output_found,
            "ingredients_assigned": assignments_verified
        }
    }