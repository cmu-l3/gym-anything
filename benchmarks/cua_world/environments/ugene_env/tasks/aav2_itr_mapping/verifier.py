#!/usr/bin/env python3
"""
Verifier for AAV2 ITR Mapping Task.
Evaluates exported files and verifies trajectory using VLM to ensure anti-gaming.
"""

import json
import os
import tempfile
import logging
import re

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_aav2_itr_mapping(traj, env_info, task_info):
    """
    Score the task execution based on GenBank file validity, proper coordinates 
    derived from structural search, report contents, and visual trajectory confirmation.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Verifier error: copy_from_env unavailable"}

    score = 0
    feedback_parts = []
    
    # 1. Parse JSON results
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/aav2_itr_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read exported results: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    # 2. Extract Result Variables
    gb_exists = result.get('gb_exists', False)
    gb_valid = result.get('gb_valid', False)
    gb_created = result.get('gb_created_during_task', False)
    annotations_present = result.get('annotations_present', False)
    coords = result.get('annotation_coords', [])
    report_exists = result.get('report_exists', False)
    report_created = result.get('report_created_during_task', False)
    report_content = result.get('report_content', "").lower()

    # 3. Evaluate GenBank output & Coordinates (Primary Signals)
    if gb_exists and gb_created:
        score += 10
        feedback_parts.append("GenBank file created successfully.")
        
        if gb_valid:
            score += 10
            feedback_parts.append("GenBank format is valid.")
            
            if annotations_present and len(coords) > 0:
                score += 15
                feedback_parts.append("Custom annotations found in GenBank file.")
                
                # Verify exact/approximate ITR coordinates
                found_5prime = False
                found_3prime = False
                
                for c in coords:
                    try:
                        start, end = map(int, c.split('..'))
                        # 5' ITR is typically 1..145
                        if start <= 10 and end <= 250:
                            found_5prime = True
                        # 3' ITR is typically ~4535..4679
                        if start >= 4400 and end >= 4600:
                            found_3prime = True
                    except ValueError:
                        continue
                
                if found_5prime and found_3prime:
                    score += 35
                    feedback_parts.append("Both 5' and 3' ITR coordinates correctly annotated (structural distance > 4kb valid).")
                elif found_5prime or found_3prime:
                    score += 15
                    feedback_parts.append("Only one ITR region successfully annotated. Missed structural pair.")
                else:
                    feedback_parts.append("Annotations present but do not match expected extreme 5'/3' terminal locations.")
            else:
                feedback_parts.append("No new annotations detected in the GenBank file.")
        else:
            feedback_parts.append("GenBank file format invalid.")
    else:
        feedback_parts.append("Annotated GenBank file missing or not modified during task.")

    # 4. Evaluate the Report File
    if report_exists and report_created:
        score += 10
        feedback_parts.append("Report file created.")
        
        # Check Length
        if "4679" in report_content:
            score += 10
            feedback_parts.append("Accurate genome length (4679) documented.")
        
        # Check Biological Keywords
        biology_keywords = ['packag', 'replicat', 'hairpin', 'primer', 'cis']
        if any(kw in report_content for kw in biology_keywords):
            score += 10
            feedback_parts.append("Valid biological function described in report.")
        else:
            feedback_parts.append("Biological function missing or unrecognized in report.")
    else:
        feedback_parts.append("Report file missing.")

    # 5. VLM Trajectory Verification (Anti-Gaming check)
    # Even if files are perfectly formatted, ensure the UI was interacted with appropriately
    vlm_feedback = ""
    try:
        from gym_anything.vlm import sample_trajectory_frames, query_vlm
        frames = sample_trajectory_frames(traj, n=4)
        if frames:
            prompt = """
            You are verifying a bioinformatics agent's workflow in UGENE.
            The task was to find 'Inverted repeats' with length 30 and identity 100%.
            Look at these trajectory frames and determine:
            1. Did the agent open a 'Find repeats' or 'Search' dialog?
            2. Is there visual evidence of sequence analysis happening in the UI?
            
            Respond strictly in JSON format:
            {"used_search_tools": true/false, "reasoning": "Brief explanation"}
            """
            vlm_response = query_vlm(images=frames, prompt=prompt)
            if vlm_response and vlm_response.get("success"):
                parsed = vlm_response.get("parsed", {})
                if not parsed.get("used_search_tools", False):
                    # Heavy penalty if VLM detects they just faked the output files
                    score = max(0, score - 50)
                    vlm_feedback = "VLM Alert: No visual evidence of 'Find repeats' tool usage in trajectory."
                else:
                    vlm_feedback = "VLM verified appropriate tool usage."
    except Exception as e:
        logger.warning(f"VLM verification skipped/failed: {e}")
        vlm_feedback = "VLM check skipped."

    if vlm_feedback:
        feedback_parts.append(vlm_feedback)

    passed = (score >= 70 and (found_5prime or found_3prime) and gb_created)

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }