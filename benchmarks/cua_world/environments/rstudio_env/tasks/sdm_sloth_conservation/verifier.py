#!/usr/bin/env python3
"""
Verifier for Species Distribution Modeling task.

Scoring (100 points total):
1. Package Installation (10 pts): Required packages installed.
2. Model Metrics (25 pts): AUC CSV exists and AUC > 0.80.
3. Variable Importance (15 pts): CSV exists with data.
4. Suitability Map (30 pts): PNG exists, reasonable size (>20KB).
5. VLM Verification (20 pts): Map looks like a spatial plot of South/Central America.

Pass threshold: 60 points
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

RESULT_PATH = "/tmp/task_result.json"

# VLM Prompt for Map Verification
MAP_VERIFICATION_PROMPT = """You are evaluating a Species Distribution Model (SDM) map for the Brown-throated Sloth in South/Central America.

Analyze the image:
1. Is this a map (spatial plot) rather than a scatter plot or code screenshot?
2. Does it show a geographical shape resembling northern South America / Central America?
3. Does it show a gradient of values (e.g., probability scale, heatmap colors)?

Respond in JSON:
{
    "is_spatial_map": true/false,
    "shows_geographic_shape": true/false,
    "has_value_gradient": true/false,
    "confidence": "low/medium/high"
}
"""

def verify_sdm_sloth_conservation(traj, env_info, task_info):
    """Verify the SDM task execution and results."""
    
    # 1. Setup - Get data from container
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    get_final_screenshot = env_info.get('get_final_screenshot')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    tmp.close()
    
    try:
        try:
            copy_from_env(RESULT_PATH, tmp.name)
            with open(tmp.name, 'r') as f:
                result = json.load(f)
        except FileNotFoundError:
            return {"passed": False, "score": 0, "feedback": "Result file not found - export script failed"}
        except json.JSONDecodeError:
            return {"passed": False, "score": 0, "feedback": "Result JSON malformed"}
    finally:
        if os.path.exists(tmp.name):
            os.unlink(tmp.name)

    score = 0
    feedback = []

    # 2. Score Package Installation (10 pts)
    if result.get('packages_installed', False):
        score += 10
        feedback.append("Packages installed successfully (10/10)")
    else:
        feedback.append("Required packages (dismo, randomForest) not detected in user library (0/10)")

    # 3. Score Model Metrics (25 pts)
    auc = float(result.get('auc_value', 0))
    metrics_exists = result.get('metrics_exists', False)
    
    if metrics_exists:
        if auc >= 0.80:
            score += 25
            feedback.append(f"Model AUC excellent ({auc:.3f}) (25/25)")
        elif auc >= 0.60:
            score += 15
            feedback.append(f"Model AUC acceptable but low ({auc:.3f}) (15/25)")
        else:
            score += 5
            feedback.append(f"Model AUC too low ({auc:.3f}) (5/25)")
    else:
        feedback.append("Metrics CSV not found (0/25)")

    # 4. Score Variable Importance (15 pts)
    if result.get('var_imp_exists', False) and result.get('var_imp_rows', 0) > 1:
        score += 15
        feedback.append("Variable importance CSV created (15/15)")
    else:
        feedback.append("Variable importance CSV missing or empty (0/15)")

    # 5. Score Suitability Map (30 pts)
    map_exists = result.get('map_exists', False)
    map_new = result.get('map_is_new', False)
    map_size = result.get('map_size_kb', 0)
    
    if map_exists and map_new:
        if map_size > 20:
            score += 30
            feedback.append("Suitability map created and valid size (30/30)")
        else:
            score += 10
            feedback.append(f"Suitability map created but file size suspicious ({map_size}KB) (10/30)")
    else:
        feedback.append("Suitability map missing or not created during task (0/30)")

    # 6. VLM Verification (20 pts)
    # Note: We prioritize the generated map file for VLM if possible, but standard interface 
    # usually runs VLM on screenshots. We'll use the final screenshot for VLM context 
    # or the map if we could extract it (here we rely on final screenshot showing the plot 
    # or the agent viewing the plot).
    
    # Check if we passed the map generation; if so, we trust the file check heavily. 
    # We add VLM score based on general workflow if visual confirmation is tricky.
    
    final_screen = get_final_screenshot(traj)
    vlm_score = 0
    if query_vlm and final_screen:
        try:
            vlm_res = query_vlm(prompt=MAP_VERIFICATION_PROMPT, image=final_screen)
            if vlm_res.get('success'):
                parsed = vlm_res.get('parsed', {})
                if parsed.get('is_spatial_map') or parsed.get('shows_geographic_shape'):
                    vlm_score = 20
                    feedback.append("VLM confirms map visualization visible (20/20)")
                else:
                    feedback.append("VLM could not confirm map content in final screenshot (0/20)")
            else:
                # If VLM fails but file exists, give partial credit benefit of doubt
                if map_exists:
                    vlm_score = 10
                    feedback.append("VLM failed, partial credit for file existence (10/20)")
        except Exception as e:
            logger.warning(f"VLM error: {e}")
            if map_exists: vlm_score = 10 # Fallback
    
    # Adjust total to 100 max (current sum logic: 10+25+15+30+20 = 100)
    score += vlm_score

    # Final result
    passed = score >= 60 and map_exists and metrics_exists
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }