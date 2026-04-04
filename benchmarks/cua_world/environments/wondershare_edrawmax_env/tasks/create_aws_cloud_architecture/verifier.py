#!/usr/bin/env python3
"""
Verifier for create_aws_cloud_architecture task.

Strategy:
1. File Verification (40 pts):
   - Check if .eddx and .png files exist and were created during the task.
   - Check file sizes to ensure they aren't empty/trivial.
2. Content Verification (30 pts):
   - Inspect internal XML of .eddx for required keywords (VPC, EC2, RDS, etc.).
3. Visual Verification (VLM) (30 pts):
   - Analyze the exported PNG and trajectory to ensure logical layout and valid workflow.
"""

import json
import os
import tempfile
import zipfile
import logging
from gym_anything.vlm import query_vlm, get_final_screenshot, sample_trajectory_frames

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_aws_cloud_architecture(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    required_keywords = set(k.lower() for k in metadata.get('required_keywords', []))
    min_keywords_pass = metadata.get('passing_threshold_keywords', 5)

    # 1. Retrieve Result JSON
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task result: {e}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    score = 0
    feedback_parts = []
    
    # ---------------------------------------------------------
    # Criterion 1: File Existence & Anti-Gaming (40 pts)
    # ---------------------------------------------------------
    eddx_ok = result.get("eddx_exists") and result.get("eddx_created_during_task") and result.get("eddx_size", 0) > 1000
    png_ok = result.get("png_exists") and result.get("png_created_during_task") and result.get("png_size", 0) > 5000

    if eddx_ok:
        score += 20
        feedback_parts.append("EDDX source file created successfully.")
    else:
        feedback_parts.append("EDDX file missing, too small, or not created during task.")

    if png_ok:
        score += 20
        feedback_parts.append("PNG export created successfully.")
    else:
        feedback_parts.append("PNG export missing, too small, or not created during task.")

    # ---------------------------------------------------------
    # Criterion 2: Content Verification (XML Keywords) (30 pts)
    # ---------------------------------------------------------
    keywords_found = set()
    
    if eddx_ok:
        # Retrieve the EDDX file to analyze content
        temp_eddx = tempfile.NamedTemporaryFile(delete=False, suffix='.eddx')
        try:
            copy_from_env(result["eddx_path"], temp_eddx.name)
            
            # EDDX is a ZIP. Extract XML content and search for text.
            if zipfile.is_zipfile(temp_eddx.name):
                with zipfile.ZipFile(temp_eddx.name, 'r') as zf:
                    for filename in zf.namelist():
                        if filename.endswith('.xml'):
                            try:
                                content = zf.read(filename).decode('utf-8', errors='ignore').lower()
                                for kw in required_keywords:
                                    if kw in content:
                                        keywords_found.add(kw)
                            except:
                                continue
            
            found_count = len(keywords_found)
            feedback_parts.append(f"Found {found_count} required component labels in diagram.")
            
            # Score based on coverage
            if found_count >= min_keywords_pass:
                score += 30
            elif found_count > 0:
                score += int(30 * (found_count / min_keywords_pass))
            else:
                feedback_parts.append("Diagram seems empty of required text labels.")
                
        except Exception as e:
            feedback_parts.append(f"Error analyzing EDDX content: {e}")
        finally:
            if os.path.exists(temp_eddx.name):
                os.unlink(temp_eddx.name)
    
    # ---------------------------------------------------------
    # Criterion 3: Visual Verification (VLM) (30 pts)
    # ---------------------------------------------------------
    # We verify the PNG output if available, else fallback to final screenshot
    
    vlm_image_path = None
    if png_ok:
        # Fetch the PNG export
        temp_png = tempfile.NamedTemporaryFile(delete=False, suffix='.png')
        try:
            copy_from_env(result["png_path"], temp_png.name)
            vlm_image_path = temp_png.name
        except:
            vlm_image_path = None

    # VLM Prompt
    prompt = """
    You are evaluating an AWS Cloud Architecture diagram created in EdrawMax.
    
    The diagram SHOULD contain:
    1. A VPC boundary (large box) containing subnets.
    2. Cloud infrastructure icons: EC2 (servers), RDS (database), S3 (bucket), CloudFront.
    3. Arrows connecting these components in a flow.
    4. Text labels identifying "Public Subnet", "Private Subnet", "Web Server", "App Server", etc.
    
    Analyze the image:
    - Does it look like a cloud architecture diagram?
    - Are there grouped components (subnets/VPC)?
    - Are the required components (EC2, RDS, S3) visible?
    
    Return JSON:
    {
        "is_cloud_diagram": true/false,
        "has_vpc_structure": true/false,
        "components_visible": ["list", "of", "found", "items"],
        "quality_score_0_to_10": int
    }
    """
    
    vlm_score = 0
    try:
        # Use the exported PNG if available, otherwise trajectory final frame
        image_to_check = vlm_image_path if vlm_image_path else get_final_screenshot(traj)
        
        if image_to_check:
            vlm_resp = query_vlm(prompt=prompt, image=image_to_check)
            if vlm_resp.get("success"):
                parsed = vlm_resp.get("parsed", {})
                
                if parsed.get("is_cloud_diagram"):
                    vlm_score += 10
                if parsed.get("has_vpc_structure"):
                    vlm_score += 10
                
                # Quality points
                quality = parsed.get("quality_score_0_to_10", 0)
                vlm_score += quality  # Max 10 pts
                
                feedback_parts.append(f"VLM Analysis: {parsed.get('components_visible')}")
            else:
                feedback_parts.append("VLM analysis failed.")
        else:
            feedback_parts.append("No image available for VLM analysis.")
            
    except Exception as e:
        feedback_parts.append(f"VLM error: {e}")
    finally:
        if vlm_image_path and os.path.exists(vlm_image_path):
            os.unlink(vlm_image_path)
            
    score += vlm_score
    
    # ---------------------------------------------------------
    # Final Scoring
    # ---------------------------------------------------------
    # Pass if:
    # 1. Both files exist (40 pts base)
    # 2. At least some correct content found (keywords or VLM)
    # 3. Total score >= 60
    
    passed = (eddx_ok and png_ok) and (score >= 60)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }