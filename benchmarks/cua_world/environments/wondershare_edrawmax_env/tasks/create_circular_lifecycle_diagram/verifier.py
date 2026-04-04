#!/usr/bin/env python3
"""
Verifier for create_circular_lifecycle_diagram task.

Combines programmatic file checks with VLM trajectory analysis.

Criteria:
1. Programmatic: .eddx file exists, is a valid zip, contains required label text (>5KB). (20 pts)
2. Programmatic: .png file exists, valid dimensions (>10KB). (10 pts)
3. Programmatic: Files created during task session. (5 pts)
4. VLM: Circular/Ring layout verification. (25 pts)
5. VLM: Arrows forming a cycle. (20 pts)
6. VLM: All phases labeled correctly and visible in proper order. (20 pts)
"""

import json
import os
import tempfile
import zipfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Try to import VLM helpers if available, otherwise define stubs
try:
    from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
except ImportError:
    # Fallback for local testing or different framework versions
    def sample_trajectory_frames(traj, n=5):
        return []
    def get_final_screenshot(traj):
        return None

def verify_create_circular_lifecycle_diagram(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    required_labels = metadata.get('required_labels', [])
    
    score = 0
    feedback_parts = []
    
    # ------------------------------------------------------------------
    # 1. Retrieve and Check Result JSON (Programmatic Basic Checks)
    # ------------------------------------------------------------------
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    # Check EDDX existence and size
    eddx_exists = result.get('eddx_exists', False)
    eddx_size = result.get('eddx_size', 0)
    eddx_new = result.get('eddx_is_new', False)
    
    # Check PNG existence and size
    png_exists = result.get('png_exists', False)
    png_size = result.get('png_size', 0)
    png_new = result.get('png_is_new', False)
    png_width = result.get('png_width', 0)
    
    # Mandatory Gate: Both files must exist and be reasonable size
    if not eddx_exists or eddx_size < 5000:
        return {"passed": False, "score": score, "feedback": "FAIL: Source .eddx file missing or empty."}
    if not png_exists or png_size < 10000:
        return {"passed": False, "score": score, "feedback": "FAIL: Exported .png file missing or empty."}

    # Files exist score
    score += 10 # Basic existence
    feedback_parts.append("Files exist")
    
    # Timestamp check (Anti-gaming)
    if eddx_new and png_new:
        score += 5
        feedback_parts.append("Files created during task")
    else:
        feedback_parts.append("Warning: Files have old timestamps")

    # PNG Dimensions check
    if png_width >= 400:
        score += 5
        feedback_parts.append("PNG dimensions valid")
    
    # ------------------------------------------------------------------
    # 2. Deep Content Check of EDDX (Programmatic Text Verification)
    # ------------------------------------------------------------------
    # Retrieve the actual EDDX file to check XML content for labels
    temp_eddx = tempfile.NamedTemporaryFile(delete=False, suffix='.eddx')
    try:
        copy_from_env("/home/ga/Documents/sdlc_lifecycle.eddx", temp_eddx.name)
        
        found_labels = 0
        is_valid_zip = False
        
        if zipfile.is_zipfile(temp_eddx.name):
            is_valid_zip = True
            try:
                with zipfile.ZipFile(temp_eddx.name, 'r') as zf:
                    # Search all XML files in the archive
                    all_text = ""
                    for name in zf.namelist():
                        if name.endswith('.xml'):
                            all_text += zf.read(name).decode('utf-8', errors='ignore')
                    
                    # Check for required SDLC phases
                    for label in required_labels:
                        if label in all_text:
                            found_labels += 1
                    
                    # Check for title
                    if "Software Development Life Cycle" in all_text:
                        found_labels += 1 # Bonus point for title text
            except Exception as e:
                feedback_parts.append(f"Error reading EDDX content: {e}")
        
        if is_valid_zip:
            # Score based on found text labels (max 10 points)
            # 6 phases + 1 title = 7 items.
            label_score = min(10, int((found_labels / 7) * 10))
            score += label_score
            feedback_parts.append(f"Found {found_labels}/7 text labels in file")
        else:
            feedback_parts.append("EDDX is not a valid zip archive")
            
    except Exception as e:
        feedback_parts.append(f"Failed to inspect EDDX file: {e}")
    finally:
        if os.path.exists(temp_eddx.name):
            os.unlink(temp_eddx.name)

    # ------------------------------------------------------------------
    # 3. VLM Verification (Visual Structure)
    # ------------------------------------------------------------------
    # We need to verify the CIRCULAR layout and ARROWS, which XML parsing is bad at.
    
    query_vlm = env_info.get('query_vlm')
    if query_vlm:
        # Get trajectory frames to prove work process
        frames = sample_trajectory_frames(traj, n=4)
        final_img = get_final_screenshot(traj)
        
        if final_img:
            frames.append(final_img)
            
            prompt = """
            You are verifying a diagram created in EdrawMax.
            The user was tasked to create a 'Software Development Life Cycle' (SDLC) diagram.
            
            Look at the final screenshot (and history) and check for:
            1. CIRCULAR LAYOUT: Are the shapes arranged in a ring/circle? (Not a list/line)
            2. ARROWS: Are there directional arrows connecting the shapes in a loop?
            3. PHASES: Can you see labels like 'Requirements', 'Design', 'Implementation', 'Testing', 'Deployment', 'Maintenance'?
            4. TITLE: Is there a visible title 'Software Development Life Cycle'?
            
            Return JSON:
            {
                "is_circular": boolean,
                "has_cycle_arrows": boolean,
                "labels_visible": boolean,
                "title_visible": boolean,
                "confidence": "high/medium/low"
            }
            """
            
            try:
                vlm_resp = query_vlm(prompt=prompt, images=frames)
                if vlm_resp.get('success'):
                    parsed = vlm_resp.get('parsed', {})
                    
                    # Circular Layout (25 pts)
                    if parsed.get('is_circular', False):
                        score += 25
                        feedback_parts.append("VLM: Circular layout confirmed")
                    
                    # Arrows (20 pts)
                    if parsed.get('has_cycle_arrows', False):
                        score += 20
                        feedback_parts.append("VLM: Cycle arrows confirmed")
                        
                    # Visual confirmation of labels (15 pts)
                    if parsed.get('labels_visible', False):
                        score += 15
                        feedback_parts.append("VLM: Labels visually confirmed")
                        
                    # Title visual (10 pts)
                    if parsed.get('title_visible', False):
                        score += 10
                        feedback_parts.append("VLM: Title visually confirmed")
                        
            except Exception as e:
                feedback_parts.append(f"VLM verification failed: {e}")
                # Fallback: if VLM fails but programmatic text checks passed, give partial credit?
                # We'll just rely on what we have.
    else:
        feedback_parts.append("VLM function missing, skipping visual verification")

    # Normalize score to max 100
    score = min(100, score)
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }