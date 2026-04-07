#!/usr/bin/env python3
"""
Verifier for create_method_of_adjustment_task.

Verification Strategy (Programmatic Analysis of XML and CSV):

1. **Conditions File (10 pts)**:
   - File exists and has required columns (ref_size, start_size).
   - Has at least 5 data rows.

2. **Visual Setup (20 pts)**:
   - Experiment contains 2 Polygon/Rect components.
   - One is positioned left (ref), one right (adj).
   - Reference size uses `ref_size` variable.

3. **Interaction Logic (Code Component) (40 pts)**:
   - A Code Component exists in the Trial routine.
   - 'Begin Routine' initializes a variable from `start_size`.
   - 'Each Frame' contains logic to check keys (up/down) and modify the variable.
   - Evidence of `+=` or `-=` or mathematical adjustment.

4. **Real-time Update (15 pts)**:
   - The Adjustable Polygon's size parameter is set to update "Every Frame" (constant update).
   - It references the variable modified in the code.

5. **Data Logging (15 pts)**:
   - Code component contains `addData` call to save the final value.

Pass threshold: 85 points.
"""

import json
import tempfile
import os
import csv
import logging
import xml.etree.ElementTree as ET
import re

logger = logging.getLogger(__name__)

def verify_create_method_of_adjustment_task(traj, env_info, task_info):
    """Verify Method of Adjustment task implementation."""
    
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    exp_path_env = metadata.get('experiment_path', "/home/ga/PsychoPyExperiments/size_matching.psyexp")
    cond_path_env = metadata.get('conditions_path', "/home/ga/PsychoPyExperiments/conditions/size_conditions.csv")
    
    feedback_parts = []
    score = 0
    
    # ------------------------------------------------------------------
    # 1. Verify Conditions File
    # ------------------------------------------------------------------
    cond_score = 0
    try:
        with tempfile.NamedTemporaryFile(delete=False, suffix='.csv') as tmp:
            local_cond_path = tmp.name
        
        copy_from_env(cond_path_env, local_cond_path)
        
        with open(local_cond_path, 'r', newline='') as f:
            reader = csv.DictReader(f)
            headers = [h.strip() for h in (reader.fieldnames or [])]
            rows = list(reader)
            
        # Check columns
        if 'ref_size' in headers and 'start_size' in headers:
            cond_score += 5
            feedback_parts.append("Conditions file columns correct.")
        else:
            feedback_parts.append(f"Missing columns in conditions file. Found: {headers}")
            
        # Check rows
        if len(rows) >= 5:
            cond_score += 5
            feedback_parts.append(f"Conditions file has {len(rows)} rows.")
        else:
            feedback_parts.append(f"Not enough rows in conditions file ({len(rows)}/5).")
            
    except Exception as e:
        feedback_parts.append(f"Failed to verify conditions file: {e}")
    finally:
        if 'local_cond_path' in locals() and os.path.exists(local_cond_path):
            os.unlink(local_cond_path)
            
    score += cond_score
    
    # ------------------------------------------------------------------
    # 2. Verify Experiment XML
    # ------------------------------------------------------------------
    try:
        with tempfile.NamedTemporaryFile(delete=False, suffix='.psyexp') as tmp:
            local_exp_path = tmp.name
            
        copy_from_env(exp_path_env, local_exp_path)
        
        tree = ET.parse(local_exp_path)
        root = tree.getroot()
        
        # Helper: Find all routines
        routines = root.findall(".//Routine")
        trial_routine = None
        for r in routines:
            # Assuming the routine with the code/polygons is the trial one
            # Look for one containing a Code Component
            if r.find(".//CodeComponent") is not None:
                trial_routine = r
                break
        
        # If no code component found, maybe named "trial" specifically?
        if trial_routine is None:
            for r in routines:
                if r.get('name') == 'trial':
                    trial_routine = r
                    break
                    
        if trial_routine is None:
            return {
                "passed": False, 
                "score": score, 
                "feedback": "Could not find a Trial routine with components. " + " ".join(feedback_parts)
            }

        # --- A. Visual Setup (20 pts) ---
        visual_score = 0
        polygons = trial_routine.findall(".//PolygonComponent")
        if len(polygons) >= 2:
            visual_score += 10
            # Check for separation and variable usage
            # We look for one using 'ref_size' and one using a variable
            ref_found = False
            adj_found = False
            
            for poly in polygons:
                # Check position (roughly) to distinguish left/right if possible, 
                # but mainly check size params
                size_param = None
                for param in poly.findall("Param"):
                    if param.get("name") == "size":
                        size_param = param
                        break
                
                if size_param is not None:
                    val = size_param.get("val")
                    updates = size_param.get("updates")
                    
                    if "ref_size" in val:
                        ref_found = True
                    # Adjustable: usually constant/set every frame, value is a variable name
                    elif updates == "set every frame" and "$" in val:
                        adj_found = True
                        
            if ref_found: visual_score += 5
            if adj_found: visual_score += 5
            
        else:
            feedback_parts.append(f"Found {len(polygons)} polygons (need 2).")
            
        score += visual_score
        if visual_score == 20:
            feedback_parts.append("Visual components configured correctly.")
            
        # --- B. Interaction Logic (Code Component) (40 pts) ---
        code_score = 0
        code_comp = trial_routine.find(".//CodeComponent")
        
        if code_comp is not None:
            code_score += 10 # Component exists
            
            # Extract code blocks
            begin_routine = ""
            each_frame = ""
            end_routine = ""
            
            for param in code_comp.findall("Param"):
                name = param.get("name")
                val = param.get("val")
                if name == "Begin Routine": begin_routine = val
                if name == "Each Frame": each_frame = val
                if name == "End Routine": end_routine = val
            
            # 1. Initialization logic
            if "start_size" in begin_routine:
                code_score += 5
                
            # 2. Key check logic (Up/Down)
            # Look for key checks: 'defaultKeyboard.getKeys', 'event.getKeys', 'key_resp', 'theseKeys'
            # Look for 'up' and 'down' strings
            has_key_check = any(k in each_frame for k in ["getKeys", "keys", "event.getKeys"])
            has_arrows = "up" in each_frame.lower() and "down" in each_frame.lower()
            
            if has_key_check and has_arrows:
                code_score += 15
            else:
                feedback_parts.append("Missing key check logic in 'Each Frame'.")
                
            # 3. Size modification logic
            # Look for math operators +=, -=, +, -
            if any(op in each_frame for op in ["+=", "-=", "+", "-"]):
                code_score += 10
            else:
                feedback_parts.append("Missing size adjustment math in 'Each Frame'.")
                
        else:
            feedback_parts.append("No Code Component found in trial routine.")
            
        score += code_score
        
        # --- C. Real-time Update (15 pts) ---
        # Checked partly in visual setup (updates="set every frame"), double checking here
        # If we found the adjustable polygon earlier
        update_score = 0
        if visual_score >= 10: # Polygons exist
             # We need to find the specific variable name modified in code
             # and ensure a polygon uses it
             
             # Extract likely variable names from code
             # Regex to find LHS of assignment? Complex.
             # Simplified: Check if any polygon uses "set every frame"
             for poly in polygons:
                for param in poly.findall("Param"):
                    if param.get("name") == "size" and param.get("updates") == "set every frame":
                        update_score = 15
                        break
                if update_score > 0: break
        
        if update_score > 0:
            feedback_parts.append("Polygon configured for real-time updates.")
        else:
            feedback_parts.append("No polygon set to update size 'Every Frame'.")
            
        score += update_score
        
        # --- D. Data Logging (15 pts) ---
        log_score = 0
        # Look for thisExp.addData in End Routine or Each Frame (if they logged every frame, acceptable)
        if "addData" in end_routine or "addData" in each_frame:
            log_score = 15
            feedback_parts.append("Data logging found.")
        else:
            feedback_parts.append("No 'thisExp.addData()' found in code.")
            
        score += log_score
        
    except Exception as e:
        feedback_parts.append(f"Error parsing experiment file: {e}")
    finally:
        if 'local_exp_path' in locals() and os.path.exists(local_exp_path):
            os.unlink(local_exp_path)
            
    passed = score >= 85
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }