#!/usr/bin/env python3
"""
Verifier for create_global_supply_chain_map task.

Verification Strategy:
1. File-based: Check if .eddx and .png files exist and were created during the task.
2. Content-based: Unzip the .eddx file and search XML for specific text labels.
3. VLM-based: Use trajectory frames to verify the visual map structure (arrows, world map).
"""

import json
import os
import tempfile
import zipfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_global_supply_chain_map(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    required_text = metadata.get('required_text', [])
    
    score = 0
    feedback_parts = []
    
    # 1. Retrieve Result JSON
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {e}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    # 2. Verify File Existence & Creation (30 pts)
    eddx_exists = result_data.get('eddx_exists', False)
    eddx_fresh = result_data.get('eddx_created_during_task', False)
    png_exists = result_data.get('png_exists', False)
    png_fresh = result_data.get('png_created_during_task', False)
    eddx_size = result_data.get('eddx_size', 0)

    if eddx_exists and eddx_fresh and eddx_size > 5000:
        score += 15
        feedback_parts.append("Valid .eddx file created")
    elif eddx_exists:
        score += 5
        feedback_parts.append(".eddx file exists but may be stale or empty")
    else:
        feedback_parts.append("No .eddx file found")

    if png_exists and png_fresh:
        score += 15
        feedback_parts.append("Valid PNG export created")
    else:
        feedback_parts.append("No PNG export found")

    # 3. Content Verification via XML Parsing (40 pts)
    content_score = 0
    text_found_count = 0
    
    if eddx_exists:
        temp_eddx = tempfile.NamedTemporaryFile(delete=False, suffix='.eddx')
        try:
            copy_from_env("/home/ga/Documents/phoenix_supply_chain.eddx", temp_eddx.name)
            
            with zipfile.ZipFile(temp_eddx.name, 'r') as zf:
                # Combine all XML content
                all_xml = ""
                for name in zf.namelist():
                    if name.endswith('.xml'):
                        try:
                            all_xml += zf.read(name).decode('utf-8', errors='ignore')
                        except:
                            pass
                
                # Check for required text strings
                found_terms = []
                for term in required_text:
                    if term.lower() in all_xml.lower():
                        text_found_count += 1
                        found_terms.append(term)
                
                # Scoring: 8 points per term, max 40
                content_score = min(40, text_found_count * 8)
                score += content_score
                if found_terms:
                    feedback_parts.append(f"Found text labels: {', '.join(found_terms)}")
                else:
                    feedback_parts.append("No required text labels found in diagram")
                    
        except zipfile.BadZipFile:
            feedback_parts.append("EDDX file is not a valid zip archive")
        except Exception as e:
            feedback_parts.append(f"Error checking file content: {str(e)}")
        finally:
            if os.path.exists(temp_eddx.name):
                os.unlink(temp_eddx.name)

    # 4. VLM Visual Verification (30 pts)
    # Using trajectory frames to prove work was done
    vlm_score = 0
    frames = sample_trajectory_frames(traj, n=4)
    final_shot = get_final_screenshot(traj)
    
    if frames and final_shot:
        prompt = """
        You are verifying a supply chain mapping task in EdrawMax.
        
        The user was asked to:
        1. Create a World Map.
        2. Place markers on Seoul, Hsinchu, Shenzhen, and Memphis.
        3. Draw arrows connecting them (Asia to Asia, Asia to USA).
        
        Look at the provided screenshots (trajectory + final).
        
        Verification Questions:
        1. Is there a World Map visible? (Yes/No)
        2. Are there markers or labels roughly in East Asia and North America? (Yes/No)
        3. Are there connector lines/arrows drawn between locations? (Yes/No)
        
        Respond in JSON: {"world_map_visible": bool, "markers_visible": bool, "arrows_visible": bool}
        """
        
        try:
            # We send the final shot plus a sampling of the trajectory
            vlm_result = query_vlm(images=frames + [final_shot], prompt=prompt)
            parsed = vlm_result.get('parsed', {})
            
            if parsed.get('world_map_visible', False):
                vlm_score += 10
            if parsed.get('markers_visible', False):
                vlm_score += 10
            if parsed.get('arrows_visible', False):
                vlm_score += 10
                
            score += vlm_score
            feedback_parts.append(f"Visual verification score: {vlm_score}/30")
            
        except Exception as e:
            feedback_parts.append(f"VLM verification failed: {e}")
            # Fallback: if text content was perfect, assume visual is okay-ish to avoid 0 if VLM fails
            if content_score >= 30:
                score += 15
                feedback_parts.append("Allocated fallback points for visual check due to high text match")

    # Final Pass Determination
    # Must have files (30), decent content (>=16 i.e. 2 labels), and some visual confirmation or perfect content
    passed = (score >= 65 and eddx_exists and text_found_count >= 2)

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }