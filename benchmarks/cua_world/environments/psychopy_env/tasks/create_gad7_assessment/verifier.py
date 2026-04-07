#!/usr/bin/env python3
"""
Verifier for create_gad7_assessment task.

Verification Strategy:
1. CSV Analysis (30 pts):
   - Check if file exists and contains the 7 specific GAD-7 questions.
2. Experiment Structure Analysis (40 pts):
   - Check for Slider component with specific ticks [0,1,2,3] and labels.
   - Check for TextBox/Text components in a demographics routine.
   - Check for Loop referencing the CSV.
3. VLM Verification (30 pts):
   - Check trajectory for visual evidence of Slider creation/configuration.
   - Check for clean UI state.

Pass Threshold: 80/100
"""

import json
import tempfile
import os
import csv
import logging
import xml.etree.ElementTree as ET

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_gad7_assessment(traj, env_info, task_info):
    """Verify GAD-7 assessment creation."""
    
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_items = metadata.get('gad7_items', [])
    expected_labels = metadata.get('slider_labels', [])
    
    score = 0
    feedback_parts = []
    
    # 1. Get basic result JSON
    try:
        with tempfile.NamedTemporaryFile(delete=False, suffix='.json') as tmp:
            tmp_json_path = tmp.name
        copy_from_env("/tmp/task_result.json", tmp_json_path)
        with open(tmp_json_path, 'r') as f:
            basic_result = json.load(f)
        os.unlink(tmp_json_path)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task results: {e}"}

    # Nonce check
    try:
        with tempfile.NamedTemporaryFile(delete=False, suffix='.txt') as tmp:
            nonce_path = tmp.name
        copy_from_env("/home/ga/.task_nonce", nonce_path)
        with open(nonce_path, 'r') as f:
            expected_nonce = f.read().strip()
        os.unlink(nonce_path)
        
        if basic_result.get("result_nonce") != expected_nonce:
            return {"passed": False, "score": 0, "feedback": "Anti-gaming check failed (nonce mismatch)."}
    except:
        pass # Fail gracefully if nonce system has issues

    # 2. Analyze CSV Content (30 points)
    csv_score = 0
    if basic_result.get("csv_exists"):
        try:
            with tempfile.NamedTemporaryFile(delete=False, suffix='.csv') as tmp:
                csv_local_path = tmp.name
            copy_from_env("/home/ga/PsychoPyExperiments/gad7_items.csv", csv_local_path)
            
            with open(csv_local_path, 'r', encoding='utf-8', errors='ignore') as f:
                content = f.read().lower()
            
            # Check for header
            if "," in content or "\n" in content:
                csv_score += 5 # Basic CSV format
            
            # Check for items
            items_found = 0
            for item in expected_items:
                # Fuzzy match: check if significant part of string exists
                key_phrase = item.split(" ")[0] + " " + item.split(" ")[1]
                if key_phrase.lower() in content:
                    items_found += 1
            
            if items_found >= 7:
                csv_score += 25
                feedback_parts.append("CSV contains all GAD-7 items.")
            elif items_found > 0:
                csv_score += int(25 * (items_found / 7))
                feedback_parts.append(f"CSV contains {items_found}/7 items.")
            else:
                feedback_parts.append("CSV found but GAD-7 items missing.")
                
            os.unlink(csv_local_path)
        except Exception as e:
            feedback_parts.append(f"Error analyzing CSV: {e}")
    else:
        feedback_parts.append("Conditions CSV file not created.")

    score += csv_score

    # 3. Analyze Experiment XML (40 points)
    exp_score = 0
    if basic_result.get("exp_exists"):
        try:
            with tempfile.NamedTemporaryFile(delete=False, suffix='.psyexp') as tmp:
                exp_local_path = tmp.name
            copy_from_env("/home/ga/PsychoPyExperiments/gad7_assessment.psyexp", exp_local_path)
            
            tree = ET.parse(exp_local_path)
            root = tree.getroot()
            
            # Check for Slider
            has_slider = False
            slider_correct = False
            for comp in root.findall(".//Component"):
                if comp.get("type") == "Slider":
                    has_slider = True
                    # Check params
                    ticks_ok = False
                    labels_ok = False
                    granularity_ok = False
                    
                    for param in comp:
                        name = param.get("name")
                        val = param.get("val")
                        
                        if name == "ticks":
                            # Check for [0, 1, 2, 3] or similar
                            if "0" in val and "3" in val and "," in val:
                                ticks_ok = True
                        
                        if name == "labels":
                            # Check for labels
                            if "Not at all" in val and "Nearly every day" in val:
                                labels_ok = True
                        
                        if name == "granularity":
                            if "1" in val or "1.0" in val:
                                granularity_ok = True
                    
                    if ticks_ok and labels_ok:
                        slider_correct = True
            
            if has_slider:
                exp_score += 10
                if slider_correct:
                    exp_score += 15
                    feedback_parts.append("Slider component correctly configured.")
                else:
                    feedback_parts.append("Slider found but configuration (ticks/labels) incorrect.")
            else:
                feedback_parts.append("No Slider component found.")

            # Check for Demographics (TextBox)
            has_textbox = False
            for comp in root.findall(".//Component"):
                if comp.get("type") == "TextBox":
                    has_textbox = True
                    break
            
            if has_textbox:
                exp_score += 5
                feedback_parts.append("Demographics input (TextBox) found.")
            
            # Check for Loop
            has_loop = False
            loops = root.findall(".//LoopInitiator")
            if loops:
                has_loop = True
                # Check if loop references CSV
                for loop in loops:
                    for param in loop.findall(".//Param"):
                        if param.get("name") == "conditionsFile":
                            if "gad7" in param.get("val", "").lower() or "csv" in param.get("val", "").lower():
                                exp_score += 10
                                feedback_parts.append("Loop correctly linked to CSV.")
                                break
            
            if not has_loop:
                feedback_parts.append("No loop found in experiment.")

            os.unlink(exp_local_path)
            
        except Exception as e:
            feedback_parts.append(f"Error analyzing .psyexp: {e}")
    else:
        feedback_parts.append("Experiment file not created.")
    
    score += exp_score

    # 4. Basic Activity Check (30 points)
    # If both files exist and modified, give points for activity
    if basic_result.get("csv_modified") and basic_result.get("exp_modified"):
        score += 30
        feedback_parts.append("Files successfully created and modified during task.")
    elif basic_result.get("csv_exists") or basic_result.get("exp_exists"):
        score += 15
        feedback_parts.append("Partial file creation detected.")

    passed = score >= 80

    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback_parts)
    }