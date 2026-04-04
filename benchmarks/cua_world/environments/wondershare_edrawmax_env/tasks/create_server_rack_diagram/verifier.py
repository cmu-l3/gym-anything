#!/usr/bin/env python3
"""
Verifier for create_server_rack_diagram task.

Verifies:
1. Files (.eddx and .png) exist and were created during the task.
2. .eddx file contains required XML content (labels and shape types).
3. VLM verification of the visual layout (stacking order).
"""

import json
import os
import tempfile
import zipfile
import logging
from gym_anything.vlm import query_vlm, get_final_screenshot, sample_trajectory_frames

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_server_rack_diagram(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    required_strings = metadata.get('required_strings', [])
    
    score = 0
    max_score = 100
    feedback_parts = []
    
    # =========================================================
    # 1. Retrieve Result JSON
    # =========================================================
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    task_start = result_data.get('task_start', 0)
    
    # =========================================================
    # 2. File Existence & Timestamp Checks (30 points)
    # =========================================================
    eddx_exists = result_data.get('eddx_exists', False)
    png_exists = result_data.get('png_exists', False)
    eddx_mtime = result_data.get('eddx_mtime', 0)
    png_mtime = result_data.get('png_mtime', 0)
    
    files_ok = False
    if eddx_exists and png_exists:
        if eddx_mtime > task_start and png_mtime > task_start:
            score += 30
            files_ok = True
            feedback_parts.append("Both output files created successfully.")
        else:
            score += 10
            feedback_parts.append("Files exist but timestamps look suspicious (pre-existing?).")
    elif eddx_exists:
        score += 15
        feedback_parts.append("Source .eddx file created, but PNG export missing.")
    elif png_exists:
        score += 10
        feedback_parts.append("PNG export created, but source .eddx file missing.")
    else:
        feedback_parts.append("No output files found.")

    # =========================================================
    # 3. Content Verification (Parsing .eddx XML) (30 points)
    # =========================================================
    content_score = 0
    found_strings = []
    
    if eddx_exists and files_ok:
        temp_eddx = tempfile.NamedTemporaryFile(delete=False, suffix='.eddx')
        try:
            copy_from_env("/home/ga/Documents/rack_elevation.eddx", temp_eddx.name)
            
            # EdrawMax .eddx is a ZIP containing XML files
            if zipfile.is_zipfile(temp_eddx.name):
                with zipfile.ZipFile(temp_eddx.name, 'r') as zf:
                    # Search all XML content in the archive
                    all_text = ""
                    for name in zf.namelist():
                        if name.endswith('.xml'):
                            try:
                                all_text += zf.read(name).decode('utf-8', errors='ignore')
                            except:
                                pass
                    
                    # Check for required labels
                    found_count = 0
                    for s in required_strings:
                        if s in all_text:
                            found_strings.append(s)
                            found_count += 1
                        # Also check case-insensitive partials if exact fail
                        elif s.lower() in all_text.lower():
                             found_strings.append(s + " (partial)")
                             found_count += 0.5
                    
                    # Check for shape types (heuristic based on standard libraries)
                    shape_keywords = ["Rack", "UPS", "Server", "Switch", "Patch"]
                    shapes_found = [k for k in shape_keywords if k in all_text]
                    
                    if len(shapes_found) >= 3:
                        content_score += 10
                        feedback_parts.append(f"Found rack equipment shapes: {', '.join(shapes_found)}")
                    
                    # Score based on found labels
                    if found_count >= len(required_strings):
                        content_score += 20
                        feedback_parts.append("All required text labels found in file.")
                    elif found_count > 0:
                        partial = int(20 * (found_count / len(required_strings)))
                        content_score += partial
                        feedback_parts.append(f"Found {found_count}/{len(required_strings)} text labels.")
                    else:
                        feedback_parts.append("No required text labels found in diagram.")
                        
            else:
                feedback_parts.append("Output file is not a valid EdrawMax archive.")
                
        except Exception as e:
            feedback_parts.append(f"Failed to analyze EDDX content: {e}")
        finally:
            if os.path.exists(temp_eddx.name):
                os.unlink(temp_eddx.name)
    
    score += content_score

    # =========================================================
    # 4. VLM Verification (40 points)
    # =========================================================
    vlm_score = 0
    
    # Use trajectory frames to see the process + final result
    # We want to verify the visual arrangement: Rack frame, UPS at bottom, Servers, Network at top
    frames = sample_trajectory_frames(traj, n=3)
    final_ss = get_final_screenshot(traj)
    
    if final_ss:
        images_to_check = frames + [final_ss]
        
        prompt = """
        You are verifying a "Server Rack Diagram" task in EdrawMax.
        
        Expected Outcome:
        1. A tall rectangular "Rack" or "Cabinet" frame.
        2. Equipment stacked vertically INSIDE the rack.
        3. Specific arrangement:
           - Bottom: UPS (usually a larger block)
           - Middle: Servers (rectangular units)
           - Top: Patch Panel / Switch (thinner strips)
        4. Labels visible: "APC", "Server", "Switch".
        
        Analyze the images and answer:
        - Is there a Rack Diagram visible?
        - Is equipment placed INSIDE the rack frame (not floating outside)?
        - Is the stacking order roughly correct (UPS at bottom)?
        - Do you see text labels?
        """
        
        vlm_result = query_vlm(prompt=prompt, images=images_to_check)
        
        if vlm_result and vlm_result.get('success'):
            analysis = vlm_result.get('response', '').lower()
            
            # Simple heuristic scoring based on VLM text response keywords
            # (In a real scenario, structured JSON output from VLM is better)
            
            # Check for positive indicators
            if "rack" in analysis and "inside" in analysis:
                vlm_score += 20
                feedback_parts.append("VLM confirms equipment inside rack.")
            
            if "ups" in analysis and ("bottom" in analysis or "lower" in analysis):
                vlm_score += 10
                feedback_parts.append("VLM confirms UPS at bottom.")
                
            if "server" in analysis or "switch" in analysis:
                vlm_score += 10
                feedback_parts.append("VLM sees expected equipment types.")
                
            feedback_parts.append(f"VLM Analysis: {vlm_result.get('response')[:100]}...")
        else:
            # Fallback if VLM fails but files are good
            if files_ok and content_score > 20:
                vlm_score += 20
                feedback_parts.append("VLM unavailable, trusting file analysis.")
    
    score += vlm_score

    # Final pass determination
    # Must have files and reasonable content/VLM confirmation
    passed = (score >= 70) and files_ok

    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback_parts)
    }