#!/usr/bin/env python3
"""
Verifier for create_isometric_piping_diagram task.
Checks for .eddx/.png creation, verifies XML content for labels, and uses VLM for visual validation.
"""

import json
import os
import tempfile
import zipfile
import logging
from typing import Dict, Any, List

# Setup logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Import VLM utils provided by the framework environment
try:
    from vlm_utils import query_vlm, get_final_screenshot, sample_trajectory_frames
except ImportError:
    # Fallback/Mock for local testing
    def query_vlm(**kwargs): return {"success": False, "error": "VLM not available"}
    def get_final_screenshot(traj): return None
    def sample_trajectory_frames(traj, n): return []


def verify_create_isometric_piping_diagram(traj: Dict[str, Any], env_info: Dict[str, Any], task_info: Dict[str, Any]) -> Dict[str, Any]:
    """
    Verifies the isometric piping diagram task.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_eddx_path = metadata.get('expected_eddx_path', '/home/ga/Diagrams/cooling_loop_iso.eddx')
    expected_png_path = metadata.get('expected_png_path', '/home/ga/Diagrams/cooling_loop_iso.png')
    required_strings = metadata.get('required_text_strings', ["T-100", "P-101", "HX-200"])
    
    score = 0
    feedback_parts = []
    
    # 1. Retrieve task_result.json
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    # 2. Verify File Creation (Anti-Gaming) (20 points)
    eddx_exists = result_data.get('eddx_exists', False)
    eddx_fresh = result_data.get('eddx_created_during_task', False)
    png_exists = result_data.get('png_exists', False)
    png_fresh = result_data.get('png_created_during_task', False)

    if eddx_exists and eddx_fresh:
        score += 10
        feedback_parts.append("EDDX file created successfully")
    elif eddx_exists:
        feedback_parts.append("EDDX file exists but timestamp is old (pre-existing?)")
    else:
        feedback_parts.append("EDDX file not found")

    if png_exists and png_fresh:
        score += 10
        feedback_parts.append("PNG export created successfully")
    elif png_exists:
        score += 5
        feedback_parts.append("PNG export exists but timestamp is old")
    else:
        feedback_parts.append("PNG export not found")

    # 3. Verify Content via XML Parsing (40 points)
    # .eddx files are ZIP archives containing XML data
    found_strings = []
    xml_content_valid = False
    
    if eddx_exists:
        temp_eddx = tempfile.NamedTemporaryFile(delete=False, suffix='.eddx')
        try:
            copy_from_env(expected_eddx_path, temp_eddx.name)
            
            # Check if valid zip
            if zipfile.is_zipfile(temp_eddx.name):
                with zipfile.ZipFile(temp_eddx.name, 'r') as zf:
                    # Iterate through all files in the zip to find text
                    all_text = ""
                    for filename in zf.namelist():
                        if filename.endswith('.xml') or filename.endswith('.json'):
                            try:
                                with zf.open(filename) as f:
                                    content = f.read().decode('utf-8', errors='ignore')
                                    all_text += content
                            except:
                                pass
                    
                    # Check for required strings
                    hit_count = 0
                    for req in required_strings:
                        if req in all_text:
                            found_strings.append(req)
                            hit_count += 1
                    
                    # Score based on found strings
                    # We expect 6 strings total. 
                    if hit_count >= len(required_strings):
                        score += 40
                        feedback_parts.append(f"All required labels found ({hit_count}/{len(required_strings)})")
                        xml_content_valid = True
                    elif hit_count >= 3:
                        partial_score = int(40 * (hit_count / len(required_strings)))
                        score += partial_score
                        feedback_parts.append(f"Some labels found ({hit_count}/{len(required_strings)})")
                    else:
                        feedback_parts.append(f"Few labels found ({hit_count}/{len(required_strings)})")
                        
            else:
                feedback_parts.append("EDDX file is not a valid ZIP archive")
        except Exception as e:
            feedback_parts.append(f"Error parsing EDDX file: {e}")
        finally:
            if os.path.exists(temp_eddx.name):
                os.unlink(temp_eddx.name)

    # 4. VLM Verification (40 points)
    # Check visual structure: 3 main components + lines
    
    # Get images: trajectory frames + final screenshot
    frames = sample_trajectory_frames(traj, n=4)
    final_img = get_final_screenshot(traj)
    
    if final_img:
        frames.append(final_img)
        
    if not frames:
        feedback_parts.append("No screenshots available for VLM verification")
    else:
        prompt = """
        You are verifying a "Create Isometric Piping Diagram" task in EdrawMax.
        The user was asked to create a diagram with:
        1. A Tank (vertical cylinder)
        2. A Pump
        3. A Heat Exchanger (shell and tube)
        4. Piping lines connecting them (Tank -> Pump -> Exchanger)
        5. Valves on the lines
        
        Look at the provided screenshots.
        Q1: Do you see a diagram with 3 distinct industrial/engineering components connected by lines?
        Q2: Can you identify text labels like T-100, P-101, or HX-200?
        Q3: Does the style look like an isometric or engineering diagram (not just a basic flowchart)?
        
        Return JSON:
        {
          "components_visible": boolean,
          "connections_visible": boolean,
          "labels_visible": boolean,
          "is_engineering_diagram": boolean,
          "confidence": int (0-100)
        }
        """
        
        vlm_res = query_vlm(images=frames, prompt=prompt)
        
        if vlm_res.get('success'):
            parsed = vlm_res.get('parsed', {})
            vlm_score = 0
            if parsed.get('components_visible'): vlm_score += 10
            if parsed.get('connections_visible'): vlm_score += 10
            if parsed.get('labels_visible'): vlm_score += 10
            if parsed.get('is_engineering_diagram'): vlm_score += 10
            
            score += vlm_score
            feedback_parts.append(f"VLM verification score: {vlm_score}/40")
        else:
            feedback_parts.append("VLM verification failed to run")

    # Final Pass Determination
    # Must have created files + have some valid content (XML or VLM)
    passed = (score >= 60) and eddx_fresh
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }