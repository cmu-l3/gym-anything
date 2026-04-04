#!/usr/bin/env python3
"""
Verifier for create_timeline_diagram task.

Checks:
1. .eddx file existence, validity, and content (text search in XML).
2. .png file existence and dimensions.
3. VLM verification of the visual timeline structure.
"""

import os
import json
import tempfile
import zipfile
import logging
import sys

# Add parent directory to path to import vlm_utils if needed, 
# though we usually use the helper provided in the prompt context if available.
# Here we will implement self-contained VLM logic or use the gym_anything provided one.
try:
    from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm
except ImportError:
    # Fallback for testing environments
    def sample_trajectory_frames(traj, n=5): return []
    def get_final_screenshot(traj): return None
    def query_vlm(**kwargs): return {"success": False, "error": "VLM not available"}

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_timeline_diagram(traj, env_info, task_info):
    """
    Verify the creation of the IT Migration Timeline.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    required_phases = metadata.get('required_text_phases', [])
    required_milestones = metadata.get('required_text_milestones', [])
    required_year = metadata.get('required_year', "2025")

    # Load result JSON
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
    # Criterion 1: EDDX File Check (40 points)
    # ---------------------------------------------------------
    eddx_exists = result_data.get("eddx_exists", False)
    eddx_created = result_data.get("eddx_created_during_task", False)
    eddx_size = result_data.get("eddx_size_bytes", 0)

    xml_content = ""
    eddx_valid = False

    if eddx_exists:
        if eddx_size > 2000: # Minimum size for non-empty file
            # Retrieve the file to check content
            temp_eddx = tempfile.NamedTemporaryFile(delete=False, suffix='.eddx')
            try:
                copy_from_env("/home/ga/Documents/migration_timeline.eddx", temp_eddx.name)
                
                if zipfile.is_zipfile(temp_eddx.name):
                    eddx_valid = True
                    try:
                        with zipfile.ZipFile(temp_eddx.name, 'r') as zf:
                            # EdrawMax text is usually in page xml files
                            for name in zf.namelist():
                                if name.endswith('.xml'):
                                    try:
                                        xml_content += zf.read(name).decode('utf-8', errors='ignore')
                                    except:
                                        pass
                    except Exception as e:
                        logger.error(f"Error reading eddx zip: {e}")
                
            except Exception as e:
                logger.error(f"Failed to copy eddx file: {e}")
            finally:
                if os.path.exists(temp_eddx.name):
                    os.unlink(temp_eddx.name)
        
        if eddx_valid and eddx_created:
            score += 15
            feedback_parts.append("Valid .eddx file created")
            
            # Check for content keywords in XML
            found_phases = 0
            for phase in required_phases:
                if phase.lower() in xml_content.lower():
                    found_phases += 1
            
            found_milestones = 0
            for mile in required_milestones:
                if mile.lower() in xml_content.lower():
                    found_milestones += 1
            
            year_found = required_year in xml_content
            
            # Scoring for content
            # Expecting roughly most phases and milestones to be found
            if found_phases >= 3: score += 10
            if found_milestones >= 4: score += 10
            if year_found: score += 5
            
            feedback_parts.append(f"Content check: Found {found_phases} phase terms and {found_milestones} milestones")
        else:
            feedback_parts.append("EDDX file invalid or not created during task")
    else:
        feedback_parts.append("EDDX file not found")

    # ---------------------------------------------------------
    # Criterion 2: PNG Export Check (20 points)
    # ---------------------------------------------------------
    png_exists = result_data.get("png_exists", False)
    png_created = result_data.get("png_created_during_task", False)
    png_width = result_data.get("png_width", 0)

    if png_exists and png_created:
        if png_width >= 1200:
            score += 20
            feedback_parts.append(f"Valid PNG export found (width: {png_width}px)")
        else:
            score += 10
            feedback_parts.append(f"PNG export found but resolution low ({png_width}px)")
    else:
        feedback_parts.append("PNG export not found or not created during task")

    # ---------------------------------------------------------
    # Criterion 3: VLM Verification (40 points)
    # ---------------------------------------------------------
    # Use trajectory frames to verify the process and the final outcome
    frames = sample_trajectory_frames(traj, n=4)
    final_img = get_final_screenshot(traj)
    
    # We add the final result PNG if available, or just use the screenshot
    images_to_analyze = frames + ([final_img] if final_img else [])

    if images_to_analyze:
        prompt = """
        You are verifying an agent's work in Wondershare EdrawMax.
        The goal was to create a "Cloud ERP Migration Roadmap 2025" timeline diagram.
        
        Look at the images provided (trajectory of actions).
        
        1. Does the final state or the work in progress show a 'Timeline' or 'Roadmap' type diagram? (Horizontal or vertical sequence of events/phases).
        2. Can you see text related to migration phases like 'Assessment', 'Data Migration', 'Go-Live'?
        3. Can you see text related to dates in 2025?
        4. Did the agent seem to be using the EdrawMax interface (dragging shapes, typing text)?
        
        Return JSON:
        {
            "is_timeline_diagram": boolean,
            "contains_migration_text": boolean,
            "contains_2025_dates": boolean,
            "interface_usage_valid": boolean,
            "confidence": "high/medium/low"
        }
        """
        
        vlm_res = query_vlm(prompt=prompt, images=images_to_analyze)
        
        if vlm_res.get("success"):
            parsed = vlm_res.get("parsed", {})
            vlm_score = 0
            if parsed.get("is_timeline_diagram"): vlm_score += 10
            if parsed.get("contains_migration_text"): vlm_score += 10
            if parsed.get("contains_2025_dates"): vlm_score += 10
            if parsed.get("interface_usage_valid"): vlm_score += 10
            
            score += vlm_score
            feedback_parts.append(f"VLM verification score: {vlm_score}/40")
        else:
            feedback_parts.append("VLM verification failed to execute")
            # Fallback: if EDDX was very strong, give partial credit, else 0
            if score >= 40: score += 20 

    # ---------------------------------------------------------
    # Final Decision
    # ---------------------------------------------------------
    passed = score >= 60
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }