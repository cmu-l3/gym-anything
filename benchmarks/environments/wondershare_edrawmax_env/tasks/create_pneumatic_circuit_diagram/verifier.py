#!/usr/bin/env python3
"""
Verifier for create_pneumatic_circuit_diagram task.

This script verifies that:
1. The agent created the required .eddx and .png files.
2. The .eddx file is a valid archive and contains specific text labels and keywords.
3. The visual output (trajectory/final screenshot) confirms a schematic diagram structure.
"""

import json
import os
import tempfile
import zipfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_pneumatic_circuit_diagram(traj, env_info, task_info):
    """
    Verify the pneumatic circuit diagram task.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    required_labels = metadata.get('required_labels', ["Main Air", "FRL-01", "SOL-A", "Clamp Cyl"])
    required_xml_terms = metadata.get('required_xml_terms', ["Pneumatic", "Cylinder", "Valve"])

    score = 0
    max_score = 100
    feedback_parts = []
    
    # 1. Retrieve Task Result JSON
    temp_result_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result_file.name)
        with open(temp_result_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read task result: {e}"}
    finally:
        if os.path.exists(temp_result_file.name):
            os.unlink(temp_result_file.name)

    # 2. Verify File Existence & Timestamps (20 points)
    eddx_exists = result.get('eddx_exists', False)
    eddx_created = result.get('eddx_created_during_task', False)
    png_exists = result.get('png_exists', False)
    png_created = result.get('png_created_during_task', False)
    eddx_size = result.get('eddx_size', 0)

    if eddx_exists and eddx_created and eddx_size > 5000: # 5KB min for non-empty diagram
        score += 10
        feedback_parts.append("EDDX file created successfully")
    elif eddx_exists:
        feedback_parts.append("EDDX file exists but timestamp invalid or file too small")
    else:
        feedback_parts.append("EDDX file not found")

    if png_exists and png_created:
        score += 10
        feedback_parts.append("PNG export created successfully")
    elif png_exists:
        feedback_parts.append("PNG exists but timestamp invalid")
    else:
        feedback_parts.append("PNG export not found")

    # 3. Verify EDDX Content (Programmatic) (40 points)
    # The .eddx format is a ZIP containing XML files. We search the XML for keywords.
    content_score = 0
    labels_found = []
    terms_found = []
    
    if eddx_exists:
        temp_eddx = tempfile.NamedTemporaryFile(delete=False, suffix='.eddx')
        try:
            copy_from_env(result.get('eddx_path', ''), temp_eddx.name)
            
            with zipfile.ZipFile(temp_eddx.name, 'r') as zf:
                # Concatenate all XML content to search
                all_xml_content = ""
                for filename in zf.namelist():
                    if filename.endswith(".xml"):
                        try:
                            all_xml_content += zf.read(filename).decode('utf-8', errors='ignore')
                        except:
                            pass
                
                # Check for labels (20 pts)
                labels_hit = 0
                for label in required_labels:
                    if label.lower() in all_xml_content.lower():
                        labels_hit += 1
                        labels_found.append(label)
                
                if len(required_labels) > 0:
                    content_score += int(20 * (labels_hit / len(required_labels)))
                
                # Check for pneumatic terms/shapes (20 pts)
                terms_hit = 0
                for term in required_xml_terms:
                    if term.lower() in all_xml_content.lower():
                        terms_hit += 1
                        terms_found.append(term)
                
                if len(required_xml_terms) > 0:
                    content_score += int(20 * (terms_hit / len(required_xml_terms)))
                    
        except Exception as e:
            feedback_parts.append(f"Failed to analyze EDDX content: {e}")
        finally:
            if os.path.exists(temp_eddx.name):
                os.unlink(temp_eddx.name)

    score += content_score
    if labels_found:
        feedback_parts.append(f"Found labels: {', '.join(labels_found)}")
    if terms_found:
        feedback_parts.append(f"Found schema terms: {', '.join(terms_found)}")

    # 4. VLM Verification (40 points)
    # Use trajectory frames + final screenshot (if available from export)
    frames = sample_trajectory_frames(traj, n=4)
    final_img = get_final_screenshot(traj)
    
    # If the agent exported a PNG, we prefer to verify that specific artifact if possible, 
    # but the framework VLM tools work best with the captured trajectory frames.
    # We will use the trajectory frames which show the UI and the work in progress.
    
    images_to_check = frames
    if final_img:
        images_to_check.append(final_img)

    vlm_score = 0
    if images_to_check:
        prompt = """
        You are verifying a task to create a pneumatic circuit diagram in EdrawMax.
        Look at the sequence of images.
        
        Check for:
        1. **Software Usage**: Is the EdrawMax application visible?
        2. **Diagram Structure**: Do you see symbols connected by lines in a schematic layout (not just random boxes)?
        3. **Specific Symbols**: Can you identify standard pneumatic symbols like:
           - A cylinder (rectangle with a rod/piston)
           - A valve (rectangle with internal paths/arrows)
           - An FRL unit (diamond or combined symbol) or Air Source (circle/triangle)
        4. **Labels**: Can you see text labels like "FRL", "SOL", "Clamp", "Air"?
        
        Return JSON:
        {
            "edrawmax_visible": true/false,
            "schematic_layout": true/false,
            "pneumatic_symbols_visible": true/false,
            "labels_visible": true/false,
            "confidence": "low/medium/high"
        }
        """
        
        try:
            vlm_result = query_vlm(prompt=prompt, images=images_to_check)
            parsed = vlm_result.get('parsed', {})
            
            if parsed.get('edrawmax_visible'): vlm_score += 10
            if parsed.get('schematic_layout'): vlm_score += 10
            if parsed.get('pneumatic_symbols_visible'): vlm_score += 10
            if parsed.get('labels_visible'): vlm_score += 10
            
            feedback_parts.append(f"VLM Analysis: {parsed}")
        except Exception as e:
            feedback_parts.append(f"VLM verification failed: {e}")
            # Fallback: give partial credit if file content was perfect
            if content_score >= 30:
                vlm_score = 20
                feedback_parts.append("Awarding partial VLM points based on strong file content.")

    score += vlm_score

    # Final logic
    passed = score >= 60 and eddx_exists and eddx_created
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }