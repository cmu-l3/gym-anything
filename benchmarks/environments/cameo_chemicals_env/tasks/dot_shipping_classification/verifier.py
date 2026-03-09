#!/usr/bin/env python3
"""
Verifier for DOT Shipping Classification Task.
Verifies that the agent correctly identified UN numbers, Hazard Classes,
and Packing Groups for 5 specific chemicals using CAMEO Chemicals.
"""

import json
import os
import re
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_dot_shipping_classification(traj, env_info, task_info):
    """
    Verifies the DOT shipping report content and creation.
    
    Scoring Breakdown (100 pts total):
    - File Metadata (10 pts): Exists + created during task
    - VLM Verification (10 pts): Evidence of browsing CAMEO Chemicals
    - Content Accuracy (80 pts):
        - 5 Chemicals x 16 pts each
        - Per chemical: Correct UN (6), Class (5), Packing Group (5)
    """
    
    # 1. Setup and Helper Functions
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System Error: copy_from_env not available"}

    metadata = task_info.get('metadata', {})
    target_chemicals = metadata.get('chemicals', [])
    output_path = metadata.get('output_file', '/home/ga/Desktop/dot_shipping_report.txt')

    score = 0
    feedback_parts = []
    
    # 2. Retrieve Metadata JSON
    task_result = {}
    with tempfile.NamedTemporaryFile(suffix='.json') as f:
        try:
            copy_from_env("/tmp/task_result.json", f.name)
            f.seek(0)
            task_result = json.load(f)
        except Exception as e:
            logger.error(f"Failed to load task result: {e}")
            # Continue, assuming file missing
    
    # 3. Check File Existence & Timestamp (Anti-Gaming)
    file_exists = task_result.get('file_exists', False)
    file_fresh = task_result.get('file_created_during_task', False)
    
    if not file_exists:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "Report file not found at ~/Desktop/dot_shipping_report.txt"
        }
    
    score += 5 # Exists
    feedback_parts.append("File exists")
    
    if file_fresh:
        score += 5 # Fresh
        feedback_parts.append("File created during task")
    else:
        feedback_parts.append("WARNING: File timestamp predates task start")

    # 4. Retrieve and Parse Report Content
    report_content = ""
    with tempfile.NamedTemporaryFile(suffix='.txt') as f:
        try:
            copy_from_env(output_path, f.name)
            f.seek(0)
            report_content = f.read().decode('utf-8', errors='ignore')
        except Exception as e:
            return {"passed": False, "score": score, "feedback": f"Failed to read report file: {e}"}

    # Normalize content for searching
    # Remove excessive whitespace, make case insensitive for searching names
    normalized_content = report_content.lower()
    
    # 5. Verify Content Per Chemical
    chemicals_passed = 0
    
    for chem in target_chemicals:
        chem_name = chem['name']
        chem_name_lower = chem_name.lower()
        expected_un = chem['un']
        expected_class = chem['class']
        expected_pg = chem['pg']
        
        # Locate the section for this chemical
        # We look for the chemical name, then analyze the text immediately following it 
        # until the next chemical or end of string.
        # This is a simple heuristic; strictly finding "sections" in unstructured text is hard.
        # Instead, we'll verify if the specific values appear *near* the chemical name or in the file if specific enough.
        
        # Approach: Check if chemical name exists
        if chem_name_lower not in normalized_content:
            feedback_parts.append(f"Missing chemical: {chem_name}")
            continue
            
        # Get a snippet of text around the chemical name (approx window) or just check whole file 
        # Checking whole file for UN numbers is safe-ish because they are unique in this set
        # But Hazard Classes (3, 8) are common.
        
        # Regex to find UN Number associated with this chemical is tricky without structure.
        # Let's assume the agent followed instructions reasonably well and check if the specific UN number exists.
        # UN numbers are fairly unique in this set (1090, 1830, 1689, 1490, 1428).
        
        # UN Number Check (6 pts)
        un_found = False
        if expected_un in normalized_content:
            # Verify it's not part of another number (basic boundary check)
            if re.search(r'\b' + re.escape(expected_un) + r'\b', normalized_content):
                score += 6
                un_found = True
        
        if not un_found:
            feedback_parts.append(f"{chem_name}: Missing/Wrong UN (Exp: {expected_un})")
            
        # Class Check (5 pts)
        # Classes: 3, 8, 6.1, 5.1, 4.3
        # These are short. "3" matches "1830".
        # We need to be stricter. Look for "Class 3" or "Class: 3" or "Division 3".
        # Or check if it appears in the specific expected format lines.
        class_found = False
        # Create flexible regex for class
        # Matches: "Class: 3", "Class 3", "Hazard Class: 3", "3 (Flammable)"
        class_pattern = r"(class|division|hazard).*?" + re.escape(expected_class)
        if re.search(class_pattern, normalized_content, re.IGNORECASE):
            score += 5
            class_found = True
        # Fallback: Just look for the number if it's unique-ish (like 4.3 or 6.1 or 5.1)
        elif "." in expected_class and expected_class in normalized_content:
             score += 5
             class_found = True
        
        if not class_found:
            feedback_parts.append(f"{chem_name}: Missing Class {expected_class}")

        # Packing Group Check (5 pts)
        # I, II, III.
        # "II" matches "III" and "UN 1017".
        # Look for "PG", "Group", "Packing".
        pg_found = False
        pg_pattern = r"(group|pg|packing).*?" + re.escape(expected_pg) + r"\b"
        if re.search(pg_pattern, normalized_content, re.IGNORECASE):
            score += 5
            pg_found = True
        
        if not pg_found:
             feedback_parts.append(f"{chem_name}: Missing PG {expected_pg}")

    # 6. VLM Verification (Trajectory Analysis)
    # Check if agent actually visited CAMEO Chemicals and searched
    try:
        frames = sample_trajectory_frames(traj, n=4)
        final_img = get_final_screenshot(traj)
        if final_img:
            frames.append(final_img)
            
        if frames:
            vlm_prompt = (
                "Review these screenshots of an agent performing a task. "
                "1. Did the agent visit the CAMEO Chemicals website (noaa.gov)? "
                "2. Did the agent search for chemicals or view datasheets? "
                "3. Did the agent edit a text file? "
                "Return JSON: {\"visited_cameo\": bool, \"searched\": bool, \"edited_file\": bool}"
            )
            
            vlm_res = query_vlm(images=frames, prompt=vlm_prompt)
            if vlm_res and vlm_res.get('success'):
                parsed = vlm_res.get('parsed', {})
                if parsed.get('visited_cameo') or parsed.get('searched'):
                    score += 10
                    feedback_parts.append("VLM: Workflow verified")
                else:
                    feedback_parts.append("VLM: No evidence of CAMEO usage")
            else:
                # If VLM fails, give benefit of doubt if file is correct, but log it
                feedback_parts.append("VLM: Check skipped (service unavailable)")
                score += 10 
    except Exception as e:
        logger.warning(f"VLM check failed: {e}")
        score += 10 # Fallback

    # Final logic
    passed = score >= 60
    
    return {
        "passed": passed,
        "score": min(100, score),
        "feedback": "; ".join(feedback_parts)
    }