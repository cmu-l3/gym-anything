#!/usr/bin/env python3
"""
Verifier for create_network_topology task.

Verification Strategy:
1. File-based: Check if .eddx and .png files exist and were created during the task.
2. Content-based: Parse the .eddx (ZIP/XML) to verify required labels and IP addresses exist.
3. Visual: Use VLM to verify the PNG export shows a structured diagram with connections.
"""

import json
import os
import tempfile
import zipfile
import logging
from gym_anything.vlm import query_vlm, get_final_screenshot, sample_trajectory_frames

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_network_topology(traj, env_info, task_info):
    """
    Verify that the agent created a labeled network topology diagram.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    required_labels = metadata.get('required_labels', [])
    required_ips = metadata.get('required_ips', [])

    # Load export results
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

    score = 0
    feedback_parts = []
    
    # ---------------------------------------------------------
    # 1. FILE EXISTENCE & ANTI-GAMING (20 pts)
    # ---------------------------------------------------------
    eddx_exists = result_data.get('eddx_exists', False)
    eddx_valid_time = result_data.get('eddx_created_during_task', False)
    png_exists = result_data.get('png_exists', False)
    png_valid_time = result_data.get('png_created_during_task', False)

    if eddx_exists:
        if eddx_valid_time:
            score += 10
            feedback_parts.append("EDDX file created successfully")
        else:
            feedback_parts.append("EDDX file exists but has old timestamp (pre-task?)")
    else:
        feedback_parts.append("EDDX file missing")

    if png_exists:
        if png_valid_time:
            score += 10
            feedback_parts.append("PNG export created successfully")
        else:
            feedback_parts.append("PNG file exists but has old timestamp")
    else:
        feedback_parts.append("PNG export missing")

    # ---------------------------------------------------------
    # 2. CONTENT VERIFICATION (EDDX PARSING) (50 pts)
    # ---------------------------------------------------------
    xml_content = ""
    labels_found = 0
    ips_found = 0
    
    if eddx_exists:
        temp_eddx = tempfile.NamedTemporaryFile(delete=False, suffix='.eddx')
        try:
            copy_from_env(metadata.get('eddx_path', '/home/ga/Documents/network_topology.eddx'), temp_eddx.name)
            
            # EdrawMax .eddx is a ZIP containing XML files
            if zipfile.is_zipfile(temp_eddx.name):
                with zipfile.ZipFile(temp_eddx.name, 'r') as zf:
                    # Read all XML files to find text content
                    for filename in zf.namelist():
                        if filename.endswith('.xml'):
                            try:
                                content = zf.read(filename).decode('utf-8', errors='ignore')
                                xml_content += content
                            except:
                                pass
            
            # Check for required labels
            for label in required_labels:
                if label in xml_content:
                    labels_found += 1
            
            # Check for required IPs
            for ip in required_ips:
                if ip in xml_content:
                    ips_found += 1
            
            # Score labels (max 25 pts)
            label_score = int((labels_found / len(required_labels)) * 25)
            score += label_score
            feedback_parts.append(f"Found {labels_found}/{len(required_labels)} component labels")
            
            # Score IPs (max 25 pts)
            ip_score = int((ips_found / len(required_ips)) * 25)
            score += ip_score
            feedback_parts.append(f"Found {ips_found}/{len(required_ips)} IP addresses")
            
        except Exception as e:
            feedback_parts.append(f"Error parsing EDDX file: {e}")
        finally:
            if os.path.exists(temp_eddx.name):
                os.unlink(temp_eddx.name)
    
    # ---------------------------------------------------------
    # 3. VISUAL VERIFICATION (VLM) (30 pts)
    # ---------------------------------------------------------
    # Use trajectory frames to verify workflow + PNG for final quality
    # We use the exported PNG if available, otherwise the final screen
    
    vlm_image = None
    vlm_source = "screen"
    
    if png_exists:
        temp_png = tempfile.NamedTemporaryFile(delete=False, suffix='.png')
        try:
            copy_from_env(metadata.get('png_path', '/home/ga/Documents/network_topology.png'), temp_png.name)
            vlm_image = temp_png.name
            vlm_source = "export"
        except:
            pass
    
    # If no export, fall back to final screenshot
    if not vlm_image:
        vlm_image = get_final_screenshot(traj)
    
    if vlm_image:
        prompt = """
        Analyze this image of a network diagram.
        1. Are there distinct network shapes visible (clouds, firewalls, routers, switches, servers, PCs)?
        2. Are there connector lines joining these shapes?
        3. Is there a hierarchical structure (e.g. Internet at top/left, devices at bottom/right)?
        4. Are there text labels visible near the shapes?
        
        Answer JSON: {"shapes_visible": bool, "connectors_visible": bool, "structure_visible": bool, "labels_visible": bool}
        """
        
        try:
            result = query_vlm(image=vlm_image, prompt=prompt)
            if result.get('success'):
                parsed = result.get('parsed', {})
                
                vlm_score = 0
                if parsed.get('shapes_visible'): vlm_score += 10
                if parsed.get('connectors_visible'): vlm_score += 10
                if parsed.get('structure_visible'): vlm_score += 5
                if parsed.get('labels_visible'): vlm_score += 5
                
                score += vlm_score
                feedback_parts.append(f"Visual verification ({vlm_source}): {vlm_score}/30 pts")
                
                # Cleanup
                if vlm_source == "export" and os.path.exists(vlm_image):
                    os.unlink(vlm_image)
            else:
                feedback_parts.append("VLM verification failed to process image")
        except Exception as e:
            feedback_parts.append(f"VLM error: {e}")

    # ---------------------------------------------------------
    # FINAL SCORING
    # ---------------------------------------------------------
    
    # Pass threshold: 60 points + EDDX file must exist + at least some labels found
    passed = (score >= 60) and eddx_exists and (labels_found >= 3)
    
    return {
        "passed": passed,
        "score": min(100, score),
        "feedback": " | ".join(feedback_parts)
    }