#!/usr/bin/env python3
"""
Verifier for add_drug_inventory task.

Checks:
1. Database record existence for 'Metformin' (25 pts)
2. Correct Name format (15 pts)
3. Correct NDC (15 pts)
4. Attributes (Form, Route, Size) (25 pts)
5. Anti-gaming (Count increase) (10 pts)
6. VLM Trajectory (10 pts)
"""

import json
import os
import tempfile
import logging
from typing import Dict, Any

# Import VLM utils from framework
try:
    from gym_anything.vlm import sample_trajectory_frames, query_vlm
except ImportError:
    # Fallback for local testing
    def sample_trajectory_frames(traj, n=5): return []
    def query_vlm(images, prompt): return {"success": False}

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_add_drug_inventory(traj, env_info, task_info):
    """
    Verify the agent added the drug to inventory correctly.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    score = 0
    feedback_parts = []
    
    # 1. Load result JSON from container
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

    # 2. Check Database Evidence
    drug_found = result.get('drug_found', False)
    drug_name = result.get('drug_name', '')
    drug_ndc = result.get('drug_ndc', '')
    
    # Convert string "NULL" or "0" to useful types
    def clean_val(v):
        if v in ["NULL", "None", ""]: return 0
        try: return float(v)
        except: return v

    drug_form = clean_val(result.get('drug_form', 0))
    drug_route = clean_val(result.get('drug_route', 0))
    drug_size = clean_val(result.get('drug_size', 0))
    
    initial_count = int(result.get('initial_count', 0))
    final_count = int(result.get('final_count', 0))

    # Criterion 1: Drug Record Exists (25 pts)
    if drug_found:
        score += 25
        feedback_parts.append("Drug record found")
    else:
        feedback_parts.append("No drug record found matching 'Metformin'")
        return {"passed": False, "score": 0, "feedback": "FAILED: No drug record created."}

    # Criterion 2: Name Accuracy (15 pts)
    # Expected: "Metformin HCl 500mg" or similar
    name_lower = drug_name.lower()
    if "metformin" in name_lower and ("500" in name_lower or "hcl" in name_lower):
        score += 15
        feedback_parts.append("Drug name correct")
    else:
        feedback_parts.append(f"Drug name '{drug_name}' imprecise")
        score += 5 # Partial credit for just existing

    # Criterion 3: NDC Accuracy (15 pts)
    # Expected: 00093-7214-01
    clean_ndc = drug_ndc.replace("-", "").replace(" ", "")
    if "000937214" in clean_ndc or "937214" in clean_ndc:
        score += 15
        feedback_parts.append("NDC correct")
    else:
        feedback_parts.append(f"NDC '{drug_ndc}' incorrect")

    # Criterion 4: Attributes (25 pts total)
    # Form != 0 (10 pts)
    if drug_form != 0:
        score += 10
        feedback_parts.append("Form set")
    
    # Route != 0 (10 pts)
    if drug_route != 0:
        score += 10
        feedback_parts.append("Route set")
        
    # Size approx 500 (5 pts)
    try:
        if 499 <= float(drug_size) <= 501:
            score += 5
            feedback_parts.append("Dosage size correct")
    except:
        pass

    # Criterion 5: Anti-gaming / Count check (10 pts)
    if final_count > initial_count:
        score += 10
        feedback_parts.append("Inventory count increased")
    else:
        feedback_parts.append("Inventory count did not increase (modified existing?)")

    # Criterion 6: VLM Trajectory Check (10 pts)
    # Verify the agent actually navigated the UI
    frames = sample_trajectory_frames(traj, n=4)
    if frames:
        vlm_prompt = """
        Analyze these screenshots of a user interacting with an EHR system.
        Did the user:
        1. Navigate to an Inventory or Drug Management screen?
        2. Fill out a form for a new drug?
        3. Save the record?
        
        Return JSON: {"ui_navigation_confirmed": true/false}
        """
        vlm_res = query_vlm(images=frames, prompt=vlm_prompt)
        if vlm_res.get('success') and vlm_res.get('parsed', {}).get('ui_navigation_confirmed'):
            score += 10
            feedback_parts.append("UI navigation confirmed")
        else:
            # Fallback if VLM unsure but DB is perfect
            if score >= 90: score += 10 
            feedback_parts.append("UI navigation unconfirmed")

    return {
        "passed": score >= 60,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }