#!/usr/bin/env python3
"""Verifier for Configure Course Sections task in Moodle."""

import json
import tempfile
import os
import logging
import re

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_configure_course_sections(traj, env_info, task_info):
    """
    Verify that PHYS101 sections are correctly renamed, described, and hidden.
    
    Scoring (100 points total):
    - 5 sections to configure.
    - Each section:
      - Correct Name keywords: 8 points
      - Correct Summary keywords: 5 points
    - Visibility:
      - Sections 1-4 Visible: 15 points (total for all)
      - Section 5 Hidden: 20 points
      
    Total breakdown:
    - Names: 5 * 8 = 40
    - Summaries: 5 * 5 = 25
    - Visibility 1-4: 15
    - Visibility 5: 20
    = 100
    
    Pass threshold: 60 points (Must get at least 3 sections correct and hide the 5th)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_config = metadata.get('expected_sections', [])

    try:
        temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/task_result.json", temp_result.name)
            with open(temp_result.name, 'r') as f:
                result = json.load(f)
        finally:
            os.unlink(temp_result.name)
            
        score = 0
        feedback_parts = []
        actual_sections = {s['section']: s for s in result.get('sections', [])}
        
        # 1. Check Names and Summaries (65 points total potential)
        sections_correct_count = 0
        
        for expected in expected_config:
            sec_id = expected['id']
            actual = actual_sections.get(sec_id)
            
            if not actual:
                feedback_parts.append(f"Section {sec_id}: Not found")
                continue
                
            # Check Name (8 pts)
            actual_name = actual.get('name', '')
            name_keywords = expected['name_keywords']
            # All keywords must be present (case insensitive)
            name_match = all(k.lower() in actual_name.lower() for k in name_keywords)
            
            if name_match:
                score += 8
                feedback_parts.append(f"Sec {sec_id} Name: OK")
            else:
                feedback_parts.append(f"Sec {sec_id} Name: Incorrect ('{actual_name}')")

            # Check Summary (5 pts)
            actual_summary = actual.get('summary', '')
            summary_keywords = expected['summary_keywords']
            summary_match = all(k.lower() in actual_summary.lower() for k in summary_keywords)
            
            if summary_match:
                score += 5
                feedback_parts.append(f"Sec {sec_id} Summary: OK")
            else:
                feedback_parts.append(f"Sec {sec_id} Summary: Incorrect")

            if name_match and summary_match:
                sections_correct_count += 1

        # 2. Check Visibility (35 points total)
        
        # Check Sections 1-4 Visibility (15 points)
        # All 1-4 must be visible (1)
        vis_1_4_ok = True
        for i in range(1, 5):
            sec = actual_sections.get(i)
            if not sec or sec.get('visible') != 1:
                vis_1_4_ok = False
                break
        
        if vis_1_4_ok:
            score += 15
            feedback_parts.append("Sec 1-4 Visibility: OK (Visible)")
        else:
            feedback_parts.append("Sec 1-4 Visibility: Incorrect (Some hidden)")
            
        # Check Section 5 Visibility (20 points)
        # Must be hidden (0)
        sec_5 = actual_sections.get(5)
        if sec_5 and sec_5.get('visible') == 0:
            score += 20
            feedback_parts.append("Sec 5 Visibility: OK (Hidden)")
        else:
            feedback_parts.append("Sec 5 Visibility: Incorrect (Visible)")

        passed = score >= 60 and sections_correct_count >= 3
        
        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }

    except Exception as e:
        logger.error(f"Verification error: {e}")
        return {"passed": False, "score": 0, "feedback": f"Error verifying: {str(e)}"}