#!/usr/bin/env python3
"""
Verifier for create_hvac_plan task.

Criteria:
1. Files exist and were created during task (Anti-gaming).
2. .eddx file is a valid zip and contains specific text labels ("AHU-1", "Supply Air").
3. VLM Verification: Visual confirmation of HVAC plan layout.
"""

import json
import os
import tempfile
import zipfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_hvac_plan(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System Error: copy_from_env missing"}

    # Load result from export script
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load task result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    score = 0
    feedback = []
    
    # --- Criterion 1: Files Existence & Freshness (30 pts) ---
    eddx = result_data.get("eddx_file", {})
    png = result_data.get("png_file", {})
    
    files_ok = False
    if eddx.get("exists") and eddx.get("created_during_task"):
        score += 15
        feedback.append("Project file (.eddx) created.")
        if eddx.get("size", 0) > 2000: # Check for non-empty file
            files_ok = True
    else:
        feedback.append("Project file missing or not new.")

    if png.get("exists") and png.get("created_during_task"):
        score += 15
        feedback.append("Exported image (.png) created.")
    else:
        feedback.append("Exported image missing or not new.")

    # --- Criterion 2: Content Verification (Programmatic) (40 pts) ---
    # Parse the .eddx (which is a zip) to check for text labels
    content_score = 0
    required_labels = task_info.get("metadata", {}).get("required_labels", ["AHU-1", "Supply Air", "Return Air"])
    found_labels = []
    
    if files_ok:
        temp_eddx = tempfile.NamedTemporaryFile(delete=False, suffix='.eddx')
        try:
            copy_from_env(eddx["path"], temp_eddx.name)
            
            with zipfile.ZipFile(temp_eddx.name, 'r') as zf:
                # EdrawMax stores diagram data in xml files, often under 'pages/' or root
                xml_content = ""
                for filename in zf.namelist():
                    if filename.endswith(".xml"):
                        try:
                            xml_content += zf.read(filename).decode('utf-8', errors='ignore')
                        except:
                            pass
                
                # Check for required labels
                for label in required_labels:
                    if label in xml_content:
                        found_labels.append(label)
                        content_score += 10 # Approx 10 pts per label found
                    else:
                        # Fallback: check case-insensitive or partial
                        if label.lower() in xml_content.lower():
                            found_labels.append(label + " (partial)")
                            content_score += 5

                # Check for keywords indicating HVAC library usage (Bonus)
                keywords = task_info.get("metadata", {}).get("required_keywords", [])
                keyword_hits = [k for k in keywords if k in xml_content]
                if len(keyword_hits) >= 2:
                    content_score += 10
                    feedback.append(f"HVAC symbols detected: {', '.join(keyword_hits[:3])}...")

        except zipfile.BadZipFile:
            feedback.append("Error: .eddx file is not a valid zip archive.")
        except Exception as e:
            feedback.append(f"Error checking file content: {str(e)}")
        finally:
            if os.path.exists(temp_eddx.name):
                os.unlink(temp_eddx.name)
    
    score += min(40, content_score)
    if found_labels:
        feedback.append(f"Found text labels: {', '.join(found_labels)}")
    else:
        feedback.append("No required text labels found in diagram.")

    # --- Criterion 3: VLM Verification (30 pts) ---
    # Use trajectory to confirm they actually used the tool interface
    vlm_score = 0
    frames = sample_trajectory_frames(traj, n=4)
    final_screen = get_final_screenshot(traj)
    
    if frames:
        prompt = """
        You are verifying a user action in EdrawMax. 
        The user was asked to create an HVAC plan for a server room.
        
        Look for these steps in the image sequence:
        1. User selecting "Building Plan" or "HVAC" category/templates.
        2. User dragging HVAC symbols (ducts, fans, terminals) onto the canvas.
        3. A diagram resembling a room with ducts connecting a unit to vents.
        
        Does the trajectory show the creation of an HVAC-style diagram?
        """
        
        try:
            # We append the final screen to the trajectory frames for context
            all_images = frames + ([final_screen] if final_screen else [])
            vlm_res = query_vlm(images=all_images, prompt=prompt)
            
            if vlm_res.get("success"):
                # Simple boolean parsing based on VLM response text usually requires structure
                # But for this template we assume the VLM output implies success if positive
                analysis = vlm_res.get("response", "").lower()
                if "yes" in analysis or "shows" in analysis or "created" in analysis:
                    vlm_score = 30
                    feedback.append("VLM confirms HVAC diagram creation workflow.")
                else:
                    feedback.append("VLM could not clearly verify HVAC workflow.")
                    # Partial credit if file checks passed significantly
                    if files_ok: 
                        vlm_score = 10 
            else:
                feedback.append("VLM query failed.")
        except Exception as e:
            logger.error(f"VLM verification error: {e}")
            
    score += vlm_score

    # Final Calculation
    passed = (score >= 70) and files_ok
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }