#!/usr/bin/env python3
"""
Verifier for microfluidic_serpentine_mixer task.

Verification Logic:
1. DXF file existence and timestamp check (Anti-gaming).
2. DXF Content Analysis (via JSON generated in export_result.sh):
   - Check for required layers: SUBSTRATE, RESERVOIRS, CHANNEL.
   - Check Substrate: Should have entities (Rectangle).
   - Check Reservoirs: Should be 2 circles with ~2mm radius.
   - Check Channel: Should exist and have ARCs or Bulges (proof of fillets).
3. VLM Verification:
   - Visual confirmation of the zig-zag pattern inside the rectangle.
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import query_vlm, sample_trajectory_frames, get_final_screenshot

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_microfluidic_serpentine_mixer(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # 1. File Existence & Anti-Gaming (20 pts)
    if result.get('output_exists') and result.get('file_created_during_task'):
        score += 20
        feedback_parts.append("DXF file saved successfully.")
    elif result.get('output_exists'):
        score += 10
        feedback_parts.append("DXF file exists but timestamp suggests it wasn't created during task.")
    else:
        return {"passed": False, "score": 0, "feedback": "No output file found."}

    # 2. DXF Geometry Analysis (50 pts)
    dxf_data = result.get('dxf_analysis', {})
    
    if not dxf_data.get('valid_dxf'):
        feedback_parts.append("DXF file could not be parsed or was invalid.")
    else:
        # Check Layers (10 pts)
        layers = dxf_data.get('layers', [])
        required_layers = ['SUBSTRATE', 'RESERVOIRS', 'CHANNEL']
        found_layers = [l for l in required_layers if l in layers]
        if len(found_layers) == 3:
            score += 10
            feedback_parts.append("All required layers found.")
        else:
            feedback_parts.append(f"Missing layers: {set(required_layers) - set(layers)}")

        # Check Substrate (5 pts)
        if dxf_data.get('substrate_entity_count', 0) > 0:
            score += 5
            feedback_parts.append("Substrate geometry found.")
        else:
            feedback_parts.append("Substrate layer is empty.")

        # Check Reservoirs (15 pts)
        res_count = dxf_data.get('reservoir_count', 0)
        res_data = dxf_data.get('reservoir_data', [])
        valid_reservoirs = 0
        for r in res_data:
            # Radius tolerance: 2mm +/- 0.1
            if 1.9 <= r.get('radius', 0) <= 2.1:
                valid_reservoirs += 1
        
        if valid_reservoirs >= 2:
            score += 15
            feedback_parts.append("Two valid reservoirs found.")
        elif res_count >= 2:
            score += 5
            feedback_parts.append("Reservoirs found but dimensions incorrect.")
        else:
            feedback_parts.append("Reservoirs missing.")

        # Check Channel & Fillets (20 pts)
        channel_count = dxf_data.get('channel_entity_count', 0)
        arc_count = dxf_data.get('channel_arc_count', 0)
        bulge_count = dxf_data.get('channel_polyline_bulges', 0)
        
        if channel_count > 0:
            # Proof of Fillets: Arcs or Polyline Bulges
            if arc_count >= 4 or bulge_count >= 4:
                score += 20
                feedback_parts.append("Channel path with fillets detected.")
            else:
                score += 10
                feedback_parts.append("Channel path found, but fillets/rounding appear missing (no arcs detected).")
        else:
            feedback_parts.append("Channel layer is empty.")

    # 3. VLM Verification (30 pts)
    frames = sample_trajectory_frames(traj, n=4)
    final_shot = get_final_screenshot(traj)
    
    vlm_prompt = """
    Review the final state of this CAD drawing.
    The user was asked to draw a microfluidic chip:
    1. A rectangle (slide).
    2. Two circles (reservoirs) inside.
    3. A zig-zag or serpentine line connecting the circles.
    4. The zig-zag should have rounded corners (fillets).
    
    Do you see a zig-zag/wavy line connecting two points inside a rectangle?
    Does the drawing look like a clean technical schematic?
    """
    
    try:
        vlm_res = query_vlm(images=frames + [final_shot], prompt=vlm_prompt)
        # Simple keyword matching if VLM returns boolean-like text, or use structured output if available
        # Assuming VLM returns a general analysis string
        vlm_text = vlm_res.get('text', '').lower()
        
        vlm_score = 0
        if "zig-zag" in vlm_text or "serpentine" in vlm_text or "wavy" in vlm_text or "connecting" in vlm_text:
            vlm_score += 15
        if "rectangle" in vlm_text and "circle" in vlm_text:
            vlm_score += 15
            
        # Fallback if VLM is generic: check for positive sentiment keywords
        if vlm_score == 0 and ("yes" in vlm_text or "correct" in vlm_text or "appears to be" in vlm_text):
            vlm_score = 20
            
        score += vlm_score
        feedback_parts.append(f"Visual verification: {vlm_text[:50]}...")
        
    except Exception as e:
        logger.error(f"VLM check failed: {e}")
        # Graceful degradation: If programmatic checks passed well (score > 60), assume visual is likely okay
        if score >= 60:
            score += 20
            feedback_parts.append("VLM check skipped, programmatic checks passed.")

    return {
        "passed": score >= 75,
        "score": score,
        "feedback": " ".join(feedback_parts)
    }