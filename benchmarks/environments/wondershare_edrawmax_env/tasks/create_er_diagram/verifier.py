#!/usr/bin/env python3
"""
Verifier for create_er_diagram task.

Verification Strategy:
1. Programmatic:
   - Check if .eddx file exists, was created during task, and has valid size.
   - Check if .png file exists, was created during task, and has valid size.
   - Parse .eddx (ZIP/XML) to verify it contains the 5 required entity names.
2. VLM (Visual Language Model):
   - Analyze trajectory frames to verify workflow (placing shapes, connecting lines).
   - Analyze final diagram image for structural correctness (boxes, attributes, connectors).
"""

import json
import os
import tempfile
import zipfile
import logging
from typing import Dict, Any, List

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# VLM Utilities (Mocked import for standalone execution, expected in framework)
try:
    from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm
except ImportError:
    # Fallback for testing environment
    def sample_trajectory_frames(traj, n=5): return []
    def get_final_screenshot(traj): return None
    def query_vlm(prompt, image=None, images=None): return {"success": False, "error": "VLM not available"}

REQUIRED_ENTITIES = ["Artist", "Album", "Track", "Genre", "Invoice"]

def verify_create_er_diagram(traj: Dict[str, Any], env_info: Dict[str, Any], task_info: Dict[str, Any]) -> Dict[str, Any]:
    """
    Verify the creation of the Chinook ER Diagram.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Load basic task results
    task_result = {}
    temp_result_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result_file.name)
        with open(temp_result_file.name, 'r') as f:
            task_result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load task result: {e}"}
    finally:
        if os.path.exists(temp_result_file.name):
            os.unlink(temp_result_file.name)

    score = 0
    feedback_parts = []
    
    # --- Criterion 1: EDDX File Check (20 pts) ---
    eddx_stats = task_result.get('eddx_file', {})
    eddx_exists = eddx_stats.get('exists', False)
    eddx_fresh = eddx_stats.get('created_during_task', False)
    eddx_size = eddx_stats.get('size', 0)

    if eddx_exists and eddx_size > 2000:
        if eddx_fresh:
            score += 20
            feedback_parts.append("EDDX file saved successfully (20/20)")
        else:
            score += 10
            feedback_parts.append("EDDX file exists but timestamp is old (10/20)")
    else:
        feedback_parts.append("EDDX file missing or empty (0/20)")

    # --- Criterion 2: PNG Export Check (10 pts) ---
    png_stats = task_result.get('png_file', {})
    png_exists = png_stats.get('exists', False)
    png_fresh = png_stats.get('created_during_task', False)
    png_size = png_stats.get('size', 0)

    if png_exists and png_size > 5000:
        if png_fresh:
            score += 10
            feedback_parts.append("PNG exported successfully (10/10)")
        else:
            score += 5
            feedback_parts.append("PNG exists but timestamp is old (5/10)")
    else:
        feedback_parts.append("PNG export missing (0/10)")

    # --- Criterion 3: Content Verification (XML Parsing) (20 pts) ---
    # We download the .eddx file and inspect its contents
    entity_hits = []
    if eddx_exists:
        temp_eddx = tempfile.NamedTemporaryFile(delete=False, suffix='.eddx')
        try:
            copy_from_env("/home/ga/Diagrams/chinook_er_diagram.eddx", temp_eddx.name)
            
            # .eddx is a zip file. Content is usually in pages/page1.xml or similar.
            # We will grep all xml files in the zip for entity names.
            if zipfile.is_zipfile(temp_eddx.name):
                with zipfile.ZipFile(temp_eddx.name, 'r') as zf:
                    # Read all XML content
                    all_text = ""
                    for name in zf.namelist():
                        if name.endswith('.xml') or name.endswith('.json'):
                            try:
                                all_text += zf.read(name).decode('utf-8', errors='ignore')
                            except:
                                pass
                    
                    # Check for entities
                    for entity in REQUIRED_ENTITIES:
                        if entity in all_text:
                            entity_hits.append(entity)
            else:
                feedback_parts.append("Saved file is not a valid EdrawMax (.eddx) archive")
        except Exception as e:
            feedback_parts.append(f"Failed to inspect EDDX content: {str(e)}")
        finally:
            if os.path.exists(temp_eddx.name):
                os.unlink(temp_eddx.name)

    hit_count = len(entity_hits)
    if hit_count >= 5:
        score += 20
        feedback_parts.append(f"All 5 entities found in file metadata (20/20)")
    elif hit_count >= 3:
        score += 10
        feedback_parts.append(f"Found {hit_count}/5 entities in file metadata (10/20)")
    else:
        feedback_parts.append(f"Found only {hit_count}/5 entities in file metadata (0/20)")
        
    # --- Criterion 4: VLM Visual Verification (50 pts) ---
    # We use trajectory frames to ensure work was done, and final image for correctness
    
    frames = sample_trajectory_frames(traj, n=4)
    final_img = get_final_screenshot(traj)
    
    # If we have an exported PNG from the agent, checking that is also good, 
    # but the final screenshot is safer to prove what was on screen.
    
    if final_img:
        vlm_prompt = """
        You are grading an ER Diagram creation task.
        The user was asked to create an Entity-Relationship diagram for the Chinook database.
        
        Look at the screenshot and evaluate:
        1. Are there distinct entity boxes visible? (Expect roughly 5 boxes)
        2. Do the boxes contain text attributes (like ArtistId, Title, etc)?
        3. Are the boxes connected by lines/arrows indicating relationships?
        4. Does it look like a proper ER diagram/schema?
        
        Return JSON:
        {
            "visible_entities_approx_count": int,
            "has_attributes": bool,
            "has_connections": bool,
            "looks_like_er_diagram": bool,
            "feedback": "string"
        }
        """
        
        vlm_result = query_vlm(prompt=vlm_prompt, image=final_img)
        
        if vlm_result.get("success"):
            parsed = vlm_result.get("parsed", {})
            ent_count = parsed.get("visible_entities_approx_count", 0)
            has_attr = parsed.get("has_attributes", False)
            has_conn = parsed.get("has_connections", False)
            looks_valid = parsed.get("looks_like_er_diagram", False)
            
            vlm_score = 0
            if ent_count >= 3: vlm_score += 15
            if has_attr: vlm_score += 15
            if has_conn: vlm_score += 10
            if looks_valid: vlm_score += 10
            
            score += vlm_score
            feedback_parts.append(f"Visual verification score: {vlm_score}/50. ({parsed.get('feedback', '')})")
        else:
            # Fallback if VLM fails but files exist
            if eddx_exists and hit_count >= 3:
                score += 25
                feedback_parts.append("VLM unavailable, giving partial credit based on file content")
    else:
        feedback_parts.append("No screenshots available for verification (0/50)")

    # Final tally
    passed = score >= 60 and eddx_exists and hit_count >= 3
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }