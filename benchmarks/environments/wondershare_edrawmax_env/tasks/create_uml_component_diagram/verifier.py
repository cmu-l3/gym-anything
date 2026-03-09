#!/usr/bin/env python3
"""
Verifier for create_uml_component_diagram task.

Verification Strategy:
1. File Verification (40 pts):
   - Check if .eddx file exists, is valid zip, and created during task.
   - Check if .png export exists and is valid image.
2. Content Verification (30 pts):
   - Inspect .eddx XML content for required component names.
   - Check for existence of connector/relationship elements.
3. Visual/VLM Verification (30 pts):
   - Use VLM on trajectory/final screenshot to verify:
     - 6 components visible.
     - UML notation (stereotypes, interfaces) used.
     - Dependency arrows drawn.
     - Title present.
"""

import json
import os
import tempfile
import zipfile
import logging
from typing import Dict, Any, List

# Import VLM helpers (mock import pattern for gym_anything environment)
try:
    from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm
except ImportError:
    # Fallback/mock for local testing
    def sample_trajectory_frames(traj, n=5): return []
    def get_final_screenshot(traj): return None
    def query_vlm(prompt, image=None, images=None): return {"success": False, "error": "VLM not available"}

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_uml_component_diagram(traj: Dict[str, Any], env_info: Dict[str, Any], task_info: Dict[str, Any]) -> Dict[str, Any]:
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env not available"}

    metadata = task_info.get('metadata', {})
    required_components = metadata.get('required_components', [])
    
    score = 0
    max_score = 100
    feedback_parts = []
    
    # =========================================================
    # 1. READ RESULT JSON
    # =========================================================
    result = {}
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

    # =========================================================
    # 2. FILE VERIFICATION (40 Points)
    # =========================================================
    eddx_exists = result.get('eddx_exists', False)
    eddx_created = result.get('eddx_created_during_task', False)
    eddx_size = result.get('eddx_size_bytes', 0)
    
    png_exists = result.get('png_exists', False)
    png_created = result.get('png_created_during_task', False)
    png_width = result.get('png_width', 0)

    # EDDX Check (20 pts)
    if eddx_exists and eddx_created and eddx_size > 5000:
        score += 20
        feedback_parts.append("EDDX file created successfully")
    elif eddx_exists:
        score += 5
        feedback_parts.append("EDDX file exists but may be stale or empty")
    else:
        feedback_parts.append("EDDX file NOT found")

    # PNG Check (20 pts)
    if png_exists and png_created and png_width > 400:
        score += 20
        feedback_parts.append("PNG export created successfully")
    elif png_exists:
        score += 5
        feedback_parts.append("PNG exists but may be stale or invalid")
    else:
        feedback_parts.append("PNG export NOT found")

    # =========================================================
    # 3. CONTENT VERIFICATION (30 Points)
    # =========================================================
    # We need to pull the .eddx file to host to inspect XML content
    content_score = 0
    found_components = []
    has_connectors = False
    
    if eddx_exists:
        temp_eddx = tempfile.NamedTemporaryFile(delete=False, suffix='.zip')
        try:
            copy_from_env("/home/ga/Documents/ecommerce_component_diagram.eddx", temp_eddx.name)
            
            # EdrawMax .eddx files are zip archives containing .xml files (pages)
            if zipfile.is_zipfile(temp_eddx.name):
                with zipfile.ZipFile(temp_eddx.name, 'r') as zf:
                    # Aggregate all text from all XML files in the archive
                    all_text = ""
                    for name in zf.namelist():
                        if name.endswith('.xml'):
                            try:
                                all_text += zf.read(name).decode('utf-8', errors='ignore')
                            except:
                                pass
                    
                    # Check for components
                    for comp in required_components:
                        # Simple string check (case insensitive)
                        if comp.lower() in all_text.lower():
                            found_components.append(comp)
                    
                    # Check for connectors (lines/arrows)
                    # Common EdrawMax terms for connectors
                    if 'connector' in all_text.lower() or 'dependency' in all_text.lower() or 'arrow' in all_text.lower():
                        has_connectors = True
            
        except Exception as e:
            feedback_parts.append(f"Content inspection failed: {str(e)}")
        finally:
            if os.path.exists(temp_eddx.name):
                os.unlink(temp_eddx.name)

        # Scoring content
        # 5 points for each component found, up to 25 points
        comp_score = min(25, len(found_components) * 5)
        content_score += comp_score
        if len(found_components) > 0:
            feedback_parts.append(f"Found {len(found_components)}/{len(required_components)} components in file metadata")
        else:
            feedback_parts.append("No component names found in file metadata")

        # 5 points for having connectors
        if has_connectors:
            content_score += 5
            feedback_parts.append("Found connector elements in file")
        
        score += content_score

    # =========================================================
    # 4. VISUAL/VLM VERIFICATION (30 Points)
    # =========================================================
    vlm_score = 0
    
    # Get images: trajectory frames + final screenshot
    frames = sample_trajectory_frames(traj, n=4)
    final_img = get_final_screenshot(traj)
    images_to_check = frames + ([final_img] if final_img else [])
    
    if images_to_check:
        prompt = """
        You are verifying a UML Component Diagram creation task.
        
        Look at the image(s). I need to verify that:
        1. A diagram with multiple box-like shapes (components) is visible.
        2. There are about 6 distinct components.
        3. The components are labeled (e.g., 'API Gateway', 'User Service', 'Order Service').
        4. There are lines/arrows connecting the components (dependency relationships).
        5. There is a title 'E-Commerce Microservices Component Diagram' visible.
        6. UML component notation (small icon in corner of box) or interface symbols (circles/lollipops) are used.
        
        Return JSON:
        {
            "diagram_visible": boolean,
            "component_count_approx": number,
            "labels_readable": boolean,
            "connectors_visible": boolean,
            "title_visible": boolean,
            "uml_notation_used": boolean,
            "confidence": number (0-1)
        }
        """
        
        vlm_result = query_vlm(prompt=prompt, images=images_to_check)
        
        if vlm_result.get("success"):
            parsed = vlm_result.get("parsed", {})
            
            # Scoring VLM
            if parsed.get("diagram_visible"):
                vlm_score += 5
            
            if parsed.get("component_count_approx", 0) >= 4:
                vlm_score += 10
                feedback_parts.append("Visuals: Correct number of components")
            
            if parsed.get("connectors_visible"):
                vlm_score += 5
                feedback_parts.append("Visuals: Connectors visible")
                
            if parsed.get("title_visible"):
                vlm_score += 5
                feedback_parts.append("Visuals: Title visible")
                
            if parsed.get("uml_notation_used"):
                vlm_score += 5
                feedback_parts.append("Visuals: UML notation observed")
        else:
            feedback_parts.append("VLM verification unavailable")
            # Fallback: if EDDX was perfect, grant partial VLM points to avoid penalizing for VLM failure
            if content_score >= 25:
                vlm_score += 15
                feedback_parts.append("Visuals: Skipped (Trusted File Content)")
    
    score += vlm_score

    # Final Pass/Fail
    # Pass if file exists, created during task, and content score is reasonable
    passed = (eddx_exists and eddx_created and score >= 60)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }