#!/usr/bin/env python3
"""
Verifier for cosmetics_shampoo_recipe_manager task.

Uses a hybrid approach:
1. Programmatic binary string search to confirm tags, recipes, and exclusion of obsolete data.
2. VLM (Vision-Language Model) trajectory analysis to verify the exact matrix grid mapping.

Anti-Gaming features:
- "Classic_Sulfates" presence immediately zeros out the score (Judgment check).
- Timestamp check ensures the project file was actually created during the task.
- VLM trajectory check ensures the agent actually used the Recipe Manager UI, rather
  than just naming tags with the recipe names.
"""

import os
import json
import logging
import tempfile
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_cosmetics_recipe_manager(traj, env_info, task_info):
    """Verifies the cosmetics recipe manager task."""
    
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Framework error: copy_from_env not available."}

    # Fetch result JSON from the container
    try:
        tmp = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
        tmp_path = tmp.name
        tmp.close()
        
        copy_from_env("C:/tmp/recipe_result.json", tmp_path)
        with open(tmp_path, "r", encoding="utf-8-sig") as f:
            result = json.load(f)
    except FileNotFoundError:
        return {"passed": False, "score": 0, "feedback": "Result file not found. Project was not saved."}
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Error reading result: {e}"}
    finally:
        if os.path.exists(tmp_path):
            os.unlink(tmp_path)

    # ---------------------------------------------------------
    # GATE 1: Did the agent save the project?
    # ---------------------------------------------------------
    if not result.get("project_found"):
        return {"passed": False, "score": 0, "feedback": "Project file 'cosmetics_recipes.c3' not found."}
    
    if not result.get("file_created_during_task"):
        return {"passed": False, "score": 0, "feedback": "Project file was not modified during the task."}

    strings_found = result.get("strings_found", {})
    
    # ---------------------------------------------------------
    # GATE 2: Judgment Failure (Did they enter the obsolete recipe?)
    # ---------------------------------------------------------
    if strings_found.get("Classic_Sulfates", False):
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "FAILED: Agent configured 'Classic_Sulfates'. This recipe is obsolete and should have been excluded."
        }

    # ---------------------------------------------------------
    # SCORING - Programmatic Checks (40 Points)
    # ---------------------------------------------------------
    score = 0
    feedback_parts = []
    
    # Tags created (16 pts, 4 per tag)
    tag_score = 0
    missing_tags = []
    for tag in ["SP_Water", "SP_Surfactant", "SP_Fragrance", "SP_Active"]:
        if strings_found.get(tag, False):
            tag_score += 4
        else:
            missing_tags.append(tag)
    
    score += tag_score
    if missing_tags:
        feedback_parts.append(f"Missing target tags: {', '.join(missing_tags)}")
    else:
        feedback_parts.append("All SP_ target tags created")

    # Recipe Book (9 pts)
    if strings_found.get("Shampoo_Variants", False):
        score += 9
        feedback_parts.append("Recipe Book named correctly")
    else:
        feedback_parts.append("Recipe Book 'Shampoo_Variants' missing")

    # Active Recipes Present (15 pts, 5 per recipe)
    recipe_score = 0
    missing_recipes = []
    for recipe in ["Standard_Daily", "Anti_Dandruff", "Volumizing"]:
        if strings_found.get(recipe, False):
            recipe_score += 5
        else:
            missing_recipes.append(recipe)
            
    score += recipe_score
    if missing_recipes:
        feedback_parts.append(f"Missing active recipes: {', '.join(missing_recipes)}")
    else:
        feedback_parts.append("All 3 active recipes found")

    # ---------------------------------------------------------
    # SCORING - VLM Trajectory Verification (60 Points)
    # ---------------------------------------------------------
    query_vlm = env_info.get("query_vlm")
    if query_vlm and score >= 20: # Only call VLM if programmatic baseline is partially met
        frames = sample_trajectory_frames(traj, n=5)
        final_frame = get_final_screenshot(traj)
        if final_frame:
            frames.append(final_frame)
            
        vlm_prompt = """
        Review these screenshots from an agent configuring Red Lion Crimson 3.0.
        
        The agent's goal was to configure a Recipe Book called "Shampoo_Variants" with 4 ingredients mapped to Float tags (SP_Water, SP_Surfactant, SP_Fragrance, SP_Active).
        They also needed to input a matrix of recipe values.
        
        Please evaluate the following:
        1. Did the agent navigate to the "Recipes" section in the left navigation pane?
        2. Is there evidence of the agent filling out the Recipe matrix/grid with numeric values (e.g., 750, 200, 10, etc.)?
        3. Does the trajectory show meaningful progression through creating tags and then mapping recipes?
        
        Return a JSON object:
        {
            "recipe_ui_used": true/false,
            "matrix_values_visible": true/false,
            "meaningful_progression": true/false
        }
        """
        
        try:
            vlm_response = query_vlm(prompt=vlm_prompt, images=frames)
            parsed = vlm_response.get("parsed", {})
            
            if parsed.get("recipe_ui_used"):
                score += 20
                feedback_parts.append("VLM: Recipe UI usage confirmed")
            else:
                feedback_parts.append("VLM: Could not confirm Recipe UI usage")
                
            if parsed.get("matrix_values_visible"):
                score += 20
                feedback_parts.append("VLM: Recipe matrix values visible")
                
            if parsed.get("meaningful_progression"):
                score += 20
        except Exception as e:
            logger.error(f"VLM check failed: {e}")
            feedback_parts.append("VLM verification skipped/failed")
    else:
        feedback_parts.append("VLM verification skipped due to missing prerequisites")

    # Pass Threshold: 75
    passed = score >= 75
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }