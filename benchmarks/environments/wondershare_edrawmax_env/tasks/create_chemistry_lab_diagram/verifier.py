#!/usr/bin/env python3
"""
Verifier for create_chemistry_lab_diagram task.

Verification Strategy:
1. File Existence (20 pts): Check if .eddx and .png files exist and were created during the task.
2. Content Analysis (30 pts): Unzip the .eddx file and parse XML to find:
   - Specific text labels (Bunsen Burner, Condenser, etc.)
   - Shape keywords indicating chemistry library usage.
3. VLM Verification (50 pts): Use Vision-Language Model to analyze the diagram's visual structure:
   - Is it a distillation setup?
   - Are components connected correctly?
   - Are labels legible?
"""

import json
import os
import tempfile
import zipfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_chemistry_lab_diagram(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    required_labels = metadata.get('required_labels', [])
    required_shapes = metadata.get('required_shapes', [])
    
    score = 0
    feedback_parts = []
    
    # =========================================================
    # 1. Load Result JSON & File Verification
    # =========================================================
    temp_result_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result_file.name)
        with open(temp_result_file.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {e}"}
    finally:
        if os.path.exists(temp_result_file.name):
            os.unlink(temp_result_file.name)

    eddx_exists = result_data.get('eddx_exists', False)
    eddx_fresh = result_data.get('eddx_created_during_task', False)
    png_exists = result_data.get('png_exists', False)
    png_fresh = result_data.get('png_created_during_task', False)
    
    if eddx_exists and eddx_fresh:
        score += 10
        feedback_parts.append("EDDX file created.")
    else:
        feedback_parts.append("EDDX file missing or stale.")

    if png_exists and png_fresh:
        score += 10
        feedback_parts.append("PNG export created.")
    else:
        feedback_parts.append("PNG export missing or stale.")

    # Early exit if no files
    if not eddx_exists:
        return {"passed": False, "score": score, "feedback": " | ".join(feedback_parts)}

    # =========================================================
    # 2. Programmatic Content Analysis (EDDX parsing)
    # =========================================================
    temp_eddx = tempfile.NamedTemporaryFile(delete=False, suffix='.eddx')
    try:
        copy_from_env("/home/ga/Documents/distillation_setup.eddx", temp_eddx.name)
        
        found_labels = []
        found_shapes = []
        
        with zipfile.ZipFile(temp_eddx.name, 'r') as zf:
            # EdrawMax files store data in page*.xml files usually
            xml_files = [n for n in zf.namelist() if n.endswith('.xml')]
            
            full_text_content = ""
            for xml_file in xml_files:
                try:
                    content = zf.read(xml_file).decode('utf-8', errors='ignore')
                    full_text_content += content
                except:
                    continue
            
            # Check for labels
            for label in required_labels:
                # Simple substring check (case-insensitive)
                if label.lower() in full_text_content.lower():
                    found_labels.append(label)
            
            # Check for shapes (looking for shape names/types in XML)
            for shape_kw in required_shapes:
                if shape_kw.lower() in full_text_content.lower():
                    found_shapes.append(shape_kw)

        # Scoring Content
        label_score = min(20, int((len(found_labels) / len(required_labels)) * 20))
        shape_score = min(10, int((len(found_shapes) / len(required_shapes)) * 10))
        
        score += label_score + shape_score
        
        if len(found_labels) > 0:
            feedback_parts.append(f"Found {len(found_labels)}/{len(required_labels)} labels.")
        else:
            feedback_parts.append("No required labels found in file.")
            
        if len(found_shapes) > 0:
            feedback_parts.append(f"Found chemistry shapes: {', '.join(found_shapes)}.")

    except zipfile.BadZipFile:
        feedback_parts.append("EDDX file is not a valid zip archive.")
    except Exception as e:
        feedback_parts.append(f"Error parsing EDDX file: {str(e)}")
    finally:
        if os.path.exists(temp_eddx.name):
            os.unlink(temp_eddx.name)

    # =========================================================
    # 3. VLM Verification
    # =========================================================
    
    # We use the exported PNG if available, otherwise the final screenshot from the framework
    # Ideally, we look at the PNG exported by the agent as it's the direct output.
    image_to_verify = None
    
    if png_exists and png_fresh:
        # Pull the PNG from environment
        temp_png = tempfile.NamedTemporaryFile(delete=False, suffix='.png')
        try:
            copy_from_env("/home/ga/Documents/distillation_setup.png", temp_png.name)
            image_to_verify = temp_png.name
        except:
            pass
    
    # Fallback to framework screenshot if export failed
    if not image_to_verify:
        image_to_verify = get_final_screenshot(traj)

    if image_to_verify:
        prompt = """
        You are a chemistry teacher grading a diagram of a distillation setup created by a student.
        
        Please verify the following:
        1. Is there a Bunsen burner (or heat source) at the bottom?
        2. Is there a flask sitting above the heat source?
        3. Is there a long condenser tube connected to the flask, sloping downwards?
        4. Is there a collection vessel (beaker/flask) at the end of the condenser?
        5. Are there text labels visible pointing to these parts?
        6. Does the setup look physically connected (not just random floating objects)?
        
        Return a JSON object with:
        {
            "has_burner": true/false,
            "has_flask": true/false,
            "has_condenser": true/false,
            "has_collection_vessel": true/false,
            "labels_visible": true/false,
            "physically_connected": true/false,
            "overall_quality": "low/medium/high"
        }
        """
        
        try:
            vlm_result = query_vlm(prompt=prompt, image=image_to_verify)
            
            if vlm_result.get('success'):
                parsed = vlm_result.get('parsed', {})
                
                vlm_score = 0
                checks = ['has_burner', 'has_flask', 'has_condenser', 'has_collection_vessel', 'labels_visible', 'physically_connected']
                for check in checks:
                    if parsed.get(check, False):
                        vlm_score += 8  # 6 checks * 8 = 48 pts max (capped at 50 total with quality)
                
                if parsed.get('overall_quality') in ['medium', 'high']:
                    vlm_score += 2
                    
                score += vlm_score
                feedback_parts.append(f"VLM Visual Score: {vlm_score}/50. Quality: {parsed.get('overall_quality', 'unknown')}.")
            else:
                feedback_parts.append("VLM verification failed to run.")
                
        except Exception as e:
            logger.error(f"VLM error: {e}")
            feedback_parts.append("VLM verification error.")
            
        # Cleanup temp png if used
        if png_exists and png_fresh and os.path.exists(temp_png.name):
            os.unlink(temp_png.name)
    else:
        feedback_parts.append("No image available for visual verification.")

    # =========================================================
    # Final Result
    # =========================================================
    
    # Total Score Calculation
    # File check: 20
    # Content check: 30
    # VLM check: 50
    # Total: 100
    
    final_score = min(100, score)
    passed = final_score >= 70
    
    return {
        "passed": passed,
        "score": final_score,
        "feedback": " | ".join(feedback_parts)
    }