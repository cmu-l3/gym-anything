#!/usr/bin/env python3
"""
Verifier for create_business_model_canvas task.

Verification Strategy:
1. File Verification (40 points):
   - Check if .eddx file exists and was created during task
   - Check if .png file exists and was created during task
2. Content Verification (30 points):
   - Inspect .eddx XML content for specific keywords required in the task
3. Visual Verification (30 points):
   - Use VLM to analyze the exported PNG or final screenshot
   - Check for BMC grid layout and populated text
"""

import json
import os
import tempfile
import zipfile
import logging
import sys
from gym_anything.vlm import query_vlm, get_final_screenshot

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_business_model_canvas(traj, env_info, task_info):
    """
    Verify that the Business Model Canvas was created, populated, saved, and exported.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_eddx_path = metadata.get('expected_eddx_path', '/home/ga/Documents/fraud_shield_bmc.eddx')
    expected_png_path = metadata.get('expected_png_path', '/home/ga/Documents/fraud_shield_bmc.png')
    required_strings = metadata.get('required_strings', ["FraudShield", "99.7%", "AWS"])
    
    score = 0
    feedback_parts = []
    
    # Load task result
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load task result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    # 1. File Verification (40 pts)
    # ---------------------------------------------------------
    eddx_exists = result.get('eddx_exists', False)
    eddx_fresh = result.get('eddx_created_during_task', False)
    eddx_size = result.get('eddx_size_bytes', 0)
    
    png_exists = result.get('png_exists', False)
    png_fresh = result.get('png_created_during_task', False)
    png_size = result.get('png_size_bytes', 0)

    if eddx_exists and eddx_fresh and eddx_size > 5000:
        score += 20
        feedback_parts.append("EDDX file saved correctly")
    elif eddx_exists:
        score += 5
        feedback_parts.append("EDDX file exists but may be stale or empty")
    else:
        feedback_parts.append("EDDX file missing")

    if png_exists and png_fresh and png_size > 10000:
        score += 20
        feedback_parts.append("PNG export successful")
    elif png_exists:
        score += 5
        feedback_parts.append("PNG file exists but may be stale or empty")
    else:
        feedback_parts.append("PNG export missing")

    # 2. Content Verification (XML Parsing) (30 pts)
    # ---------------------------------------------------------
    content_matches = 0
    total_required = len(required_strings)
    
    if eddx_exists:
        temp_eddx = tempfile.NamedTemporaryFile(delete=False, suffix='.eddx')
        try:
            copy_from_env(expected_eddx_path, temp_eddx.name)
            
            # .eddx is a zip file. We search all XML files inside it.
            if zipfile.is_zipfile(temp_eddx.name):
                with zipfile.ZipFile(temp_eddx.name, 'r') as zf:
                    all_text = ""
                    for name in zf.namelist():
                        if name.endswith('.xml'):
                            try:
                                all_text += zf.read(name).decode('utf-8', errors='ignore')
                            except:
                                pass
                    
                    # Check for keywords
                    found_keywords = []
                    for keyword in required_strings:
                        if keyword.lower() in all_text.lower():
                            content_matches += 1
                            found_keywords.append(keyword)
                    
                    if content_matches > 0:
                        # Normalize score to max 30
                        content_score = int((content_matches / total_required) * 30)
                        score += content_score
                        feedback_parts.append(f"Content check: Found {content_matches}/{total_required} keywords")
                        if content_matches < total_required:
                            missing = [k for k in required_strings if k not in found_keywords]
                            feedback_parts.append(f"Missing keywords: {', '.join(missing[:3])}...")
                    else:
                        feedback_parts.append("Content check: No required text found in diagram")
            else:
                feedback_parts.append("EDDX file is not a valid zip archive")
                
        except Exception as e:
            feedback_parts.append(f"Failed to inspect EDDX content: {e}")
        finally:
            if os.path.exists(temp_eddx.name):
                os.unlink(temp_eddx.name)

    # 3. Visual Verification (VLM) (30 pts)
    # ---------------------------------------------------------
    # Prefer the exported PNG if it exists, otherwise use final screenshot
    image_to_check = None
    
    if png_exists and png_size > 1000:
        # Check exported PNG
        temp_png = tempfile.NamedTemporaryFile(delete=False, suffix='.png')
        try:
            copy_from_env(expected_png_path, temp_png.name)
            image_to_check = temp_png.name
        except Exception as e:
            logger.warning(f"Could not retrieve exported PNG for VLM: {e}")
            if os.path.exists(temp_png.name):
                os.unlink(temp_png.name)

    # Fallback to final screenshot
    if not image_to_check:
        image_to_check = get_final_screenshot(traj)

    if image_to_check:
        prompt = """
        Analyze this image. It should be a Business Model Canvas (BMC) diagram for 'FraudShield AI'.
        
        Check for:
        1. A grid layout typical of a Business Model Canvas (9 sections).
        2. Specific section headers like 'Key Partners', 'Value Propositions', 'Revenue Streams', etc.
        3. A title containing 'FraudShield'.
        4. Text content populated in the boxes (not empty placeholders).
        
        Return JSON:
        {
            "is_bmc_layout": true/false,
            "has_fraudshield_title": true/false,
            "sections_populated": true/false,
            "score_0_to_10": <int>
        }
        """
        
        try:
            vlm_res = query_vlm(prompt=prompt, image=image_to_check)
            if vlm_res.get('success'):
                parsed = vlm_res.get('parsed', {})
                vlm_score = parsed.get('score_0_to_10', 0)
                
                # Scale 0-10 score to 30 points
                visual_points = vlm_score * 3
                score += visual_points
                
                checks = []
                if parsed.get('is_bmc_layout'): checks.append("Layout OK")
                if parsed.get('has_fraudshield_title'): checks.append("Title OK")
                if parsed.get('sections_populated'): checks.append("Content visible")
                
                feedback_parts.append(f"Visual check: {', '.join(checks)} ({visual_points}/30 pts)")
            else:
                feedback_parts.append("VLM analysis failed")
                
        except Exception as e:
            feedback_parts.append(f"VLM error: {e}")
        finally:
            # Cleanup temp png if we created one
            if image_to_check and image_to_check.endswith('.png') and os.path.dirname(image_to_check).startswith('/tmp'):
                if os.path.exists(image_to_check):
                    try:
                        os.unlink(image_to_check)
                    except:
                        pass
    else:
        feedback_parts.append("No image available for visual verification")

    # Final tally
    passed = score >= 60 and eddx_exists and content_matches >= 3
    
    return {
        "passed": passed,
        "score": min(100, score),
        "feedback": " | ".join(feedback_parts)
    }