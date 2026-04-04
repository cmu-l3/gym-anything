#!/usr/bin/env python3
"""
Verifier for create_uml_class_diagram task.
Checks for file existence/validity and performs VLM analysis on the output.
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_uml_class_diagram(traj, env_info, task_info):
    """
    Verify the agent created the Patient Portal UML Class Diagram.
    
    Scoring Breakdown (100 pts total):
    - 30 pts: Files exist, are valid types, created during task, and adequate size.
    - 70 pts: VLM Content Verification (Classes, Attributes, Relationships).
    """
    
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    min_eddx_size = metadata.get('min_eddx_size_bytes', 10000)
    min_png_size = metadata.get('min_png_size_bytes', 20000)

    # 1. Retrieve Result JSON
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {str(e)}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    score = 0
    feedback_parts = []
    
    task_start = result_data.get('task_start', 0)
    
    # --- CRITERION 1: File Existence & Integrity (30 pts) ---
    
    # Check EDDX
    eddx_exists = result_data.get('eddx_exists', False)
    eddx_size = result_data.get('eddx_size_bytes', 0)
    eddx_mtime = result_data.get('eddx_mtime', 0)
    
    if eddx_exists and eddx_size > min_eddx_size:
        if eddx_mtime > task_start:
            score += 10
            feedback_parts.append("EDDX file created successfully.")
        else:
            feedback_parts.append("EDDX file exists but timestamp is too old.")
    elif eddx_exists:
        feedback_parts.append(f"EDDX file exists but is too small ({eddx_size} bytes).")
    else:
        feedback_parts.append("EDDX file not found.")

    # Check PNG
    png_exists = result_data.get('png_exists', False)
    png_size = result_data.get('png_size_bytes', 0)
    png_mtime = result_data.get('png_mtime', 0)
    
    # We will try to download the PNG for VLM analysis
    local_png_path = None
    if png_exists and png_size > min_png_size:
        if png_mtime > task_start:
            score += 15 # Higher weight for PNG as it's the visual proof
            feedback_parts.append("PNG export created successfully.")
            
            # Download PNG for VLM
            try:
                temp_png = tempfile.NamedTemporaryFile(delete=False, suffix='.png')
                copy_from_env("/home/ga/Documents/patient_portal_class_diagram.png", temp_png.name)
                local_png_path = temp_png.name
            except Exception as e:
                feedback_parts.append(f"Could not retrieve PNG for verification: {e}")
        else:
            feedback_parts.append("PNG file exists but timestamp is too old.")
    elif png_exists:
        feedback_parts.append(f"PNG file exists but is too small ({png_size} bytes).")
    else:
        feedback_parts.append("PNG export not found.")
        
    # Reasonable dimensions check (5 pts)
    png_dims = result_data.get('png_dims', "0x0")
    if png_dims != "0x0":
        try:
            w, h = map(int, png_dims.split('x'))
            if w > 400 and h > 400:
                score += 5
                feedback_parts.append("PNG dimensions look reasonable.")
        except:
            pass

    # --- CRITERION 2: VLM Verification (70 pts) ---
    
    # We prioritize the exported PNG for content verification because it's cleaner.
    # If not available, we fall back to the final screenshot.
    
    image_to_analyze = local_png_path
    
    # Fallback to final screenshot if PNG export failed
    if not image_to_analyze:
        final_screenshot_path = "/tmp/task_final.png"
        try:
            temp_screen = tempfile.NamedTemporaryFile(delete=False, suffix='.png')
            copy_from_env(final_screenshot_path, temp_screen.name)
            image_to_analyze = temp_screen.name
            feedback_parts.append("Using final screenshot for verification (PNG export missing).")
        except:
            feedback_parts.append("No images available for VLM verification.")
    
    vlm_score = 0
    if image_to_analyze:
        query_vlm = env_info.get('query_vlm')
        if query_vlm:
            prompt = """
            Analyze this image of a UML Class Diagram.
            
            I am looking for a specific Patient Portal domain model.
            Check for the existence of these 5 Class boxes with approximately these contents:
            
            1. "Patient" (Attributes: patientId, firstName... Methods: getFullName...)
            2. "Doctor" (Attributes: doctorId, specialty... Methods: getAvailableSlots...)
            3. "Appointment" (Attributes: dateTime, status... Methods: cancel...)
            4. "Prescription" (Attributes: medication, dosage...)
            5. "MedicalRecord" (Attributes: diagnosis, treatmentPlan...)
            
            Also check for:
            - Three-compartment class boxes (Name, Attributes, Methods sections).
            - Lines connecting the classes (Associations).
            - Multiplicity labels like "1" and "*".
            
            Return a JSON object with:
            {
                "found_classes": ["list", "of", "found", "class", "names"],
                "has_attributes_and_methods": true/false,
                "has_relationships": true/false,
                "has_multiplicity": true/false,
                "overall_quality": "low/medium/high"
            }
            """
            
            try:
                vlm_result = query_vlm(prompt=prompt, image=image_to_analyze)
                if vlm_result.get('success'):
                    parsed = vlm_result.get('parsed', {})
                    
                    found_classes = [c.lower() for c in parsed.get('found_classes', [])]
                    required_classes = ["patient", "doctor", "appointment", "prescription", "medicalrecord"]
                    
                    # Score classes (8 pts each, max 40)
                    class_hits = 0
                    for req in required_classes:
                        if any(req in found for found in found_classes):
                            class_hits += 1
                            vlm_score += 8
                    
                    feedback_parts.append(f"VLM found {class_hits}/5 required classes.")
                    
                    # Score structure
                    if parsed.get('has_attributes_and_methods'):
                        vlm_score += 10
                        feedback_parts.append("Class structure (attributes/methods) verified.")
                    
                    if parsed.get('has_relationships'):
                        vlm_score += 10
                        feedback_parts.append("Relationships verified.")
                        
                    if parsed.get('has_multiplicity'):
                        vlm_score += 5
                        feedback_parts.append("Multiplicity labels verified.")
                    
                    # Clean up temp file
                    if local_png_path and os.path.exists(local_png_path):
                        os.unlink(local_png_path)
                        
                else:
                    feedback_parts.append(f"VLM analysis failed: {vlm_result.get('error')}")
            except Exception as e:
                feedback_parts.append(f"VLM execution error: {e}")
        else:
            feedback_parts.append("VLM tool not available.")
            
        # Add trajectory verification for "Process" (5 pts)
        # Even if the final image is perfect, we want to know they built it.
        frames = sample_trajectory_frames(traj, n=4)
        if frames and query_vlm:
            traj_prompt = """
            Look at these screenshots of a user using EdrawMax.
            Do they show a progression of building a diagram?
            (e.g. Empty canvas -> Some shapes -> More shapes -> Final diagram)
            Answer with a JSON: {"shows_progression": true/false}
            """
            try:
                traj_res = query_vlm(prompt=traj_prompt, images=frames)
                if traj_res.get('success') and traj_res.get('parsed', {}).get('shows_progression'):
                    vlm_score += 5
                    feedback_parts.append("Trajectory shows valid work progression.")
            except:
                pass

    score += vlm_score

    # Final check
    passed = score >= 60 and (eddx_exists and png_exists)
    
    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback_parts)
    }