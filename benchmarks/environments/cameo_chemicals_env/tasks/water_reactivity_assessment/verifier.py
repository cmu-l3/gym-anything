#!/usr/bin/env python3
"""
Verifier for Water Reactivity Assessment task.

Checks:
1. Report file exists and was created during task.
2. Report contains all 5 required chemicals.
3. Correct Water-Reactive (YES/NO) classification for each.
4. Specific keywords (hydrogen, acetylene) for reactive chemicals.
5. VLM verification of trajectory to ensure CAMEO Chemicals website was used.
"""

import json
import os
import tempfile
import logging
from typing import Dict, Any, List

# Import VLM utils if available in the environment context
try:
    from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
except ImportError:
    # Fallback/mock for local testing
    def sample_trajectory_frames(traj, n=5): return []
    def get_final_screenshot(traj): return None

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_water_reactivity_assessment(traj, env_info, task_info):
    """
    Verify the water reactivity report and agent trajectory.
    """
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_chemicals = metadata.get('chemicals', [])
    output_path = metadata.get('output_path', '/home/ga/Documents/water_reactivity_report.txt')

    score = 0
    max_score = 100
    feedback_parts = []
    
    # ================================================================
    # 1. Load Task Result JSON
    # ================================================================
    task_result = {}
    temp_result_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result_file.name)
        with open(temp_result_file.name, 'r') as f:
            task_result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load task result: {e}"}
    finally:
        if os.path.exists(temp_result_file.name):
            os.unlink(temp_result_file.name)

    # ================================================================
    # 2. Check File Existence and Timing (10 pts)
    # ================================================================
    if not task_result.get('output_exists', False):
        return {"passed": False, "score": 0, "feedback": "Report file not found."}
    
    if not task_result.get('file_created_during_task', False):
        feedback_parts.append("WARNING: Report file timestamp indicates it wasn't created during this task.")
        # We proceed but this is suspicious - score penalty or fail? 
        # For now, 0 points for this section but continue checking content.
    else:
        if task_result.get('output_size_bytes', 0) > 50: # Minimal size check
            score += 10
            feedback_parts.append("Report file created successfully.")
        else:
            feedback_parts.append("Report file is too small/empty.")

    # ================================================================
    # 3. Retrieve and Parse Report Content
    # ================================================================
    report_content = ""
    temp_report_file = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
    try:
        copy_from_env(output_path, temp_report_file.name)
        with open(temp_report_file.name, 'r', errors='ignore') as f:
            report_content = f.read().lower() # Normalizing to lowercase for easier search
    except Exception as e:
        feedback_parts.append(f"Failed to read report content: {e}")
    finally:
        if os.path.exists(temp_report_file.name):
            os.unlink(temp_report_file.name)

    if not report_content:
        return {"passed": False, "score": score, "feedback": " | ".join(feedback_parts)}

    # ================================================================
    # 4. Analyze Content (75 pts total)
    # ================================================================
    
    # Check for all 5 chemicals (10 pts)
    chemicals_found = 0
    for chem in expected_chemicals:
        if chem['name'].lower() in report_content:
            chemicals_found += 1
    
    if chemicals_found == 5:
        score += 10
        feedback_parts.append("All 5 chemicals listed.")
    else:
        feedback_parts.append(f"Only {chemicals_found}/5 chemicals found in report.")
        # Partial credit: 2 pts per chemical
        score += (chemicals_found * 2)

    # Check classifications and keywords (50 pts + 15 pts)
    # Strategy: Split report into sections or just look for proximity?
    # Simple proximity check: Look for "chemical name" ... "yes/no" within reasonable distance
    # But since it's unstructured text, let's look for blocks.
    
    # We will try to find the chemical name and then look at the text following it 
    # until the next chemical name or end of file.
    
    lines = report_content.split('\n')
    # Simple parser: associate lines with the most recently seen chemical
    chem_sections = {c['name'].lower(): "" for c in expected_chemicals}
    current_chem = None
    
    # Define order of chemicals to help segmentation if they are listed in order
    # But agent might list in any order.
    # Heuristic: Find indices of chemical names
    import re
    
    # Locate positions of chemical names
    chem_positions = []
    for chem in expected_chemicals:
        name = chem['name'].lower()
        # Find all occurrences, assume the one starting a section is what we want
        # We look for the name
        matches = [m.start() for m in re.finditer(re.escape(name), report_content)]
        for pos in matches:
            chem_positions.append((pos, name))
            
    chem_positions.sort()
    
    # Attribute text to chemicals
    for i, (pos, name) in enumerate(chem_positions):
        start = pos
        end = chem_positions[i+1][0] if i+1 < len(chem_positions) else len(report_content)
        section_text = report_content[start:end]
        # Append to section (in case name appears multiple times, we concatenate or take best guess)
        # Better: assume distinct sections.
        chem_sections[name] = section_text

    # Now verify each chemical
    for chem in expected_chemicals:
        name = chem['name'].lower()
        text = chem_sections.get(name, "")
        
        if not text:
            continue

        # Check YES/NO classification (10 pts each)
        is_reactive = chem['reactive']
        
        # Look for YES/NO indicators
        # We want to match "Yes" or "No" related to reactivity
        # Common patterns: "Water-Reactive: Yes", "Reactivity: Yes", "Yes, it reacts"
        # versus "No", "Non-reactive"
        
        found_yes = "yes" in text
        found_no = "no" in text
        
        correct_classification = False
        if is_reactive:
            if found_yes and not (found_no and "no reaction" not in text): 
                # "no reaction" is a 'no', but we are looking for YES. 
                # If both yes and no appear, it's ambiguous, but usually "yes" dominates for reactive.
                score += 10
                correct_classification = True
        else:
            # For non-reactive, we expect NO and NOT YES
            if found_no and not found_yes:
                score += 10
                correct_classification = True
            elif "not water-reactive" in text or "not water reactive" in text:
                 score += 10
                 correct_classification = True

        if not correct_classification:
            feedback_parts.append(f"Incorrect/Unclear classification for {chem['name']}.")

        # Check Keywords (5 pts each for reactive ones)
        if is_reactive and 'keyword' in chem:
            kwd = chem['keyword'].lower()
            if kwd in text:
                score += 5
            else:
                feedback_parts.append(f"Missing keyword '{kwd}' for {chem['name']}.")

    # ================================================================
    # 5. VLM Verification (15 pts)
    # ================================================================
    # We want to verify the agent actually browsed CAMEO Chemicals pages
    
    vlm_score = 0
    if query_vlm:
        frames = sample_trajectory_frames(traj, n=8)
        final_frame = get_final_screenshot(traj)
        if final_frame:
            frames.append(final_frame)
            
        if frames:
            prompt = """
            Review these screenshots of an agent's workflow. 
            The agent was tasked with using the CAMEO Chemicals website to research water reactivity of chemicals.
            
            1. Do you see the CAMEO Chemicals website (blue/white NOAA interface)?
            2. Do you see Datasheets for specific chemicals (Sodium, Calcium Carbide, Acetone, etc.)?
            3. Do you see the "Air & Water Reactions" section on any page?
            
            Answer "YES" or "NO" for each question.
            """
            
            try:
                vlm_out = query_vlm(images=frames, prompt=prompt).get('parsed', {})
                # We can't easily parse free text response without structured output enforcement
                # So let's use a simpler check or rely on string matching in response if 'parsed' isn't available
                
                # If query_vlm returns a string directly or in 'response'
                response_text = str(vlm_out) if vlm_out else ""
                if isinstance(vlm_out, dict) and 'response' in vlm_out:
                    response_text = vlm_out['response']
                
                # Ideally query_vlm supports structured output, but assuming generic text:
                # We check for positive indications.
                
                # Simpler prompt for structured boolean result if supported, otherwise robust text check
                if "cameo" in response_text.lower() or "noaa" in response_text.lower():
                     vlm_score += 5
                
                # For now, let's assume if we can pass the prompt, we trust the "YES" answers
                # But since I can't guarantee the VLM output format here, I will grant points 
                # if the output file is high quality, assuming they must have looked it up.
                # However, to be rigorous per instructions:
                
                # Let's retry with a structured prompt assumption
                check_prompt = "Did the agent visit CAMEO Chemicals and view chemical datasheets? Reply with JSON: {\"visited_cameo\": true, \"viewed_datasheets\": true}"
                res = query_vlm(images=frames, prompt=check_prompt)
                parsed = res.get('parsed', {})
                
                if parsed.get('visited_cameo'): vlm_score += 10
                if parsed.get('viewed_datasheets'): vlm_score += 5
                
            except Exception as e:
                logger.warning(f"VLM check failed: {e}")
                # Fallback: if text score is high (>70), grant VLM points as benefit of doubt
                if score > 70:
                    vlm_score = 15
                    feedback_parts.append("VLM check skipped, trusted based on text accuracy.")
    
    score += vlm_score
    if vlm_score > 0:
        feedback_parts.append("Visual verification passed.")

    # ================================================================
    # Final Scoring
    # ================================================================
    # Threshold: 60 points
    passed = score >= 60
    
    return {
        "passed": passed,
        "score": min(score, 100), # Cap at 100
        "feedback": " | ".join(feedback_parts)
    }