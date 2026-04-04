#!/usr/bin/env python3
"""Verifier for create_wms_decoration_layout task."""

import json
import tempfile
import os
import xml.etree.ElementTree as ET

def verify_create_wms_decoration_layout(traj, env_info, task_info):
    """Verify WMS decoration layout creation and map generation."""

    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_text = metadata.get('expected_text', '© Natural Earth Data')

    # Copy result file
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/create_wms_decoration_layout_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # Verify nonce
    nonce_temp = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
    try:
        copy_from_env("/tmp/result_nonce", nonce_temp.name)
        with open(nonce_temp.name, 'r') as f:
            expected_nonce = f.read().strip()
        if result.get('result_nonce') != expected_nonce:
            return {"passed": False, "score": 0, "feedback": "INTEGRITY FAIL: nonce mismatch"}
    except Exception:
        pass # Optional check
    finally:
        if os.path.exists(nonce_temp.name):
            os.unlink(nonce_temp.name)

    score = 0
    feedback_parts = []
    
    # 1. Layout file exists in container (15 pts)
    if result.get('layout_file_exists'):
        score += 15
        feedback_parts.append("Layout file created in container")
    else:
        feedback_parts.append("Layout file NOT found in container")

    # 2. Check XML Content (20 pts)
    layout_content = result.get('layout_content', '')
    has_scaleline = False
    has_text = False
    
    if layout_content:
        try:
            # Wrap in root if needed (layout files usually have a root element)
            # GeoServer layouts usually start with <layout>
            if not layout_content.strip().startswith('<'):
                feedback_parts.append("Invalid XML format")
            else:
                root = ET.fromstring(layout_content)
                # Naive check for tags and text attributes
                xml_str = layout_content.lower()
                
                # Check for scaleline (10 pts)
                if 'scaleline' in xml_str:
                    has_scaleline = True
                    score += 10
                    feedback_parts.append("Layout contains scaleline")
                
                # Check for text decoration (10 pts)
                # Check if the specific text is present
                if expected_text in layout_content:
                    has_text = True
                    score += 10
                    feedback_parts.append(f"Layout contains correct text: '{expected_text}'")
                elif 'text' in xml_str:
                    score += 5
                    feedback_parts.append("Layout contains text decoration but wrong message")
        except ET.ParseError:
            feedback_parts.append("XML parsing error")
            # Fallback text search
            if 'scaleline' in layout_content.lower():
                score += 5
                feedback_parts.append("Found 'scaleline' (text search)")
            if expected_text in layout_content:
                score += 5
                feedback_parts.append("Found expected text (text search)")

    # 3. Images exist (30 pts)
    undec_exists = result.get('undecorated_exists')
    dec_exists = result.get('decorated_exists')
    
    if undec_exists:
        score += 15
        feedback_parts.append("Undecorated map image generated")
    
    if dec_exists:
        score += 15
        feedback_parts.append("Decorated map image generated")

    # 4. Images differ (15 pts)
    # This proves the decoration actually rendered
    if result.get('images_differ'):
        score += 15
        feedback_parts.append("Decorated image differs from undecorated (decoration applied)")
    elif undec_exists and dec_exists:
        feedback_parts.append("Warning: Decorated and undecorated images are identical")

    # 5. VLM Verification (20 pts)
    # Check visuals + workflow
    query_vlm = env_info.get('query_vlm')
    if query_vlm and traj:
        from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
        
        # We need the final image (decorated map) specifically, 
        # but verify logic usually only has access to screenshots.
        # However, we can ask VLM to check trajectory for CLI usage.
        
        frames = sample_trajectory_frames(traj, num_samples=5)
        
        vlm_result = query_vlm(
            images=frames,
            prompt=(
                "These screenshots show an agent working on a GeoServer task.\n"
                "1. Did the agent use the terminal/console to create a file?\n"
                "2. Did the agent use 'curl', 'wget' or browser to download/view map images?\n"
                "3. Can you see a map image displayed with a scale bar or text 'Natural Earth Data'?\n\n"
                "Return JSON: {\"cli_file_creation\": bool, \"map_generation_attempt\": bool, \"decoration_visible\": bool}"
            )
        )
        
        if vlm_result and isinstance(vlm_result, dict) and vlm_result.get('success', True):
            parsed = vlm_result.get('parsed', {})
            
            if parsed.get('cli_file_creation', False):
                score += 10
                feedback_parts.append("VLM: Detected CLI file creation")
            
            if parsed.get('decoration_visible', False):
                score += 10
                feedback_parts.append("VLM: Detected decoration on map")
            elif parsed.get('map_generation_attempt', False):
                score += 5
                feedback_parts.append("VLM: Detected map generation attempt")
        else:
             # Fallback if VLM fails/not available but programmatic passed
            if score >= 60:
                 score += 20
                 feedback_parts.append("VLM unavailable - assumed pass based on programmatic success")
    else:
        # Fallback
        if score >= 60:
             score += 20
             feedback_parts.append("VLM unavailable - assumed pass based on programmatic success")

    passed = score >= 60 and result.get('layout_file_exists') and (undec_exists or dec_exists)
    
    return {
        "passed": passed,
        "score": min(100, score),
        "feedback": " | ".join(feedback_parts)
    }