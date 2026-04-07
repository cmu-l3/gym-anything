#!/usr/bin/env python3
"""
Verifier for the annotate_contour_elevations task in TopoCal.

Verification Strategy:
1. JSON Export Checks:
   - DXF file exists and was created/modified during the task.
   - TCL project file exists and was created/modified during the task.
2. DXF Entity Parsing:
   - Uses `ezdxf` (installed dynamically if missing) to parse the output DXF.
   - Searches for TEXT or MTEXT entities.
   - Verifies the presence of at least 5 numeric text labels.
   - Verifies the labels fall within realistic elevation bounds (1600-2400m).
   - Verifies rotation variance (anti-gaming: manual text is typically all 0.0 degrees).
3. VLM Trajectory Verification:
   - Uses trajectory frames + final screenshot to visually confirm the user
     interacted with the automated labeling tool and that labels appear on contours.
"""

import json
import os
import tempfile
import logging
import sys
import subprocess

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Ensure ezdxf is installed for DXF parsing
try:
    import ezdxf
except ImportError:
    logger.info("ezdxf not found. Installing...")
    subprocess.check_call([sys.executable, "-m", "pip", "install", "-q", "ezdxf"])
    import ezdxf

def verify_annotate_contour_elevations(traj, env_info, task_info):
    """
    Main verification logic.
    """
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env not available."}

    metadata = task_info.get('metadata', {})
    expected_dxf_path = metadata.get('expected_dxf_path', "C:\\Users\\Docker\\Documents\\TopoCal\\labeled_contours.dxf")
    min_labels = metadata.get('min_labels', 5)
    min_elev = metadata.get('min_elevation', 1600)
    max_elev = metadata.get('max_elevation', 2400)

    score = 0
    feedback_parts = []
    
    # 1. Retrieve the exported JSON result
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("C:\\temp\\task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task result: {e}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    dxf_info = result.get('dxf_file', {})
    tcl_info = result.get('tcl_file', {})

    # Evaluate File Existence & Timestamps (Anti-gaming)
    files_created = True
    
    if dxf_info.get('exists') and dxf_info.get('created_during_task'):
        score += 15
        feedback_parts.append("DXF file successfully created/modified.")
    else:
        files_created = False
        feedback_parts.append("DXF file missing or pre-dates task.")

    if tcl_info.get('exists') and tcl_info.get('created_during_task'):
        score += 10
        feedback_parts.append("Project TCL file successfully saved.")
    else:
        feedback_parts.append("Project TCL file missing or pre-dates task.")

    # 2. Parse the DXF file for verification
    dxf_parsed_successfully = False
    valid_elevations = []
    text_rotations = set()
    
    if dxf_info.get('exists') and dxf_info.get('size_bytes', 0) > 0:
        temp_dxf = tempfile.NamedTemporaryFile(delete=False, suffix='.dxf')
        try:
            # Note: DXF paths need escaping or exact matching for copy_from_env
            copy_from_env(expected_dxf_path, temp_dxf.name)
            
            # Use ezdxf to read the modelspace
            doc = ezdxf.readfile(temp_dxf.name)
            msp = doc.modelspace()
            
            # Query text entities
            text_entities = msp.query('TEXT MTEXT')
            
            for entity in text_entities:
                text_val = entity.dxf.text.strip()
                try:
                    # Check if it's numeric and matches elevation bounds
                    val = float(text_val)
                    if min_elev <= val <= max_elev:
                        valid_elevations.append(val)
                        # Capture rotation to ensure automated tool was used
                        rot = getattr(entity.dxf, 'rotation', 0.0)
                        text_rotations.add(round(rot, 2))
                except ValueError:
                    pass
            dxf_parsed_successfully = True
        except Exception as e:
            feedback_parts.append(f"Error parsing DXF: {e}")
        finally:
            if os.path.exists(temp_dxf.name):
                os.unlink(temp_dxf.name)

    # Score DXF content
    if dxf_parsed_successfully:
        num_labels = len(valid_elevations)
        if num_labels >= min_labels:
            score += 25
            feedback_parts.append(f"Found {num_labels} valid elevation labels in DXF.")
        elif num_labels > 0:
            score += 10
            feedback_parts.append(f"Found only {num_labels} valid elevation labels (expected >={min_labels}).")
        else:
            feedback_parts.append("No valid elevation text entities found in DXF.")
            
        # Anti-gaming: Automated labeling aligns text to contours, resulting in varied rotations.
        # Manual placement often leaves rotations at exactly 0.0.
        if len(text_rotations) > 1:
            score += 20
            feedback_parts.append("Text rotation variance detected (validates automated tool usage).")
        elif len(text_rotations) == 1 and 0.0 not in text_rotations:
            score += 10
            feedback_parts.append("Non-zero uniform text rotation detected.")
        else:
            feedback_parts.append("Text rotations suggest manual placement rather than automated tool.")

    # 3. VLM Verification on Trajectory Frames
    vlm_passed = False
    if query_vlm:
        from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
        frames = sample_trajectory_frames(traj, n=4)
        final = get_final_screenshot(traj)
        images = frames + [final] if final else frames
        
        prompt = """
        You are verifying a topographic CAD task in TopoCal.
        The goal was to add elevation labels to contour lines.
        
        Look at these screenshots from the user's session:
        1. Can you see numeric elevation labels (e.g., 1800, 1805) placed directly on or along the contour lines in the drawing area?
        2. Does it look like the user successfully completed the contour labeling operation?
        
        Respond with a JSON object:
        {
            "labels_visible": true/false,
            "operation_successful": true/false,
            "reasoning": "Brief explanation"
        }
        """
        vlm_res = query_vlm(images=images, prompt=prompt)
        
        if vlm_res and vlm_res.get("success"):
            parsed = vlm_res.get("parsed", {})
            if parsed.get("labels_visible") and parsed.get("operation_successful"):
                score += 30
                vlm_passed = True
                feedback_parts.append("VLM visually confirmed elevation labels on contours.")
            else:
                feedback_parts.append(f"VLM verification failed: {parsed.get('reasoning', 'Labels not clearly visible')}")
        else:
            feedback_parts.append("VLM query failed or returned invalid format.")

    # Determine final Pass/Fail
    # Must have created files AND parsed DXF successfully AND (VLM passed OR had sufficient DXF variance)
    key_criteria_met = files_created and len(valid_elevations) >= min_labels
    passed = (score >= 60) and key_criteria_met
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }