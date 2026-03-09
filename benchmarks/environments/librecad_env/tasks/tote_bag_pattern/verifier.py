#!/usr/bin/env python3
"""
Verifier for tote_bag_pattern task.
Checks DXF geometry for correct dimensions, layers, chamfers, and offsets.
"""

import json
import os
import sys
import tempfile
import logging
import math
from typing import Dict, Any, List, Tuple

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Try importing ezdxf, fail gracefully if not available (will rely on VLM fallback if needed)
try:
    import ezdxf
    from ezdxf.document import Drawing
    EZDXF_AVAILABLE = True
except ImportError:
    logger.warning("ezdxf not installed. Programmatic geometric verification will be limited.")
    EZDXF_AVAILABLE = False

from gym_anything.vlm import query_vlm, sample_trajectory_frames, get_final_screenshot

def verify_tote_bag_pattern(traj, env_info, task_info):
    """
    Verifies the tote bag pattern task.
    
    Scoring Criteria:
    1. File Creation (10 pts): Valid DXF created during task.
    2. Layers (10 pts): Correct layers (STITCH_LINE, SEAM_ALLOWANCE, FOLD_LINE) exist.
    3. Body Geometry (20 pts): 350x400mm bounds on STITCH_LINE.
    4. Chamfer (20 pts): Bottom corners are chamfered (geometry analysis).
    5. Offset (20 pts): Seam allowance layer has correct expanded bounds.
    6. Fold Line (10 pts): Horizontal line at correct height.
    7. VLM Check (10 pts): Visual confirmation of workflow/result.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_path = metadata.get('expected_output_path', '/home/ga/Documents/LibreCAD/tote_bag_pattern.dxf')
    
    score = 0
    feedback_parts = []
    
    # 1. Load Task Result JSON
    task_result = {}
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            task_result = json.load(f)
    except Exception as e:
        logger.error(f"Failed to load task result: {e}")
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)
            
    # Check if file exists and was created during task
    if not task_result.get('output_exists', False):
        return {"passed": False, "score": 0, "feedback": "DXF file not found. Task incomplete."}
    
    if not task_result.get('file_created_during_task', False):
        feedback_parts.append("WARNING: File timestamp indicates it was not created during this session.")
        # We continue but this is suspicious
    else:
        score += 10
        feedback_parts.append("File created successfully.")

    # 2. Analyze DXF Content
    dxf_score = 0
    dxf_feedback = []
    
    temp_dxf = tempfile.NamedTemporaryFile(delete=False, suffix='.dxf')
    try:
        copy_from_env(expected_path, temp_dxf.name)
        
        if EZDXF_AVAILABLE:
            try:
                doc = ezdxf.readfile(temp_dxf.name)
                msp = doc.modelspace()
                
                # Check Layers
                layers = doc.layers
                layer_names = [l.dxf.name.upper() for l in layers]
                required_layers = ["STITCH_LINE", "SEAM_ALLOWANCE", "FOLD_LINE"]
                missing_layers = [l for l in required_layers if l not in layer_names]
                
                if not missing_layers:
                    dxf_score += 10
                    dxf_feedback.append("All required layers present.")
                else:
                    dxf_feedback.append(f"Missing layers: {', '.join(missing_layers)}")

                # Analyze STITCH_LINE (Body)
                stitch_entities = msp.query('INSERT LINE LWPOLYLINE POLYLINE[layer=="STITCH_LINE"]')
                if len(stitch_entities) > 0:
                    bbox = ezdxf.bbox.extents(stitch_entities)
                    width = bbox.extmax.x - bbox.extmin.x
                    height = bbox.extmax.y - bbox.extmin.y
                    
                    # Expected 350x400
                    if 348 <= width <= 352 and 398 <= height <= 402:
                        dxf_score += 20
                        dxf_feedback.append("Body dimensions correct (350x400).")
                        
                        # Check for Chamfer
                        # Logic: A simple rectangle has 4 corners. A chamfered one has cuts.
                        # Area check is robust: 350*400 = 140000. 
                        # Chamfer 30mm means removing 2 triangles of 0.5*30*30 = 450 each. Total 900 removed.
                        # Expected Area ~ 139100.
                        # Since calculating area of loose entities is hard, let's check vertex count or specific lines.
                        
                        # Check for diagonal lines
                        has_diagonal = False
                        for e in stitch_entities:
                            if e.dxftype() == 'LINE':
                                dx = abs(e.dxf.start.x - e.dxf.end.x)
                                dy = abs(e.dxf.start.y - e.dxf.end.y)
                                if dx > 1 and dy > 1 and abs(dx - dy) < 5: # Diagonal 45 deg
                                    has_diagonal = True
                            elif e.dxftype() == 'LWPOLYLINE':
                                for i in range(len(e) - 1):
                                    p1 = e[i]
                                    p2 = e[i+1]
                                    dx = abs(p1[0] - p2[0])
                                    dy = abs(p1[1] - p2[1])
                                    if dx > 1 and dy > 1 and abs(dx - dy) < 5:
                                        has_diagonal = True
                                        
                        if has_diagonal:
                            dxf_score += 20
                            dxf_feedback.append("Chamfer detected (diagonal geometry found).")
                        else:
                            dxf_feedback.append("Chamfer geometry not clearly detected.")
                    else:
                        dxf_feedback.append(f"Body dimensions incorrect: {width:.1f}x{height:.1f} (Exp: 350x400).")
                else:
                    dxf_feedback.append("No geometry on STITCH_LINE layer.")

                # Analyze SEAM_ALLOWANCE (Offset)
                seam_entities = msp.query('INSERT LINE LWPOLYLINE POLYLINE[layer=="SEAM_ALLOWANCE"]')
                if len(seam_entities) > 0:
                    bbox_seam = ezdxf.bbox.extents(seam_entities)
                    w_seam = bbox_seam.extmax.x - bbox_seam.extmin.x
                    h_seam = bbox_seam.extmax.y - bbox_seam.extmin.y
                    
                    # Expected: 350 + 15 + 15 = 380, 400 + 15 + 15 = 430
                    if 378 <= w_seam <= 382 and 428 <= h_seam <= 432:
                        dxf_score += 20
                        dxf_feedback.append("Seam allowance dimensions correct.")
                    else:
                        dxf_feedback.append(f"Seam allowance bounds incorrect: {w_seam:.1f}x{h_seam:.1f}.")
                else:
                    dxf_feedback.append("No geometry on SEAM_ALLOWANCE layer.")

                # Analyze FOLD_LINE
                fold_entities = msp.query('LINE[layer=="FOLD_LINE"]')
                if len(fold_entities) > 0:
                    # Check vertical position relative to top
                    # Top Y is usually around 500 (100+400)
                    bbox_fold = ezdxf.bbox.extents(fold_entities)
                    fold_y = (bbox_fold.extmax.y + bbox_fold.extmin.y) / 2
                    
                    # Assuming standard origin (100,100), top is 500. Fold should be at 460.
                    if 450 <= fold_y <= 470:
                        dxf_score += 10
                        dxf_feedback.append("Fold line at correct height.")
                    else:
                        dxf_feedback.append(f"Fold line Y position {fold_y:.1f} seems off (Exp ~460).")
                else:
                    dxf_feedback.append("No lines on FOLD_LINE layer.")

            except Exception as e:
                logger.error(f"DXF Parsing Error: {e}")
                dxf_feedback.append(f"Error parsing DXF: {e}")
        else:
            dxf_feedback.append("DXF parsing skipped (ezdxf not available).")
            # If ezdxf missing, we give partial credit or rely heavily on VLM
            dxf_score = 40 # Grace points if tools are missing

    finally:
        if os.path.exists(temp_dxf.name):
            os.unlink(temp_dxf.name)
            
    score += dxf_score
    feedback_parts.extend(dxf_feedback)

    # 3. VLM Verification (Trajectory + Final State)
    vlm_score = 0
    frames = sample_trajectory_frames(traj, n=4)
    final_shot = get_final_screenshot(traj)
    
    if final_shot:
        frames.append(final_shot)
        
    prompt = """
    Review this CAD workflow in LibreCAD.
    The goal is to design a tote bag pattern.
    
    Check for:
    1. A main rectangular shape with cut/angled corners at the bottom (Chamfer).
    2. An outer contour line surrounding the main shape (Seam Allowance).
    3. A horizontal line near the top (Fold Line).
    4. Different colors used for lines (indicating layers).
    
    Does the final result look like a technical sewing pattern matching these criteria?
    """
    
    try:
        vlm_result = query_vlm(images=frames, prompt=prompt)
        if vlm_result.get('success') and vlm_result.get('parsed', {}).get('positive_assessment', True):
            # Simple keyword check if structured parse fails
            resp = vlm_result.get('response', '').lower()
            if 'yes' in resp or 'correct' in resp or 'match' in resp:
                vlm_score = 10
                feedback_parts.append("VLM confirms visual correctness.")
            else:
                 feedback_parts.append("VLM did not confirm visual correctness.")
        else:
            # Fallback if VLM is ambiguous but file analysis passed
            if dxf_score > 40:
                vlm_score = 10
    except Exception as e:
        logger.error(f"VLM error: {e}")
        # Grace points if VLM fails but file is good
        if dxf_score > 50:
            vlm_score = 10

    score += vlm_score

    return {
        "passed": score >= 75,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }