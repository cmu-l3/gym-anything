#!/usr/bin/env python3
"""
Verifier for create_prescription_favorite task.

Checks:
1. A new favorite exists in the database for the provider.
2. The favorite contains the correct drug details (Amoxicillin 500).
3. The favorite contains the correct instructions (TID, 10 days).
4. The favorite has the correct quantity (30).
5. VLM verification of the trajectory (UI interaction).
"""

import json
import os
import logging
import tempfile
import sys

# Add parent directory for shared utilities
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from gym_anything.vlm import sample_trajectory_frames, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_prescription_favorite(traj, env_info, task_info):
    """
    Verify the prescription favorite creation task.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Metadata expectations
    metadata = task_info.get('metadata', {})
    expected_drug = metadata.get('expected_drug_name', 'Amoxicillin')
    expected_strength = metadata.get('expected_strength', '500')
    expected_qty = metadata.get('expected_qty', '30')
    expected_name = metadata.get('expected_fav_name', 'Strep Throat')
    
    # Load result from container
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

    score = 0
    feedback_parts = []
    
    # Database Verification (70 points)
    favorites = result.get('favorites', [])
    initial_count = int(result.get('initial_count', 0))
    current_count = len(favorites)
    
    # Check 1: Did count increase? (10 pts)
    if current_count > initial_count:
        score += 10
        feedback_parts.append("New favorite record created.")
    else:
        feedback_parts.append("No new favorite record found.")
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "No favorite created. " + " | ".join(feedback_parts)
        }

    # Find the best matching favorite
    best_match_score = 0
    best_fav = None
    
    for fav in favorites:
        # Calculate a match score for this favorite
        current_match_score = 0
        
        # Check Name (template_name)
        fav_name = fav.get('template_name', '')
        if expected_name.lower() in fav_name.lower():
            current_match_score += 15
        
        # Check Drug Name/Description
        # Note: Fields might be 'drug_name', 'brand_name', or 'description' depending on Oscar version
        d_name = fav.get('drug_name', '') or fav.get('brand_name', '') or fav.get('archived_drug_name', '')
        if expected_drug.lower() in d_name.lower() and expected_strength in d_name:
            current_match_score += 20
        
        # Check Instructions
        instr = fav.get('instructions', '').lower()
        if ("three times" in instr or "tid" in instr) and ("10 days" in instr or "10 day" in instr):
            current_match_score += 15
            
        # Check Quantity
        qty = str(fav.get('quantity', ''))
        if expected_qty in qty:
            current_match_score += 10

        if current_match_score > best_match_score:
            best_match_score = current_match_score
            best_fav = fav

    score += best_match_score
    
    if best_match_score > 0:
        feedback_parts.append(f"Found matching favorite: {best_fav.get('template_name', 'Unknown')}")
        if best_match_score >= 60:
            feedback_parts.append("Favorite details match expectations.")
        else:
            feedback_parts.append("Favorite details partially match.")
    else:
        feedback_parts.append("Created favorite does not match expected criteria.")

    # VLM Verification (30 points)
    # Check if the agent actually navigated the UI correctly
    try:
        frames = sample_trajectory_frames(traj, n=4)
        vlm_prompt = """
        Analyze these screenshots of a user in an EMR system (Oscar EMR).
        Look for:
        1. The user searching for a drug (Amoxicillin).
        2. The user entering prescription details (instructions, quantity).
        3. The user clicking a 'Star' icon, 'Add to Favorites', or 'Save Profile' button.
        
        Does the user appear to be saving a prescription favorite/macro?
        Answer with JSON: {"saving_favorite": boolean, "drug_seen": boolean, "confidence": float}
        """
        
        vlm_result = query_vlm(images=frames, prompt=vlm_prompt)
        
        if vlm_result and vlm_result.get('parsed', {}).get('saving_favorite', False):
            score += 30
            feedback_parts.append("VLM confirms favorite saving workflow.")
        elif vlm_result and vlm_result.get('parsed', {}).get('drug_seen', False):
            score += 15
            feedback_parts.append("VLM confirms drug selection but unsure about saving favorite.")
        else:
            feedback_parts.append("VLM could not confirm workflow.")
            
    except Exception as e:
        logger.warning(f"VLM check failed: {e}")
        # Fallback: if DB score is high, give partial credit for VLM
        if score >= 60:
            score += 15
            feedback_parts.append("VLM skipped, implicit pass based on DB.")

    passed = score >= 70
    
    return {
        "passed": passed,
        "score": min(100, score),
        "feedback": " | ".join(feedback_parts)
    }