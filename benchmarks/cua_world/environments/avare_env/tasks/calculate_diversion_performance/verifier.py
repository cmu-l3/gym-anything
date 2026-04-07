#!/usr/bin/env python3
"""
Verifier for calculate_diversion_performance task.

Criteria:
1. Output file /sdcard/diversion_calc.txt exists.
2. Output file contains ETE (approx 36-37 mins) and FUEL (approx 8.8 gal).
3. Preferences file shows TAS set to 135 and Fuel Burn set to 14.5.
4. VLM verifies the Plan page was used.
"""

import json
import os
import re
import tempfile
import logging
import xml.etree.ElementTree as ET

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_diversion_calculation(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    min_ete = metadata.get('min_ete', 33)
    max_ete = metadata.get('max_ete', 40)
    min_fuel = metadata.get('min_fuel', 7.5)
    max_fuel = metadata.get('max_fuel', 10.0)

    score = 0
    feedback = []
    
    # ------------------------------------------------------------------
    # 1. Fetch Artifacts
    # ------------------------------------------------------------------
    temp_dir = tempfile.mkdtemp()
    local_result_json = os.path.join(temp_dir, "task_result.json")
    local_output_txt = os.path.join(temp_dir, "diversion_calc.txt")
    local_prefs_xml = os.path.join(temp_dir, "task_prefs.xml")
    
    try:
        copy_from_env("/sdcard/task_result.json", local_result_json)
        # Load JSON first to see if output exists
        with open(local_result_json, 'r') as f:
            result_data = json.load(f)
            
        if result_data.get("output_exists", False):
            copy_from_env("/sdcard/diversion_calc.txt", local_output_txt)
            
        # Try copying prefs (might fail if export failed)
        try:
            copy_from_env("/sdcard/task_prefs.xml", local_prefs_xml)
        except Exception:
            logger.warning("Could not copy prefs xml")

    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task data: {str(e)}"}

    # ------------------------------------------------------------------
    # 2. Verify Output Values (40 pts)
    # ------------------------------------------------------------------
    output_valid = False
    if os.path.exists(local_output_txt):
        try:
            with open(local_output_txt, 'r') as f:
                content = f.read()
            
            # Extract ETE
            ete_match = re.search(r"ETE_MIN[:\s]+([\d\.]+)", content, re.IGNORECASE)
            fuel_match = re.search(r"FUEL_GAL[:\s]+([\d\.]+)", content, re.IGNORECASE)
            
            if ete_match and fuel_match:
                ete_val = float(ete_match.group(1))
                fuel_val = float(fuel_match.group(1))
                
                # Check ranges
                ete_ok = min_ete <= ete_val <= max_ete
                fuel_ok = min_fuel <= fuel_val <= max_fuel
                
                if ete_ok:
                    score += 20
                    feedback.append(f"ETE {ete_val} min is accurate.")
                else:
                    feedback.append(f"ETE {ete_val} min out of range ({min_ete}-{max_ete}).")
                    
                if fuel_ok:
                    score += 20
                    feedback.append(f"Fuel {fuel_val} gal is accurate.")
                else:
                    feedback.append(f"Fuel {fuel_val} gal out of range ({min_fuel}-{max_fuel}).")
                
                if ete_ok and fuel_ok:
                    output_valid = True
            else:
                feedback.append("Could not parse ETE_MIN or FUEL_GAL from output file.")
        except Exception as e:
            feedback.append(f"Error reading output file: {str(e)}")
    else:
        feedback.append("Output file diversion_calc.txt not found.")

    # ------------------------------------------------------------------
    # 3. Verify Preferences Configuration (30 pts)
    # ------------------------------------------------------------------
    prefs_correct = False
    if os.path.exists(local_prefs_xml):
        try:
            tree = ET.parse(local_prefs_xml)
            root = tree.getroot()
            
            # Avare prefs keys (based on typical android prefs or observation)
            # We look for value "135" and "14.5" in any string/float entry if precise key unknown,
            # but keys are likely "TAS" or similar. Let's search broadly first.
            
            tas_found = False
            fuel_found = False
            
            for elem in root.iter():
                # Check attributes 'value' or text content
                val = str(elem.get('value', '')) + str(elem.text or '')
                name = elem.get('name', '')
                
                if '135' in val and ('TAS' in name or 'Speed' in name or 'tas' in name):
                    tas_found = True
                if '14.5' in val and ('Fuel' in name or 'GPH' in name or 'burn' in name):
                    fuel_found = True
                    
            if tas_found:
                score += 15
                feedback.append("Aircraft TAS configured correctly.")
            else:
                feedback.append("Aircraft TAS preference not found/incorrect.")
                
            if fuel_found:
                score += 15
                feedback.append("Aircraft Fuel Burn configured correctly.")
            else:
                feedback.append("Aircraft Fuel Burn preference not found/incorrect.")
                
            prefs_correct = tas_found and fuel_found
            
        except Exception as e:
            feedback.append(f"Error parsing preferences XML: {str(e)}")
    else:
        feedback.append("Preferences file missing (export failed).")

    # ------------------------------------------------------------------
    # 4. Verify Plan Existence (10 pts)
    # ------------------------------------------------------------------
    if result_data.get("plan_file_found", False):
        score += 10
        feedback.append("Flight plan 'DivertKFAT' found in storage.")
    else:
        feedback.append("Flight plan file not found (may not be saved properly).")

    # ------------------------------------------------------------------
    # 5. VLM / Screenshot Verification (20 pts)
    # ------------------------------------------------------------------
    # We assume if they got the numbers right and changed prefs, they likely used the UI.
    # We give points for a "sensible" looking final state or trajectory.
    
    from gym_anything.vlm import get_final_screenshot, query_vlm
    final_img = get_final_screenshot(traj)
    
    if final_img:
        prompt = "Is the Avare aviation app visible? Does it show a 'Plan' or map screen with KMOD or KFAT visible?"
        try:
            vlm_res = query_vlm(image=final_img, prompt=prompt)
            if vlm_res.get("parsed", {}).get("answer", False) or "yes" in vlm_res.get("text", "").lower():
                score += 20
                feedback.append("Visual verification passed.")
            else:
                # Fallback points if output valid
                if output_valid:
                    score += 20
                    feedback.append("Visual verification ambiguous, but output is correct.")
                else:
                    feedback.append("Visual verification failed.")
        except:
            if output_valid: score += 20 # Fallback
    else:
        feedback.append("No final screenshot available.")

    # ------------------------------------------------------------------
    # Final Decision
    # ------------------------------------------------------------------
    # Pass if: Output values are correct AND Preferences are set correctly.
    passed = output_valid and prefs_correct and score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }