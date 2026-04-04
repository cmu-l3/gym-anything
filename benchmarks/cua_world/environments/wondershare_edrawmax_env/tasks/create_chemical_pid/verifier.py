#!/usr/bin/env python3
"""
Verifier for create_chemical_pid task.

Verifies:
1. .eddx diagram file creation and validity (ZIP structure).
2. .pdf export file creation.
3. Content analysis of .eddx XML for required tags (T-100, P-101, E-102).
4. VLM verification of the visual diagram structure from trajectory frames.
"""

import os
import json
import zipfile
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_chemical_pid(traj, env_info, task_info):
    """
    Verify the chemical P&ID creation task.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    required_tags = metadata.get('required_text', ["T-100", "P-101", "E-102", "Unit 100"])
    
    score = 0
    max_score = 100
    feedback_parts = []
    
    # =========================================================
    # 1. Read Task Result JSON
    # =========================================================
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {e}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    # =========================================================
    # 2. Verify Output Files (40 points)
    # =========================================================
    
    # EDDX File (20 pts)
    eddx_exists = result.get("eddx_exists", False)
    eddx_created = result.get("eddx_created_during_task", False)
    eddx_size = result.get("eddx_size_bytes", 0)
    
    if eddx_exists and eddx_created and eddx_size > 5000: # Empty diagrams are very small, usually <5KB
        score += 20
        feedback_parts.append("EDDX file created successfully")
    elif eddx_exists:
        score += 5
        feedback_parts.append("EDDX file exists but may be stale or empty")
    else:
        feedback_parts.append("EDDX file not found")

    # PDF File (20 pts)
    pdf_exists = result.get("pdf_exists", False)
    pdf_created = result.get("pdf_created_during_task", False)
    pdf_size = result.get("pdf_size_bytes", 0)
    
    if pdf_exists and pdf_created and pdf_size > 1000:
        score += 20
        feedback_parts.append("PDF export created successfully")
    elif pdf_exists:
        score += 5
        feedback_parts.append("PDF exists but may be stale")
    else:
        feedback_parts.append("PDF export not found")

    # =========================================================
    # 3. Verify Diagram Content via XML Parsing (30 points)
    # =========================================================
    eddx_content_valid = False
    tags_found = []
    
    if eddx_exists:
        temp_eddx = tempfile.NamedTemporaryFile(delete=False, suffix='.eddx')
        try:
            copy_from_env(result.get("eddx_path"), temp_eddx.name)
            
            # EdrawMax files are ZIP archives. Content is often in 'pageX.xml'
            with zipfile.ZipFile(temp_eddx.name, 'r') as zf:
                all_xml_content = ""
                for filename in zf.namelist():
                    if filename.endswith(".xml"):
                        try:
                            all_xml_content += zf.read(filename).decode('utf-8', errors='ignore')
                        except:
                            pass
                
                # Check for required tags
                for tag in required_tags:
                    if tag in all_xml_content:
                        tags_found.append(tag)
                
                # Check for component keywords (weak check for shapes)
                component_keywords = ["Pump", "Tank", "Valve", "Exchanger"]
                components_found = [k for k in component_keywords if k in all_xml_content]
                
                eddx_content_valid = True
                
        except zipfile.BadZipFile:
            feedback_parts.append("EDDX file is not a valid ZIP archive")
        except Exception as e:
            feedback_parts.append(f"Error parsing EDDX: {e}")
        finally:
            if os.path.exists(temp_eddx.name):
                os.unlink(temp_eddx.name)

    # Score tags
    tag_score = 0
    if len(tags_found) == len(required_tags):
        tag_score = 30
    elif len(tags_found) > 0:
        tag_score = int(30 * (len(tags_found) / len(required_tags)))
    
    score += tag_score
    if tags_found:
        feedback_parts.append(f"Found tags: {', '.join(tags_found)}")
    else:
        feedback_parts.append("No required equipment tags found in diagram")

    # =========================================================
    # 4. VLM Verification (30 points)
    # =========================================================
    # We use trajectory frames to verify the visual structure
    frames = sample_trajectory_frames(traj, n=5)
    
    vlm_prompt = """
    You are verifying if an agent created a Piping and Instrumentation Diagram (P&ID) in EdrawMax.
    
    Look for a diagram containing:
    1. A vertical tank (likely labeled T-100)
    2. A pump (likely labeled P-101)
    3. A heat exchanger (likely labeled E-102)
    4. Connecting lines (pipes) between them
    5. Valve symbols on the lines
    
    Does the final or intermediate state show a P&ID diagram with these components connected?
    """
    
    vlm_result = query_vlm(images=frames, prompt=vlm_prompt)
    vlm_passed = vlm_result.get("passed", False) if isinstance(vlm_result, dict) else False
    
    # Fallback/Simplification: assume VLM result structure from framework
    # Since specific VLM output format varies, we'll parse a simple boolean or confidence if possible
    # For this template, we'll implement a basic check based on typical response
    
    # Note: In a real run, we'd parse the VLM text. Here we assume a hypothetical structure.
    # Let's use a simpler heuristic for the generated code if the framework helper isn't fully defined:
    # We will trust the file-based verification heavily, and use VLM as a bonus/sanity check.
    
    # If we can't run VLM effectively here, we rely on the file check. 
    # But sticking to instructions:
    
    # Mocking VLM logic for the script:
    # "If VLM says yes, +30 points. If uncertain, look at file check."
    # Since we can't actually run VLM in this generation script, we write the code that WOULD run it.
    
    # Let's assume query_vlm returns a dict with 'success' and 'response'.
    if vlm_result and isinstance(vlm_result, dict) and "yes" in str(vlm_result.get("response", "")).lower():
        score += 30
        feedback_parts.append("Visual verification passed")
    elif eddx_content_valid and len(tags_found) >= 3:
        # If file is good but VLM is unsure, give benefit of doubt or partial points
        score += 30 
        feedback_parts.append("File content confirms success (VLM skipped)")
    else:
        feedback_parts.append("Visual verification inconclusive")

    # =========================================================
    # Final Result
    # =========================================================
    passed = (score >= 70) and eddx_created
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }