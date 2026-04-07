#!/usr/bin/env python3
"""
Verifier for Investor Relations Deck Assembly task.

This evaluates whether the agent properly navigated a Word document, an Excel sheet,
and a PowerPoint presentation inside ONLYOFFICE to create a new summary presentation.

Verification Checks:
1. Output file exists and was created/modified during the task (Anti-gaming check)
2. Presentation has at least 4 slides
3. Operational metrics ("113.2" & "18.3") found together on a slide
4. Financial metrics ("3397" & "4374" or their variations) found together on a slide
5. Strategic priorities found together on a slide
6. VLM Trajectory check: Visual confirmation that ONLYOFFICE UI was used to complete the task
"""

import json
import os
import sys
import tempfile
import logging

# Ensure gym_anything modules are available for trajectory analysis
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../'))
try:
    from vlm_utils import query_vlm, sample_trajectory_frames, get_final_screenshot
except ImportError:
    # Handle gracefully if running outside standard framework layout
    query_vlm = None
    sample_trajectory_frames = None
    get_final_screenshot = None

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_deck_assembly(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    metrics = metadata.get('metrics', {})

    # ================================================================
    # Read task result JSON from container
    # ================================================================
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read exported result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # Check basic file constraints
    output_exists = result.get("output_exists", False)
    file_created_during_task = result.get("file_created_during_task", False)
    
    if not output_exists:
        return {"passed": False, "score": 0, "feedback": "Failure: Target presentation file 'Airbnb_Q3_Summary.pptx' was not found."}
    
    if file_created_during_task:
        score += 15
        feedback_parts.append("File created/modified during task (+15)")
    else:
        return {"passed": False, "score": 0, "feedback": "Failure: File exists but was not created/modified during the task window (anti-gaming block)."}

    # Extract parsed slide data
    slide_data = result.get("slide_data", {})
    if "error" in slide_data:
        feedback_parts.append(f"Warning: PPTX parser error: {slide_data['error']}")
        
    slides = slide_data.get("slides", [])
    num_slides = len(slides)
    
    # 2. Slide structure
    if num_slides >= 4:
        score += 15
        feedback_parts.append(f"Presentation contains {num_slides} slides (+15)")
    else:
        score += int(15 * (num_slides / 4.0))
        feedback_parts.append(f"Presentation contains {num_slides}/4 slides (+{int(15 * (num_slides / 4.0))})")

    # Lowercase all slides for easier text matching
    slides_lower = [s.lower() for s in slides]
    
    # 3. Operational Metrics
    ops_found = False
    ops_str1 = metrics.get('nights', "113.2")
    ops_str2 = metrics.get('gbv', "18.3")
    for slide in slides_lower:
        if ops_str1 in slide and ops_str2 in slide:
            ops_found = True
            break
            
    if ops_found:
        score += 20
        feedback_parts.append("Operational metrics found (+20)")
    else:
        feedback_parts.append("Missing operational metrics (113.2 and 18.3)")

    # 4. Financial Results
    fin_found = False
    rev_variants = [v.lower() for v in metrics.get('revenue', ["3397"])]
    net_variants = [v.lower() for v in metrics.get('net_income', ["4374"])]
    for slide in slides_lower:
        has_rev = any(v in slide for v in rev_variants)
        has_net = any(v in slide for v in net_variants)
        if has_rev and has_net:
            fin_found = True
            break
            
    if fin_found:
        score += 20
        feedback_parts.append("Financial metrics found (+20)")
    else:
        feedback_parts.append("Missing or incomplete financial metrics (3397 and 4374)")

    # 5. Strategic Focus
    strat_found = False
    strat1 = metrics.get('strategy_1', "hosting mainstream").lower()
    strat2 = metrics.get('strategy_2', "perfect the core").lower()
    strat3 = metrics.get('strategy_3', "expand beyond").lower()
    for slide in slides_lower:
        if strat1 in slide and strat2 in slide and strat3 in slide:
            strat_found = True
            break
            
    if strat_found:
        score += 20
        feedback_parts.append("Strategic priorities found (+20)")
    else:
        feedback_parts.append("Missing or incomplete strategic priorities")

    # ================================================================
    # VLM Trajectory Verification (Anti-Gaming & UI confirmation)
    # ================================================================
    vlm_score = 0
    if query_vlm and sample_trajectory_frames and get_final_screenshot:
        try:
            frames = sample_trajectory_frames(traj, n=4)
            final_frame = get_final_screenshot(traj)
            
            # Filter None frames
            valid_images = [img for img in frames + [final_frame] if img is not None]
            
            if valid_images:
                prompt = (
                    "You are verifying if a computer agent successfully created a presentation using ONLYOFFICE. "
                    "Look at these trajectory screenshots. "
                    "1. Is the ONLYOFFICE Desktop Editors application visible? "
                    "2. Did the agent actively use the graphical interface to interact with a presentation, word document, or spreadsheet? "
                    "Respond with a JSON object: {\"gui_used\": true/false, \"reasoning\": \"brief explanation\"}"
                )
                
                vlm_result = query_vlm(images=valid_images, prompt=prompt)
                
                if vlm_result and "parsed" in vlm_result:
                    if vlm_result["parsed"].get("gui_used", False):
                        vlm_score = 10
                        feedback_parts.append("VLM confirms GUI usage (+10)")
                    else:
                        feedback_parts.append("VLM did not detect ONLYOFFICE GUI usage")
                else:
                    feedback_parts.append("VLM verification failed to parse")
            else:
                feedback_parts.append("No valid trajectory images for VLM")
        except Exception as e:
            logger.warning(f"VLM verification exception: {e}")
            feedback_parts.append("VLM exception occurred")
    else:
        # If VLM is not available in the testing environment, award the points to prevent penalizing
        logger.warning("VLM utilities not available, bypassing VLM check.")
        vlm_score = 10
        feedback_parts.append("VLM bypassed (+10)")

    score += vlm_score

    # Determine Pass / Fail
    # Threshold is 70 points out of 100, must have created the file and retrieved at least some data
    key_criteria_met = output_exists and file_created_during_task
    passed = (score >= 70) and key_criteria_met

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }