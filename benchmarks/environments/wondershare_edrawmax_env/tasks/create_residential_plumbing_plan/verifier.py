#!/usr/bin/env python3
"""
Verifier for create_residential_plumbing_plan task.

Verification Strategy:
1. File Existence: Check if .eddx and .png files exist and were created during the task.
2. Content Analysis (Programmatic): Unzip .eddx and check XML for required text labels (Toilet, Shower, Hot, Cold, etc.).
3. Visual Verification (VLM): Analyze the PNG export or final screenshot to verify:
   - Correct fixtures present.
   - Red (Hot) and Blue (Cold) lines used.
   - Logic: Toilet has no hot water connection.
"""

import json
import os
import tempfile
import zipfile
import logging
from gym_anything.vlm import query_vlm, get_final_screenshot, sample_trajectory_frames

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_residential_plumbing_plan(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_eddx = metadata.get('expected_eddx_path', '/home/ga/Diagrams/bathroom_plumbing_plan.eddx')
    expected_png = metadata.get('expected_png_path', '/home/ga/Diagrams/bathroom_plumbing_plan.png')
    
    score = 0
    feedback_parts = []
    
    # 1. Get result JSON
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {e}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)
            
    # 2. Verify EDDX File (Existence & Content) - 40 Points
    eddx_exists = result_data.get("eddx_exists", False)
    eddx_fresh = result_data.get("eddx_created_during_task", False)
    
    if eddx_exists and eddx_fresh:
        score += 10
        feedback_parts.append("EDDX project file created.")
        
        # Check content inside EDDX (it's a zip)
        temp_eddx = tempfile.NamedTemporaryFile(delete=False, suffix='.eddx')
        try:
            copy_from_env(expected_eddx, temp_eddx.name)
            
            # Check size
            if os.path.getsize(temp_eddx.name) > 2000: # Empty is very small
                score += 10
                feedback_parts.append("EDDX file has valid size.")
            
            # Check XML content for labels
            with zipfile.ZipFile(temp_eddx.name, 'r') as zf:
                all_xml_text = ""
                for name in zf.namelist():
                    if name.endswith('.xml'):
                        try:
                            all_xml_text += zf.read(name).decode('utf-8', errors='ignore')
                        except:
                            pass
                
                # Check for required keywords
                required_terms = ["Toilet", "Shower", "Sink", "Heater", "Hot", "Cold", "Drain"]
                found_terms = [term for term in required_terms if term.lower() in all_xml_text.lower()]
                
                term_score = min(20, len(found_terms) * 3) # Max 20 pts for terms
                score += term_score
                feedback_parts.append(f"Found {len(found_terms)}/{len(required_terms)} required labels in file.")
                
        except zipfile.BadZipFile:
            feedback_parts.append("EDDX file is corrupted or not a valid zip.")
        except Exception as e:
            feedback_parts.append(f"Error analyzing EDDX content: {e}")
        finally:
            if os.path.exists(temp_eddx.name):
                os.unlink(temp_eddx.name)
    else:
        feedback_parts.append("EDDX project file missing or not created during task.")

    # 3. Verify PNG Export - 10 Points
    png_exists = result_data.get("png_exists", False)
    png_fresh = result_data.get("png_created_during_task", False)
    
    if png_exists and png_fresh:
        score += 10
        feedback_parts.append("PNG export created.")
    else:
        feedback_parts.append("PNG export missing.")

    # 4. VLM Verification (Visual Logic) - 50 Points
    # We prefer the exported PNG for clarity, but fall back to the final screenshot if needed.
    image_to_check = None
    
    if png_exists:
        # Use the exported PNG
        temp_png = tempfile.NamedTemporaryFile(delete=False, suffix='.png')
        try:
            copy_from_env(expected_png, temp_png.name)
            image_to_check = temp_png.name
        except:
            pass
            
    if not image_to_check:
        # Fallback to final screenshot from trajectory
        image_to_check = get_final_screenshot(traj)

    if image_to_check:
        prompt = """
        You are a plumbing inspector checking a diagram.
        The diagram should show a bathroom plan with:
        1. Fixtures: Toilet, Shower, Sink, Water Heater.
        2. Piping: 
           - Blue lines (Cold Water)
           - Red lines (Hot Water)
           - Black or Green lines (Drain/Waste)
        
        CRITICAL CHECKS:
        A. Does the TOILET have ONLY a Blue (Cold) line? (Toilets must NOT have Red/Hot lines).
        B. Do the SINK and SHOWER have BOTH Red (Hot) and Blue (Cold) lines?
        C. Are the lines clearly color-coded?
        
        Respond in JSON:
        {
            "fixtures_visible": true/false,
            "piping_colors_visible": true/false,
            "toilet_piping_correct": true/false,
            "sink_shower_piping_correct": true/false,
            "reasoning": "Explain what lines connect to what."
        }
        """
        
        try:
            vlm_res = query_vlm(prompt=prompt, image=image_to_check)
            if vlm_res.get("success"):
                parsed = vlm_res.get("parsed", {})
                
                if parsed.get("fixtures_visible"):
                    score += 10
                    feedback_parts.append("VLM: Fixtures visible.")
                
                if parsed.get("piping_colors_visible"):
                    score += 10
                    feedback_parts.append("VLM: Piping is color-coded.")
                    
                if parsed.get("toilet_piping_correct"): # Key logic check
                    score += 15
                    feedback_parts.append("VLM: Toilet piping correct (Cold only).")
                else:
                    feedback_parts.append("VLM: Toilet piping incorrect (might have hot water connected?).")
                    
                if parsed.get("sink_shower_piping_correct"):
                    score += 15
                    feedback_parts.append("VLM: Sink/Shower piping correct (Hot & Cold).")
                
                feedback_parts.append(f"VLM reasoning: {parsed.get('reasoning')}")
            else:
                feedback_parts.append("VLM verification failed to run.")
        except Exception as e:
            feedback_parts.append(f"VLM error: {e}")
            
        # Clean up temp png if we used one
        if png_exists and image_to_check and os.path.exists(image_to_check) and image_to_check != get_final_screenshot(traj):
            os.unlink(image_to_check)
    else:
        feedback_parts.append("No image available for VLM verification.")

    passed = score >= 70
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }