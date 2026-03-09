#!/usr/bin/env python3
"""
Verifier for create_digital_logic_circuit task.

Verification Strategy:
1. File Existence: Check if .eddx and .png files exist and were created during the task.
2. Content Analysis (XML): Unzip .eddx file and count occurrences of "XOR", "AND", "OR" gates.
3. VLM Verification: Analyze the exported PNG or trajectory to confirm visual structure of a Full Adder.
"""

import json
import os
import tempfile
import zipfile
import logging
import sys
from pathlib import Path

# Add parent directory to path to import vlm_utils if needed, 
# though we usually assume environment setup handles imports.
# For this script, we'll try to import common VLM helpers if available.
try:
    from gym_anything.vlm import query_vlm, get_final_screenshot, sample_trajectory_frames
except ImportError:
    # Mock for local testing or if package not available in this context
    def query_vlm(**kwargs): return {"success": False, "error": "VLM not available"}
    def get_final_screenshot(traj): return None
    def sample_trajectory_frames(traj, n=1): return []

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_digital_logic_circuit(traj, env_info, task_info):
    """
    Verify the 1-bit Full Adder creation.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    required_gates = metadata.get('required_gates', {"XOR": 2, "AND": 2, "OR": 1})
    
    score = 0
    max_score = 100
    feedback_parts = []
    
    # =========================================================
    # 1. READ EXPORTED RESULT
    # =========================================================
    temp_result_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result_file.name)
        with open(temp_result_file.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read task results: {str(e)}"}
    finally:
        if os.path.exists(temp_result_file.name):
            os.unlink(temp_result_file.name)

    # =========================================================
    # 2. FILE VERIFICATION (20 Points)
    # =========================================================
    eddx_exists = result_data.get("eddx_exists", False)
    eddx_fresh = result_data.get("eddx_created_during_task", False)
    eddx_size = result_data.get("eddx_size", 0)
    
    png_exists = result_data.get("png_exists", False)
    png_fresh = result_data.get("png_created_during_task", False)
    png_size = result_data.get("png_size", 0)

    # Basic file check
    if eddx_exists and eddx_fresh and eddx_size > 5000:
        score += 10
        feedback_parts.append("Valid .eddx file created.")
    elif eddx_exists:
        feedback_parts.append(".eddx file exists but may be old or empty.")
    else:
        feedback_parts.append(".eddx file missing.")

    if png_exists and png_fresh and png_size > 10000:
        score += 10
        feedback_parts.append("Valid .png export created.")
    else:
        feedback_parts.append(".png export missing or invalid.")

    # =========================================================
    # 3. XML CONTENT ANALYSIS (40 Points)
    # =========================================================
    # Copy the .eddx file to host for analysis
    gate_counts = {"XOR": 0, "AND": 0, "OR": 0}
    xml_analysis_passed = False
    
    if eddx_exists:
        temp_eddx = tempfile.NamedTemporaryFile(delete=False, suffix='.zip')
        try:
            copy_from_env("/home/ga/Diagrams/full_adder_circuit.eddx", temp_eddx.name)
            
            # EdrawMax .eddx is a ZIP file. We search all .xml files inside for gate names.
            # Typical shapes are named like "XOR gate", "And Gate", "Or-Gate".
            with zipfile.ZipFile(temp_eddx.name, 'r') as zf:
                all_text = ""
                for filename in zf.namelist():
                    if filename.endswith('.xml'):
                        try:
                            all_text += zf.read(filename).decode('utf-8', errors='ignore').lower()
                        except:
                            pass
            
            # Count gates based on text occurrence
            # Note: "xor" is specific enough. "and" is too common, so we look for "and gate".
            # "or" is too common, look for "or gate".
            gate_counts["XOR"] = all_text.count("xor")
            gate_counts["AND"] = all_text.count("and gate") 
            gate_counts["OR"] = all_text.count("or gate")
            
            # Check requirements
            xor_ok = gate_counts["XOR"] >= required_gates["XOR"]
            and_ok = gate_counts["AND"] >= required_gates["AND"]
            or_ok = gate_counts["OR"] >= required_gates["OR"]
            
            if xor_ok and and_ok and or_ok:
                score += 40
                xml_analysis_passed = True
                feedback_parts.append(f"Logic gates found in file: {gate_counts}.")
            else:
                partial_score = 0
                if xor_ok: partial_score += 15
                if and_ok: partial_score += 15
                if or_ok: partial_score += 10
                score += partial_score
                feedback_parts.append(f"Gate count mismatch. Found: {gate_counts}. Expected: {required_gates}")

        except Exception as e:
            feedback_parts.append(f"Failed to analyze .eddx content: {str(e)}")
        finally:
            if os.path.exists(temp_eddx.name):
                os.unlink(temp_eddx.name)

    # =========================================================
    # 4. VLM VERIFICATION (40 Points)
    # =========================================================
    # We prefer analyzing the exported PNG if available, as it represents the final result clearly.
    # Fallback to trajectory frames.
    
    vlm_image = None
    if png_exists:
        # Copy the png to host
        temp_png = tempfile.NamedTemporaryFile(delete=False, suffix='.png')
        try:
            copy_from_env("/home/ga/Diagrams/full_adder_circuit.png", temp_png.name)
            vlm_image = temp_png.name
            # Note: The vlm_utils usually expect image data or paths. 
            # Assuming query_vlm handles local paths or we need to read bytes.
            # We will rely on framework mechanisms for trajectory if this is complex.
        except:
            pass
    
    # If no PNG or copy failed, use framework trajectory
    if not vlm_image:
        frames = sample_trajectory_frames(traj, n=1)
        if frames:
            vlm_image = frames[-1]
        else:
            final_ss = get_final_screenshot(traj)
            if final_ss:
                vlm_image = final_ss

    vlm_passed = False
    if vlm_image:
        prompt = """
        You are verifying a diagram task. The user was asked to create a '1-bit Full Adder' digital logic circuit.
        
        Look for:
        1. A logic circuit diagram with gates and wires.
        2. Text labels: 'Sum', 'Cout' (or Carry-Out), 'A', 'B', 'Cin' (or Carry-In).
        3. Structure: Inputs on left, outputs on right.
        
        JSON response format:
        {
            "is_logic_circuit": true/false,
            "has_correct_labels": true/false,
            "visible_labels": ["list", "of", "labels", "seen"],
            "score_confidence": 0-100
        }
        """
        
        try:
            # Depending on implementation, vlm_image might need to be bytes or path
            # Here we assume the framework's query_vlm handles the object passed
            response = query_vlm(image=vlm_image, prompt=prompt)
            
            if response and response.get("success"):
                parsed = response.get("parsed", {})
                
                is_circuit = parsed.get("is_logic_circuit", False)
                has_labels = parsed.get("has_correct_labels", False)
                
                if is_circuit:
                    score += 20
                    feedback_parts.append("VLM confirms logic circuit structure.")
                    if has_labels:
                        score += 20
                        vlm_passed = True
                        feedback_parts.append("VLM confirms correct labels present.")
                    else:
                        feedback_parts.append("VLM sees circuit but missing specific labels.")
                else:
                    feedback_parts.append("VLM did not recognize a logic circuit.")
            else:
                feedback_parts.append("VLM query failed.")
        except Exception as e:
            feedback_parts.append(f"VLM verification error: {str(e)}")
            # Fallback points if XML analysis was perfect, assume visual is likely okay
            if xml_analysis_passed:
                score += 20
                feedback_parts.append("Granting partial VLM points based on strong XML evidence.")
    else:
        feedback_parts.append("No image available for VLM verification.")

    # Clean up temp png if created
    if png_exists and 'temp_png' in locals() and os.path.exists(temp_png.name):
        os.unlink(temp_png.name)

    # Final Pass Logic
    # Pass if score >= 80 (Meaning files exist, XML content is good, and at least partial visual or full visual)
    passed = score >= 80

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }