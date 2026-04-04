#!/usr/bin/env python3
"""
Verifier for Chemical First Aid Protocol Compilation task.

Criteria:
1. File exists and was created during task.
2. File content includes sections for all 3 required chemicals.
3. Content includes exposure routes (Inhalation, Skin, Eye, Ingestion).
4. Content includes specific antidote/treatment keywords unique to these chemicals.
5. VLM trajectory verification confirms navigation to CAMEO Chemicals datasheets.
"""

import json
import os
import tempfile
import logging
from typing import Dict, Any, List

# VLM utilities (assumed available in environment)
from gym_anything.vlm import sample_trajectory_frames, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_chemical_first_aid_compilation(traj, env_info, task_info):
    """
    Verify the compiled first aid document using file analysis and VLM trajectory check.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    target_chemicals = metadata.get('target_chemicals', [])
    exposure_route_keywords = metadata.get('exposure_routes', ["inhalation", "skin", "eye", "ingestion"])
    
    score = 0
    max_score = 100
    feedback_parts = []
    
    # ------------------------------------------------------------------
    # 1. Load Task Result JSON
    # ------------------------------------------------------------------
    temp_result_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result_file.name)
        with open(temp_result_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load task result: {str(e)}"}
    finally:
        if os.path.exists(temp_result_file.name):
            os.unlink(temp_result_file.name)

    # ------------------------------------------------------------------
    # 2. Check File Existence & Timestamp (20 points)
    # ------------------------------------------------------------------
    output_exists = result.get('output_exists', False)
    file_created_during_task = result.get('file_created_during_task', False)
    output_size = result.get('output_size_bytes', 0)
    
    if not output_exists:
        return {"passed": False, "score": 0, "feedback": "Output file not found."}

    if file_created_during_task:
        score += 10
        feedback_parts.append("File created during task.")
    else:
        feedback_parts.append("File timestamp invalid (predates task).")

    if output_size >= 500:
        score += 10
        feedback_parts.append(f"File content sufficient ({output_size} bytes).")
    else:
        feedback_parts.append(f"File content too sparse ({output_size} bytes).")

    # ------------------------------------------------------------------
    # 3. Analyze File Content (50 points)
    # ------------------------------------------------------------------
    temp_content_file = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
    file_content = ""
    try:
        copy_from_env(result.get('output_file_path'), temp_content_file.name)
        with open(temp_content_file.name, 'r', errors='ignore') as f:
            file_content = f.read().lower()
    except Exception as e:
        feedback_parts.append(f"Failed to read output file content: {str(e)}")
    finally:
        if os.path.exists(temp_content_file.name):
            os.unlink(temp_content_file.name)

    if file_content:
        chemicals_found = 0
        treatments_found = 0
        routes_found_total = 0

        for chem in target_chemicals:
            # Check chemical presence (Title/Section)
            name_found = any(k in file_content for k in chem['keywords'])
            
            # Check treatment keywords (specific antidote/measure)
            treatment_found = any(k in file_content for k in chem['treatment_keywords'])
            
            # Check routes (roughly, doesn't map perfectly to sections but checks presence)
            # We want to see if the document discusses these routes overall or per section.
            # A simple heuristic: does the doc contain "inhalation", "skin", etc.?
            # Better: count how many routes appear in the doc (global check is safer than complex parsing)
            # We assign points if the doc looks comprehensive.
            
            if name_found:
                chemicals_found += 1
                if treatment_found:
                    treatments_found += 1
        
        # Check routes global presence
        routes_present = sum(1 for r in exposure_route_keywords if r in file_content)

        # Scoring Logic for Content
        # 3 Chemicals * 10 pts each = 30 pts
        score += (chemicals_found * 10)
        feedback_parts.append(f"Found {chemicals_found}/3 chemicals.")
        
        # Treatment specifics (proof of reading datasheet) * 5 pts each approx = 15 pts max
        # Cap at 10 pts for scoring balance
        if treatments_found >= 2:
            score += 10
            feedback_parts.append("Specific medical treatments identified.")
        elif treatments_found == 1:
            score += 5
            feedback_parts.append("Some medical treatments identified.")
        
        # Exposure routes = 10 pts
        if routes_present >= 3:
            score += 10
            feedback_parts.append("Exposure routes covered.")
        elif routes_present > 0:
            score += 5

    # ------------------------------------------------------------------
    # 4. VLM Trajectory Verification (30 points)
    # ------------------------------------------------------------------
    # We want to verify the agent actually navigated to CAMEO Chemicals
    frames = sample_trajectory_frames(traj, n=5)
    
    vlm_prompt = """
    Review these screenshots of an agent's computer screen.
    1. Did the agent visit the CAMEO Chemicals website (cameochemicals.noaa.gov)?
    2. Did the agent perform searches for chemicals (Hydrofluoric Acid, Phenol, or Sodium Cyanide)?
    3. Did the agent view chemical datasheet pages (pages showing physical properties or hazards)?
    
    Respond in JSON format:
    {
        "visited_cameo": true/false,
        "searched_chemicals": true/false,
        "viewed_datasheets": true/false,
        "confidence": "low/medium/high"
    }
    """
    
    try:
        vlm_result = query_vlm(images=frames, prompt=vlm_prompt)
        parsed = vlm_result.get('parsed', {})
        
        vlm_score = 0
        if parsed.get('visited_cameo'):
            vlm_score += 10
        if parsed.get('searched_chemicals'):
            vlm_score += 10
        if parsed.get('viewed_datasheets'):
            vlm_score += 10
            
        score += vlm_score
        feedback_parts.append(f"VLM Verification: {vlm_score}/30 points.")
        
    except Exception as e:
        logger.warning(f"VLM verification failed: {e}")
        # Fallback: if file is good, give partial credit for VLM to avoid failing solely on VLM error
        if score >= 50:
            score += 15
            feedback_parts.append("VLM check skipped (error), awarded partial credit based on file quality.")

    # ------------------------------------------------------------------
    # Final Result
    # ------------------------------------------------------------------
    # Pass threshold: 60 points AND at least 2 chemicals found
    passed = (score >= 60) and (chemicals_found >= 2)
    
    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " ".join(feedback_parts)
    }