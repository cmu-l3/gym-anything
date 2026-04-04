#!/usr/bin/env python3
"""
Verifier for Spill Neutralization Agent Lookup Task.

Verifies that the agent:
1. Created the requested CSV file.
2. Included the correct neutralizing agents for specific chemicals.
3. Correctly identified when NO neutralizer is recommended (Toluene).
4. actually performed the research (via VLM trajectory analysis).
"""

import json
import csv
import os
import tempfile
import logging
import io
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_spill_neutralization_agent_lookup(traj, env_info, task_info):
    """
    Verify the spill neutralization lookup task.
    """
    # 1. Setup and Environment Check
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System Error: Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_path = metadata.get('output_path', '/home/ga/Documents/neutralizer_inventory.csv')
    chemical_targets = metadata.get('chemicals', [])
    
    score = 0
    feedback_parts = []
    
    # 2. Retrieve Result JSON and CSV File
    temp_result_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    temp_csv_file = tempfile.NamedTemporaryFile(delete=False, suffix='.csv')
    
    try:
        # Load metadata
        copy_from_env("/tmp/task_result.json", temp_result_json.name)
        with open(temp_result_json.name, 'r') as f:
            result_meta = json.load(f)
            
        # Check basic file existence/creation
        if not result_meta.get('output_exists', False):
            return {"passed": False, "score": 0, "feedback": "Failed: Output CSV file was not created."}
            
        if not result_meta.get('file_created_during_task', False):
             # If file exists but wasn't created now, it's likely a stale file (anti-gaming)
            return {"passed": False, "score": 0, "feedback": "Failed: Output file timestamp indicates it was not created during this task."}
        
        score += 10 # File created successfully
        
        # Download the CSV content
        copy_from_env(expected_path, temp_csv_file.name)
        
        # 3. Analyze CSV Content
        with open(temp_csv_file.name, 'r', encoding='utf-8', errors='replace') as f:
            content = f.read().strip()
            
        # Parse CSV
        reader = csv.reader(io.StringIO(content))
        rows = list(reader)
        
        if not rows:
            return {"passed": False, "score": score, "feedback": "Failed: CSV file is empty."}
            
        # Verify Header (Loose check)
        header = [h.lower() for h in rows[0]]
        if "chemical" in str(header) and "neutralizer" in str(header):
            score += 5
            feedback_parts.append("Header format correct.")
        else:
            feedback_parts.append("Warning: CSV header format incorrect.")

        # Analyze Rows
        # Map chemical names in CSV to our targets using basic string matching
        chemicals_found = 0
        correct_neutralizers = 0
        
        for target in chemical_targets:
            target_name = target['name'].lower()
            target_keywords = target['keywords']
            target_forbidden = target.get('forbidden', [])
            
            # Find matching row
            found_row = None
            for row in rows:
                if len(row) < 2: continue
                if target_name.split(',')[0] in row[0].lower(): # Match "Nitric Acid" in "Nitric Acid, Red Fuming"
                    found_row = row
                    break
            
            if found_row:
                chemicals_found += 1
                agent_answer = found_row[1].lower()
                
                # Check for keywords
                hit = False
                
                # Special case for Toluene (Negative Control)
                if "toluene" in target_name:
                    # Should be None/Empty/Absorb, NOT lime/acid
                    has_forbidden = any(bad in agent_answer for bad in target_forbidden)
                    if not has_forbidden and (len(agent_answer) < 5 or "none" in agent_answer or "absorb" in agent_answer or "n/a" in agent_answer):
                        hit = True
                else:
                    # Standard Positive Control
                    hit = any(kw in agent_answer for kw in target_keywords)
                
                if hit:
                    correct_neutralizers += 1
                    feedback_parts.append(f"Correct neutralizer for {target['name'].split(',')[0]}.")
                else:
                    feedback_parts.append(f"Incorrect neutralizer for {target['name'].split(',')[0]} (Got: '{found_row[1]}').")
            else:
                feedback_parts.append(f"Missing row for {target['name'].split(',')[0]}.")

        # Scoring Logic for Content
        # 5 chemicals * 12 points each = 60 points max for content
        score += (correct_neutralizers * 12)
        
        # 4. VLM Verification (Trajectory Analysis)
        # Did the agent actually visit CAMEO chemicals and look at datasheets?
        frames = sample_trajectory_frames(traj, n=4)
        
        # We assume if they got the data right, they likely visited, but VLM confirms workflow
        # Only verify workflow if score is > 0 (efficiency)
        vlm_score = 0
        if score > 10:
            prompt = (
                "Review these screenshots of an agent performing a task.\n"
                "The agent should be using the CAMEO Chemicals website.\n"
                "1. Is the CAMEO Chemicals website visible in at least one frame?\n"
                "2. Does the agent view specific Chemical Datasheets (e.g., seeing 'Nitric Acid', 'Toluene', etc. as headers)?\n"
                "3. Does the agent scroll down to sections like 'Response Recommendations' or 'Non-Fire Response'?\n\n"
                "Return JSON: {\"cameo_visible\": bool, \"datasheet_viewed\": bool, \"response_section_visible\": bool}"
            )
            
            vlm_response = query_vlm(images=frames, prompt=prompt)
            parsed = vlm_response.get('parsed', {})
            
            if parsed.get('cameo_visible'): vlm_score += 10
            if parsed.get('datasheet_viewed'): vlm_score += 10
            if parsed.get('response_section_visible'): vlm_score += 5
            
            feedback_parts.append(f"VLM verification: {vlm_score}/25 points.")
        
        score += vlm_score

    except Exception as e:
        logger.error(f"Verification error: {e}")
        return {"passed": False, "score": score, "feedback": f"Verification failed with error: {str(e)}"}
    finally:
        # Cleanup
        if os.path.exists(temp_result_json.name): os.unlink(temp_result_json.name)
        if os.path.exists(temp_csv_file.name): os.unlink(temp_csv_file.name)

    # Final Pass Determination
    # Need at least 70 points AND the file must exist
    passed = (score >= 70) and result_meta.get('output_exists', False)
    
    return {
        "passed": passed,
        "score": min(100, score), # Cap at 100
        "feedback": " | ".join(feedback_parts)
    }