#!/usr/bin/env python3
"""
Verifier for Manhole Cover Detail task.
Uses ezdxf to parse the output DXF file and verify geometry, layers, and annotations.
Uses VLM to visually verify the drawing appearance.
"""

import json
import os
import tempfile
import logging
import math
from gym_anything.vlm import query_vlm, get_final_screenshot, sample_trajectory_frames

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Try to import ezdxf (should be installed in environment)
try:
    import ezdxf
    EZDXF_AVAILABLE = True
except ImportError:
    EZDXF_AVAILABLE = False
    logger.warning("ezdxf not installed, file content verification will be limited.")

def verify_manhole_detail(traj, env_info, task_info):
    """
    Verifies the manhole detail drawing.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_path = metadata.get('expected_output_path', '/home/ga/Documents/LibreCAD/manhole_detail.dxf')
    
    score = 0
    feedback_parts = []
    
    # 1. Retrieve Task Result JSON
    task_result = {}
    with tempfile.NamedTemporaryFile(suffix=".json") as f:
        try:
            copy_from_env("/tmp/task_result.json", f.name)
            f.seek(0)
            task_result = json.load(f)
        except Exception as e:
            logger.error(f"Failed to load task result: {e}")
            return {"passed": False, "score": 0, "feedback": "Failed to retrieve task execution metadata"}

    # 2. Check File Existence and Timestamp (Anti-gaming)
    if not task_result.get("output_exists", False):
        return {"passed": False, "score": 0, "feedback": "Output file manhole_detail.dxf not found."}
    
    if not task_result.get("file_created_during_task", False):
        return {"passed": False, "score": 0, "feedback": "Output file exists but was not created/modified during the task."}
    
    score += 10
    feedback_parts.append("File created successfully")

    # 3. Retrieve and Parse DXF File
    dxf_score = 0
    dxf_feedback = []
    
    with tempfile.NamedTemporaryFile(suffix=".dxf") as f:
        try:
            copy_from_env(expected_path, f.name)
            
            if EZDXF_AVAILABLE:
                try:
                    doc = ezdxf.readfile(f.name)
                    msp = doc.modelspace()
                    
                    # --- Geometry Checks ---
                    circles = list(msp.query('CIRCLE'))
                    radii = [c.dxf.radius for c in circles]
                    
                    # Frame Circle (R ~ 15)
                    has_frame = any(14.0 <= r <= 16.0 for r in radii)
                    if has_frame:
                        dxf_score += 10
                        dxf_feedback.append("Frame circle (R15) found")
                    
                    # Cover Circle (R ~ 12)
                    has_cover = any(11.0 <= r <= 13.0 for r in radii)
                    if has_cover:
                        dxf_score += 10
                        dxf_feedback.append("Cover circle (R12) found")
                        
                    # Pick Holes (R ~ 0.75, count >= 2)
                    pick_holes = [r for r in radii if 0.5 <= r <= 1.0]
                    if len(pick_holes) >= 2:
                        dxf_score += 10
                        dxf_feedback.append(f"Pick holes found ({len(pick_holes)})")
                    
                    # Center Lines
                    lines = list(msp.query('LINE'))
                    # Check for lines passing near origin (simple heuristic)
                    center_lines = 0
                    for line in lines:
                        start = line.dxf.start
                        end = line.dxf.end
                        # Check if line crosses or touches 0,0 area
                        # Cross product for distance from point to line is robust, 
                        # but simple bounding box check is usually enough for this task
                        min_x, max_x = min(start.x, end.x), max(start.x, end.x)
                        min_y, max_y = min(start.y, end.y), max(start.y, end.y)
                        if (min_x <= 1 and max_x >= -1) and (min_y <= 1 and max_y >= -1):
                            center_lines += 1
                    
                    if center_lines >= 2:
                        dxf_score += 10
                        dxf_feedback.append("Center lines detected")
                    
                    # --- Hatch Check ---
                    hatches = list(msp.query('HATCH'))
                    if len(hatches) > 0:
                        dxf_score += 10
                        dxf_feedback.append("Hatch entity found")
                        
                    # --- Dimensions Check ---
                    dimensions = list(msp.query('DIMENSION'))
                    if len(dimensions) >= 2:
                        dxf_score += 10
                        dxf_feedback.append(f"Dimensions found ({len(dimensions)})")
                        
                    # --- Text Check ---
                    texts = list(msp.query('TEXT MTEXT'))
                    text_content = " ".join([t.dxf.text for t in texts if hasattr(t.dxf, 'text')]).upper()
                    if "MANHOLE" in text_content:
                        dxf_score += 10
                        dxf_feedback.append("Title text found")
                        
                    # --- Layer Check ---
                    required_layers = set(["FRAME", "PICKHOLE", "CENTERLINE", "HATCH", "DIMENSIONS", "TEXT"])
                    existing_layers = set([layer.dxf.name.upper() for layer in doc.layers])
                    found_layers = required_layers.intersection(existing_layers)
                    
                    if len(found_layers) >= 4:
                        dxf_score += 15
                        dxf_feedback.append(f"Layers structure good ({len(found_layers)}/6)")
                    else:
                        dxf_feedback.append(f"Missing layers (found {len(found_layers)}/6)")

                except Exception as e:
                    logger.error(f"DXF Parsing Error: {e}")
                    dxf_feedback.append(f"DXF parsing failed: {str(e)}")
            else:
                dxf_feedback.append("Internal verification library missing")
                
        except Exception as e:
            logger.error(f"File handling error: {e}")
            dxf_feedback.append("Failed to process DXF file")

    score += dxf_score
    feedback_parts.extend(dxf_feedback)

    # 4. VLM Verification (Visual Check)
    vlm_score = 0
    final_screenshot = get_final_screenshot(traj)
    
    if final_screenshot:
        prompt = """
        Analyze this technical drawing screenshot. 
        I am looking for a "Manhole Frame and Cover" detail.
        
        Please check for:
        1. Two large concentric circles (frame and cover).
        2. Diagonal hatching pattern in the ring between the circles.
        3. Dimension lines with arrows and text.
        4. Text annotations (like "MANHOLE").
        5. Crosshair lines (center lines) going through the center.
        
        Is this a valid technical drawing of a manhole?
        """
        
        vlm_result = query_vlm(
            images=[final_screenshot], 
            prompt=prompt
        )
        
        if vlm_result.get("success"):
            # A simple heuristic for VLM confidence
            if "yes" in vlm_result.get("response", "").lower() or "valid" in vlm_result.get("response", "").lower():
                vlm_score = 15
                feedback_parts.append("Visual verification passed")
            else:
                feedback_parts.append("Visual verification ambiguous")
        else:
            feedback_parts.append("Visual verification failed to run")
    
    score += vlm_score

    # Final scoring logic
    # Pass if file exists, geometry is roughly correct, and score is high enough
    # The "Frame Circle" is a critical geometric requirement
    critical_met = "Frame circle (R15) found" in feedback_parts
    
    passed = (score >= 60) and critical_met

    return {
        "passed": passed,
        "score": min(100, score),
        "feedback": " | ".join(feedback_parts)
    }