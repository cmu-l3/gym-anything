#!/usr/bin/env python3
"""
Verifier for Time-Series Quality Assessment task.
"""

import os
import json
import re
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_quality_assessment(traj, env_info, task_info):
    """
    Verify the agent's QC report against the calculated ground truth.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    score = 0
    feedback_parts = []
    
    # 1. Load result JSON
    result = {}
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    # 2. Load Ground Truth JSON
    gt = {}
    temp_gt = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/qc_ground_truth.json", temp_gt.name)
        with open(temp_gt.name, 'r') as f:
            gt = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load ground truth: {e}"}
    finally:
        if os.path.exists(temp_gt.name):
            os.unlink(temp_gt.name)

    worst_bg_gt = set(gt.get('worst_bg', []))
    worst_fwhm_gt = set(gt.get('worst_fwhm', []))

    # Evaluate Criterion 1: Report Exists & Format Correct (20 pts)
    report_exists = result.get('report_exists', False)
    content = result.get('report_content', '')
    
    if report_exists:
        score += 10
        feedback_parts.append("Report file created")
        
        # Check basic format
        if "Worst Seeing Frames" in content and "Highest Sky Background Frames" in content:
            score += 10
            feedback_parts.append("Report format correct")
        else:
            feedback_parts.append("Report format missing required section headers")
    else:
        feedback_parts.append("Report file NOT found")
        return {
            "passed": False,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }

    # Evaluate Criterion 2: AIJ Measurements Used (20 pts)
    measurements_created = result.get('measurements_created', False)
    if measurements_created:
        score += 20
        feedback_parts.append("AIJ measurement outputs detected")
    else:
        feedback_parts.append("No AIJ measurement outputs detected (did the agent run Multi-Aperture?)")

    # Evaluate Criterion 3 & 4: Accuracy of reported frames
    # Parse the reported frames using Regex
    # Matches "1. <number>", "2. <number>", "3. <number>" under respective sections
    
    def extract_frames(section_name, text):
        frames = []
        section_idx = text.find(section_name)
        if section_idx != -1:
            # Look at the text immediately following the section header
            sub_text = text[section_idx:]
            # Find the next section header or end of string to bound the search
            next_section_match = re.search(r'\n[A-Za-z ]+Frames:', sub_text[len(section_name):])
            end_idx = len(section_name) + next_section_match.start() if next_section_match else len(sub_text)
            target_text = sub_text[:end_idx]
            
            # Extract bullet points 1., 2., 3.
            matches = re.findall(r'[123]\.\s*(\d+)', target_text)
            frames = [int(m) for m in matches]
        return frames

    reported_fwhm = extract_frames("Worst Seeing Frames:", content)
    reported_bg = extract_frames("Highest Sky Background Frames:", content)

    # 3. FWHM / Seeing Accuracy (30 pts)
    fwhm_hits = 0
    for frame in reported_fwhm:
        if frame in worst_fwhm_gt:
            fwhm_hits += 1
            
    if len(reported_fwhm) > 0:
        fwhm_score = min(30, fwhm_hits * 15)  # 15 pts per correct frame, max 30
        score += fwhm_score
        feedback_parts.append(f"Seeing accuracy: {fwhm_hits}/{len(reported_fwhm)} frames correct ({fwhm_score} pts)")
    else:
        feedback_parts.append("No Seeing frames extracted from report")

    # 4. Sky Background Accuracy (30 pts)
    bg_hits = 0
    for frame in reported_bg:
        if frame in worst_bg_gt:
            bg_hits += 1
            
    if len(reported_bg) > 0:
        bg_score = min(30, bg_hits * 15)  # 15 pts per correct frame, max 30
        score += bg_score
        feedback_parts.append(f"Sky BG accuracy: {bg_hits}/{len(reported_bg)} frames correct ({bg_score} pts)")
    else:
        feedback_parts.append("No Sky BG frames extracted from report")

    # Final evaluation
    passed = score >= 70 and report_exists
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }