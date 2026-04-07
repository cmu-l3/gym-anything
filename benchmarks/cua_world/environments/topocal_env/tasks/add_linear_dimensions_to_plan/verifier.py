#!/usr/bin/env python3
"""
Verifier for add_linear_dimensions_to_plan task.
Evaluates the exported DXF file to ensure spatial dimensions were correctly generated and placed.
"""

import os
import json
import tempfile
import math
import re
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def parse_dxf_text_entities(filepath):
    """
    Manually parses a DXF file to extract text-like entities (TEXT, MTEXT, DIMENSION)
    and their locations, avoiding the need for external packages like ezdxf.
    """
    entities = []
    current_entity = {}
    
    try:
        with open(filepath, 'r', encoding='utf-8', errors='ignore') as f:
            lines = [l.strip() for l in f.readlines()]
            
        i = 0
        while i < len(lines) - 1:
            code = lines[i]
            val = lines[i+1]
            
            if code == '0':
                if current_entity and 'text_val' in current_entity:
                    entities.append(current_entity)
                current_entity = {'type': val}
            elif code == '1':
                # Replace comma with period for Spanish locale floats
                clean_val = val.replace(',', '.')
                # Extract the first floating point number sequence
                match = re.search(r'[-+]?\d*\.\d+|\d+', clean_val)
                if match:
                    current_entity['text_val'] = float(match.group())
            elif code == '10' and 'x' not in current_entity:
                current_entity['x'] = float(val)
            elif code == '20' and 'y' not in current_entity:
                current_entity['y'] = float(val)
            elif code == '11': # Text alignment insertion X
                current_entity['x'] = float(val)
            elif code == '21': # Text alignment insertion Y
                current_entity['y'] = float(val)
                
            i += 2
            
        if current_entity and 'text_val' in current_entity:
            entities.append(current_entity)
            
    except Exception as e:
        logger.error(f"Error parsing DXF file: {e}")
        
    return entities

def verify_add_dimensions(traj, env_info, task_info):
    """
    Main verification logic utilizing native JSON & DXF text parsing and VLM.
    """
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_lengths = metadata.get('expected_lengths', [64.57, 66.26, 63.76, 68.24])
    tolerance = metadata.get('tolerance_m', 0.05)
    spatial_tolerance = metadata.get('spatial_tolerance_m', 20.0)
    expected_midpoints = metadata.get('expected_midpoints', [])

    score = 0
    feedback_parts = []
    
    # Read primary task result from JSON
    result_json_path = tempfile.NamedTemporaryFile(delete=False, suffix='.json').name
    try:
        copy_from_env("C:\\tmp\\task_result.json", result_json_path)
        with open(result_json_path, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result JSON: {e}"}
    finally:
        if os.path.exists(result_json_path):
            os.remove(result_json_path)

    # 1. Check File Generation (10 points)
    dxf_ok = result.get('dxf_exists') and result.get('dxf_created_during_task')
    top_ok = result.get('top_exists') and result.get('top_created_during_task')
    
    if dxf_ok and top_ok:
        score += 10
        feedback_parts.append("Project and DXF files successfully exported.")
    elif dxf_ok:
        score += 5
        feedback_parts.append("DXF exported, but .top project file missing or not saved.")
    else:
        feedback_parts.append("DXF file not successfully exported. Cannot verify precise geometries.")
        return {"passed": False, "score": score, "feedback": " | ".join(feedback_parts)}

    # 2. Parse DXF to find entities
    dxf_local_path = tempfile.NamedTemporaryFile(delete=False, suffix='.dxf').name
    try:
        copy_from_env("C:\\Users\\Docker\\Documents\\TopoCal_Project\\boundary_dimensioned.dxf", dxf_local_path)
        extracted_entities = parse_dxf_text_entities(dxf_local_path)
    except Exception as e:
        extracted_entities = []
        feedback_parts.append(f"Failed to copy or read exported DXF: {e}")
    finally:
        if os.path.exists(dxf_local_path):
            os.remove(dxf_local_path)

    if len(extracted_entities) >= 4:
        score += 20
        feedback_parts.append(f"Found {len(extracted_entities)} text/dimension entities.")
    elif len(extracted_entities) > 0:
        score += 5 * len(extracted_entities)
        feedback_parts.append(f"Found only {len(extracted_entities)} text/dimension entities.")
    else:
        feedback_parts.append("No text or dimension entities found in DXF export.")
        
    # 3. Verify Value Accuracy & Spatial Location (40 pts value + 15 pts location)
    matched_lengths = set()
    correct_placements = 0
    
    for entity in extracted_entities:
        val = entity.get('text_val', -1)
        ex, ey = entity.get('x', 0), entity.get('y', 0)
        
        # Check against expected lines
        for i, expected_val in enumerate(expected_lengths):
            if i in matched_lengths:
                continue
                
            if abs(val - expected_val) <= tolerance:
                matched_lengths.add(i)
                
                # Check spatial placement (Anti-gaming measure)
                if expected_midpoints:
                    mx, my = expected_midpoints[i]
                    dist = math.sqrt((ex - mx)**2 + (ey - my)**2)
                    if dist <= spatial_tolerance:
                        correct_placements += 1
                break

    value_score = len(matched_lengths) * 10
    score += value_score
    feedback_parts.append(f"{len(matched_lengths)}/4 lengths mathematically correct.")
    
    placement_score = int((correct_placements / 4) * 15) if len(matched_lengths) > 0 else 0
    score += placement_score
    if correct_placements > 0:
        feedback_parts.append(f"{correct_placements} dimensions correctly placed near segment midpoints.")

    # 4. VLM Fallback/Visual Verification (15 pts)
    vlm_score = 0
    if query_vlm:
        try:
            from gym_anything.vlm import get_final_screenshot
            final_screenshot = get_final_screenshot(traj)
            if final_screenshot:
                prompt = (
                    "Look at this CAD/Topography software interface. "
                    "Are there text numbers indicating lengths/distances drawn along the sides of the central polygon? "
                    "Reply in JSON: {\"dimensions_visible\": true/false}"
                )
                vlm_resp = query_vlm(prompt=prompt, image=final_screenshot)
                if vlm_resp.get('success') and vlm_resp.get('parsed', {}).get('dimensions_visible'):
                    vlm_score = 15
                    feedback_parts.append("VLM confirmed dimensions visible on screen.")
        except Exception as e:
            logger.warning(f"VLM verification failed: {e}")
    score += vlm_score

    # Final logic
    key_criteria_met = len(matched_lengths) == 4 and correct_placements >= 3
    passed = score >= 80 and key_criteria_met

    if passed:
        feedback_parts.insert(0, "SUCCESS")
    else:
        feedback_parts.insert(0, "FAILED")

    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback_parts)
    }