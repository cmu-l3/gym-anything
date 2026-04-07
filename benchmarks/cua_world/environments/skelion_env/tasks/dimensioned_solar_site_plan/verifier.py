#!/usr/bin/env python3
"""
Verifier for dimensioned_solar_site_plan task in SketchUp.
Uses VLM verification on both the trajectory (workflow validation) and 
the final exported PNG image (or final screenshot as a fallback).
"""

import os
import json
import tempfile
import logging
from gym_anything.vlm import get_final_screenshot, sample_trajectory_frames

logger = logging.getLogger(__name__)

def verify_dimensioned_solar_site_plan(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')

    if not copy_from_env or not query_vlm:
        return {"passed": False, "score": 0, "feedback": "Missing environment functions required for verification."}

    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    temp_img = tempfile.NamedTemporaryFile(delete=False, suffix='.png')
    
    try:
        # 1. READ EXPORTED METADATA
        try:
            copy_from_env("C:\\tmp\\task_result.json", temp_json.name)
            with open(temp_json.name, 'r') as f:
                result = json.load(f)
        except Exception as e:
            logger.error(f"Failed to read task result JSON: {e}")
            result = {}

        output_exists = result.get('output_exists', False)
        file_created = result.get('file_created_during_task', False)
        
        # 2. LOCATE IMAGE TO EVALUATE
        eval_image = None
        if output_exists:
            try:
                copy_from_env("C:\\Users\\Docker\\Documents\\site_plan.png", temp_img.name)
                if os.path.exists(temp_img.name) and os.path.getsize(temp_img.name) > 0:
                    eval_image = temp_img.name
            except Exception as e:
                logger.error(f"Failed to copy exported PNG: {e}")
        
        # Fallback to final screenshot if the export failed
        if not eval_image:
            eval_image = get_final_screenshot(traj)

        # 3. VERIFY TRAJECTORY (WORKFLOW)
        # Prevent gaming by ensuring they actually modeled things and used SketchUp
        frames = sample_trajectory_frames(traj, n=4)
        traj_prompt = """You are verifying an agent's workflow in SketchUp.
Look at these trajectory frames. Did the agent actively use SketchUp to model a building, place solar panels, and adjust dimensions or camera settings?
Answer in JSON:
{
    "actively_worked_in_sketchup": true/false
}"""
        
        traj_res = query_vlm(images=frames, prompt=traj_prompt)
        workflow_valid = False
        if traj_res and traj_res.get('parsed'):
            workflow_valid = traj_res['parsed'].get('actively_worked_in_sketchup', False)

        # 4. VERIFY FINAL IMAGE
        img_prompt = """You are an architectural drafter evaluating a site plan image.
Examine this image (which may be an exported site plan or a CAD screenshot) and evaluate it based on technical documentation standards.

Answer these questions:
1. Is it a top-down view? (looking straight down at the roof, not from the side or an angle)
2. Is it in Parallel Projection / Orthographic mode? (In Parallel Projection, a perfectly top-down view of a box will only show the top flat rectangle, with NO vertical side walls visible receding to a vanishing point. If you see depth/perspective distortion, it is NOT Parallel Projection).
3. Are solar panels visible on the roof?
4. Are there dimension lines with text showing the length of the building edges?

Respond in JSON format:
{
    "is_top_down": true/false,
    "is_parallel_projection": true/false,
    "solar_panels_visible": true/false,
    "dimensions_visible": true/false,
    "reasoning": "Explain your findings briefly"
}"""

        img_res = query_vlm(image=eval_image, prompt=img_prompt)

        # 5. SCORING
        score = 0
        feedback_parts = []
        
        # File requirements (15 pts)
        if output_exists and file_created:
            score += 15
            feedback_parts.append("File exported correctly (15/15)")
        elif output_exists:
            score += 5
            feedback_parts.append("File exists but was not created during task (5/15)")
        else:
            feedback_parts.append("File was NOT exported (0/15)")

        # Workflow validation (10 pts)
        if workflow_valid:
            score += 10
            feedback_parts.append("Active workflow verified (10/10)")
        else:
            feedback_parts.append("Active workflow NOT verified (0/10)")

        # Visual/Technical constraints (75 pts)
        is_parallel = False
        if img_res and img_res.get('parsed'):
            p = img_res['parsed']
            
            if p.get('is_top_down'):
                score += 10
                feedback_parts.append("Top-down view confirmed (10/10)")
            else:
                feedback_parts.append("Top-down view MISSING (0/10)")
                
            if p.get('is_parallel_projection'):
                is_parallel = True
                score += 15
                feedback_parts.append("Parallel projection confirmed (15/15)")
            else:
                feedback_parts.append("Parallel projection MISSING (0/15)")
                
            if p.get('solar_panels_visible'):
                score += 20
                feedback_parts.append("Solar panels visible (20/20)")
            else:
                feedback_parts.append("Solar panels MISSING (0/20)")
                
            if p.get('dimensions_visible'):
                score += 30
                feedback_parts.append("Dimensions visible (30/30)")
            else:
                feedback_parts.append("Dimensions MISSING (0/30)")
        else:
            feedback_parts.append("VLM failed to parse image.")

        # Key requirement for the task is the technical setup (Orthographic View)
        # Plus they must pass a minimum threshold
        passed = (score >= 70) and is_parallel

        if not is_parallel and score >= 70:
            feedback_parts.append("FAILED: Parallel projection is a strict requirement for a technical site plan.")

        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }

    finally:
        # Cleanup temp files
        if os.path.exists(temp_json.name):
            try: os.unlink(temp_json.name)
            except: pass
        if os.path.exists(temp_img.name):
            try: os.unlink(temp_img.name)
            except: pass