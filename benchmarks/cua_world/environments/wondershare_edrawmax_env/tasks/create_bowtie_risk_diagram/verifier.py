#!/usr/bin/env python3
"""
Verifier for create_bowtie_risk_diagram task.

Criteria:
1. File Creation: .eddx and .pdf files exist and were created during the task.
2. Content Verification (Programmatic): Unzip .eddx and check for required text labels.
3. Visual Verification (VLM): Check if the layout follows the BowTie structure (Threats -> Event -> Consequences).
"""

import os
import json
import zipfile
import tempfile
import logging
import sys

# Add parent directory to path to import vlm_utils if needed
sys.path.append(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

# Attempt to import VLM utilities (mock or real)
try:
    from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm
except ImportError:
    # Fallback/Mock for local testing without framework
    def sample_trajectory_frames(traj, n=5): return []
    def get_final_screenshot(traj): return None
    def query_vlm(prompt, image=None, images=None): 
        return {"success": False, "error": "VLM not available"}

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_bowtie_risk_diagram(traj, env_info, task_info):
    """
    Verifies the BowTie diagram creation task.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result metadata from container
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result data: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    score = 0
    feedback = []
    
    # --- Criterion 1: File Existence & Timestamps (30 pts) ---
    eddx_valid = result_data.get("eddx_exists") and result_data.get("eddx_created_during_task") and result_data.get("eddx_size", 0) > 1000
    pdf_valid = result_data.get("pdf_exists") and result_data.get("pdf_created_during_task") and result_data.get("pdf_size", 0) > 1000

    if eddx_valid:
        score += 15
        feedback.append("Native .eddx file created successfully.")
    else:
        feedback.append("Native .eddx file missing, empty, or not created during task.")

    if pdf_valid:
        score += 15
        feedback.append("PDF export created successfully.")
    else:
        feedback.append("PDF export missing, empty, or not created during task.")

    # --- Criterion 2: Content Verification (40 pts) ---
    # We pull the .eddx file and inspect its XML content for key phrases
    required_phrases = task_info.get('metadata', {}).get('required_text', [])
    found_phrases = []
    
    if eddx_valid:
        temp_eddx = tempfile.NamedTemporaryFile(delete=False, suffix='.eddx')
        try:
            copy_from_env(result_data.get("eddx_path", "/home/ga/Documents/ransomware_bowtie.eddx"), temp_eddx.name)
            
            # .eddx is a zip file containing XML
            try:
                with zipfile.ZipFile(temp_eddx.name, 'r') as z:
                    # Content is usually in files like 'page1.xml' or similar inside the zip
                    # We'll just read all xml files we can find
                    all_text = ""
                    for filename in z.namelist():
                        if filename.endswith(".xml"):
                            with z.open(filename) as f:
                                all_text += f.read().decode('utf-8', errors='ignore')
                    
                    # Check for phrases
                    for phrase in required_phrases:
                        if phrase.lower() in all_text.lower():
                            found_phrases.append(phrase)
            except zipfile.BadZipFile:
                feedback.append("EDDX file is not a valid zip archive.")
                
        except Exception as e:
            feedback.append(f"Failed to inspect EDDX content: {e}")
        finally:
            if os.path.exists(temp_eddx.name):
                os.unlink(temp_eddx.name)

    # Scoring content
    # We have 9 phrases total. 40 points total. ~4.4 points per phrase.
    if required_phrases:
        fraction = len(found_phrases) / len(required_phrases)
        content_score = int(fraction * 40)
        score += content_score
        feedback.append(f"Found {len(found_phrases)}/{len(required_phrases)} required text elements.")
        if len(found_phrases) < len(required_phrases):
            missing = set(required_phrases) - set(found_phrases)
            feedback.append(f"Missing text: {', '.join(list(missing)[:3])}...")

    # --- Criterion 3: VLM Visual Verification (30 pts) ---
    # Use trajectory frames to confirm the structure/layout
    frames = sample_trajectory_frames(traj, n=3)
    final_img = get_final_screenshot(traj)
    images_to_check = frames + [final_img] if final_img else frames

    vlm_score = 0
    if images_to_check:
        prompt = """
        You are verifying a 'BowTie' risk diagram created in EdrawMax.
        
        The diagram should have:
        1. A central node labeled 'Ransomware' or similar.
        2. Nodes on the LEFT side (Threats).
        3. Nodes on the RIGHT side (Consequences).
        4. BARRIER nodes (rectangles) placed ON the connecting lines.
        
        Look at the provided screenshots.
        - Do you see a diagram with a central hub and diverging sides (left and right)?
        - Can you identify labels like 'Phishing', 'Encryption', 'Backups'?
        - Does it look like a structured risk diagram?
        
        Return JSON: {"is_bowtie_structure": bool, "has_barriers": bool, "text_visible": bool}
        """
        
        vlm_res = query_vlm(prompt=prompt, images=images_to_check)
        
        if vlm_res.get("success"):
            parsed = vlm_res.get("parsed", {})
            if parsed.get("is_bowtie_structure"):
                vlm_score += 15
                feedback.append("VLM confirmed BowTie structure.")
            if parsed.get("has_barriers"):
                vlm_score += 10
                feedback.append("VLM confirmed barrier placement.")
            if parsed.get("text_visible"):
                vlm_score += 5
                feedback.append("VLM confirmed text labels are visible.")
        else:
            feedback.append("VLM verification failed or inconclusive.")
    else:
        feedback.append("No screenshots available for VLM verification.")

    score += vlm_score

    # Final pass determination
    # Pass if files exist (30) + at least 50% content (20) + some visual confirmation or perfect content
    # Threshold: 60 points
    passed = score >= 60

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }