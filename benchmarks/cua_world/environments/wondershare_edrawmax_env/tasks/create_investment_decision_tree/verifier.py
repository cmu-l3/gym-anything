#!/usr/bin/env python3
"""
Verifier for create_investment_decision_tree task.

Multi-criteria verification:
1. File Existence: Checks for .eddx and .png creation.
2. Anti-Gaming: Checks file timestamps against task start.
3. Content Verification: Unzips .eddx (which is XML-based) to search for required text labels.
4. Visual Verification: Uses VLM on trajectory frames to confirm tree structure.
"""

import json
import os
import tempfile
import zipfile
import logging
from typing import Dict, Any

# VLM Utilities (Mock or Import)
try:
    from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm
except ImportError:
    # Fallback if running outside framework
    def sample_trajectory_frames(traj, n=5): return []
    def get_final_screenshot(traj): return None
    def query_vlm(**kwargs): return {"success": False, "error": "VLM not available"}

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_investment_decision_tree(traj, env_info, task_info):
    """
    Verifies the investment decision tree task.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    required_text = metadata.get('required_text', [])
    
    score = 0
    feedback_parts = []
    
    # =========================================================
    # 1. Retrieve Result JSON
    # =========================================================
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task result: {str(e)}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    # =========================================================
    # 2. File Verification (40 pts)
    # =========================================================
    eddx_exists = result_data.get('eddx_exists', False)
    eddx_fresh = result_data.get('eddx_created_during_task', False)
    png_exists = result_data.get('png_exists', False)
    png_fresh = result_data.get('png_created_during_task', False)
    eddx_size = result_data.get('eddx_size_bytes', 0)

    if eddx_exists and eddx_fresh:
        score += 20
        feedback_parts.append("EDDX project file created.")
        if eddx_size < 1000: # Empty file check
            score -= 10
            feedback_parts.append("Warning: EDDX file seems surprisingly small.")
    elif eddx_exists:
        score += 5
        feedback_parts.append("EDDX file exists but was not modified during task (stale).")
    else:
        feedback_parts.append("EDDX project file missing.")

    if png_exists and png_fresh:
        score += 20
        feedback_parts.append("PNG export created.")
    elif png_exists:
        score += 5
        feedback_parts.append("PNG file exists but was not modified during task.")
    else:
        feedback_parts.append("PNG export missing.")

    # =========================================================
    # 3. Content Verification (Text in EDDX) (30 pts)
    # =========================================================
    text_score = 0
    content_feedback = []
    
    if eddx_exists:
        temp_eddx = tempfile.NamedTemporaryFile(delete=False, suffix='.zip')
        try:
            copy_from_env(result_data.get('eddx_path'), temp_eddx.name)
            
            # EdrawMax files are zip archives containing XML
            found_text = set()
            try:
                with zipfile.ZipFile(temp_eddx.name, 'r') as z:
                    # Search all XML files in the archive
                    for filename in z.namelist():
                        if filename.endswith('.xml'):
                            content = z.read(filename).decode('utf-8', errors='ignore')
                            for term in required_text:
                                if term.lower() in content.lower():
                                    found_text.add(term)
                
                # Calculate score based on found terms
                found_count = len(found_text)
                total_required = len(required_text)
                
                if total_required > 0:
                    text_score = int(30 * (found_count / total_required))
                    content_feedback.append(f"Found {found_count}/{total_required} required text labels.")
                
                score += text_score
                
            except zipfile.BadZipFile:
                feedback_parts.append("EDDX file is not a valid zip archive.")
        except Exception as e:
            feedback_parts.append(f"Error analyzing EDDX content: {str(e)}")
        finally:
            if os.path.exists(temp_eddx.name):
                os.unlink(temp_eddx.name)
        
        if content_feedback:
            feedback_parts.extend(content_feedback)

    # =========================================================
    # 4. VLM Verification (Trajectory Analysis) (30 pts)
    # =========================================================
    # Use multiple frames to verify the *process* of creating the diagram
    frames = sample_trajectory_frames(traj, n=4)
    final_screen = get_final_screenshot(traj)
    
    if frames and final_screen:
        prompt = """
        You are verifying an agent's task to create an investment decision tree diagram.
        The diagram should have:
        1. A root node labeled "Strategy".
        2. Two branches: "Build In-house" and "Buy Vendor Sol."
        3. Financial outcomes like "$50,000" or "$150,000".
        4. A tree-like structure (nodes connected by lines).
        
        Look at the sequence of images.
        - Do you see a diagram being built?
        - Does the final image show a decision tree structure?
        - Can you see any of the specific labels mentioned above?
        
        Return JSON with:
        {
            "is_decision_tree": boolean,
            "has_correct_labels": boolean,
            "visible_labels": [list of strings found],
            "score": int (0-30, based on visual completeness)
        }
        """
        
        vlm_response = query_vlm(images=frames + [final_screen], prompt=prompt)
        
        if vlm_response and vlm_response.get("success"):
            parsed = vlm_response.get("parsed", {})
            vlm_score = parsed.get("score", 0)
            # Clamp score
            vlm_score = max(0, min(30, vlm_score))
            score += vlm_score
            
            feedback_parts.append(f"Visual verification score: {vlm_score}/30")
            if parsed.get("visible_labels"):
                feedback_parts.append(f"VLM saw labels: {', '.join(parsed['visible_labels'][:5])}...")
        else:
            # Fallback if VLM fails: award partial points if files exist and have content
            if eddx_size > 5000:
                score += 15
                feedback_parts.append("VLM unavailable, awarding partial points for non-empty file.")

    # =========================================================
    # Final Result
    # =========================================================
    
    # Pass threshold: 60 points + EDDX file must exist
    passed = (score >= 60) and eddx_exists and eddx_fresh
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }