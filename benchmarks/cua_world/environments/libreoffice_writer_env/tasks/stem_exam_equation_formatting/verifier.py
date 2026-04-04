#!/usr/bin/env python3
"""
Verifier for STEM Exam Equation Formatting task.
Verifies that the agent inserted proper LibreOffice Math objects (OLE)
instead of plain text.

Verification Strategy:
1. Check if output file exists and is a valid ODT (zip archive).
2. Unzip ODT and inspect 'content.xml' to ensure placeholders are removed.
3. Inspect embedded Objects (Object */content.xml) for MathML signatures.
   - Requires finding specific mathematical operators/variables in the MathML.
4. VLM verification of the final screenshot to confirm visual rendering.
"""

import json
import os
import shutil
import tempfile
import zipfile
import re
import logging
from typing import Dict, Any, List

# Add utils path if needed, though this task is self-contained mostly
try:
    from gym_anything.vlm import query_vlm, get_final_screenshot
except ImportError:
    pass  # Will handle gracefully

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_stem_exam(traj, env_info, task_info):
    """
    Verify STEM exam equation formatting.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    placeholders = metadata.get('placeholders', [])
    
    # Setup temporary directory for verification
    temp_dir = tempfile.mkdtemp()
    local_odt = os.path.join(temp_dir, "result.odt")
    
    score = 0
    feedback = []
    
    try:
        # 1. Get result JSON
        local_json = os.path.join(temp_dir, "result.json")
        copy_from_env("/tmp/task_result.json", local_json)
        with open(local_json, 'r') as f:
            result_data = json.load(f)
            
        if not result_data.get("output_exists"):
            return {
                "passed": False, 
                "score": 0, 
                "feedback": "Output file 'calculus_midterm_final.odt' not found."
            }
            
        if not result_data.get("created_during_task"):
            return {
                "passed": False,
                "score": 0,
                "feedback": "Output file was not modified during the task session."
            }
            
        score += 10
        feedback.append("File created and saved.")

        # 2. Get the ODT file
        copy_from_env(result_data["output_path"], local_odt)
        
        if not zipfile.is_zipfile(local_odt):
            return {
                "passed": False,
                "score": score,
                "feedback": "Output file is not a valid ODT/Zip archive."
            }

        # 3. Analyze ODT structure
        with zipfile.ZipFile(local_odt, 'r') as z:
            # Check main content for placeholder removal
            try:
                content_xml = z.read("content.xml").decode('utf-8')
                placeholders_removed = 0
                for ph in placeholders:
                    # Simple check: the exact placeholder string should not exist
                    if ph not in content_xml:
                        placeholders_removed += 1
                    else:
                        feedback.append(f"Placeholder '{ph}' still found in text.")
                
                if placeholders_removed == len(placeholders):
                    score += 20
                    feedback.append("All text placeholders removed.")
                else:
                    score += int(20 * (placeholders_removed / len(placeholders)))
            except KeyError:
                feedback.append("Could not read content.xml (corrupted ODT?).")

            # Check for Math Objects
            # LibreOffice stores formulas in 'Object X/content.xml' usually
            math_objects = []
            file_list = z.namelist()
            object_dirs = set()
            for name in file_list:
                if re.match(r'Object \d+/content.xml', name):
                    object_dirs.add(os.path.dirname(name))
            
            logger.info(f"Found {len(object_dirs)} embedded objects: {object_dirs}")
            
            if len(object_dirs) < 3:
                feedback.append(f"Found only {len(object_dirs)} math objects (expected 3).")
                score += len(object_dirs) * 5  # Partial credit
            else:
                score += 30
                feedback.append(f"Found {len(object_dirs)} math objects (Equation Editor used).")

            # Analyze Math Object Content (Signatures)
            # We look for ANY object matching the signatures
            # Signatures are loose because StarMath/MathML conversion varies
            signatures = {
                "quadratic": ["b", "4", "ac", "sqrt", "√"], # Look for b, 4, ac, and some root symbol
                "derivative": ["lim", "h", "0"],            # Limit h->0
                "integral": ["int", "∫", "dx", "a", "b"]    # Integral symbol, dx, bounds
            }
            
            found_formulas = {k: False for k in signatures}
            
            for obj_dir in object_dirs:
                try:
                    obj_content = z.read(f"{obj_dir}/content.xml").decode('utf-8')
                    # Simple heuristic: check if content matches signatures
                    # Note: MathML is verbose, we search strictly for values/identifiers
                    
                    for f_type, sigs in signatures.items():
                        if found_formulas[f_type]: continue
                        
                        # Count matches
                        matches = 0
                        required = 2 # At least 2 signature elements found
                        if f_type == "quadratic": required = 3
                        
                        for sig in sigs:
                            if sig in obj_content:
                                matches += 1
                        
                        if matches >= required:
                            found_formulas[f_type] = True
                            logger.info(f"Matched {f_type} in {obj_dir}")
                except Exception as e:
                    logger.warning(f"Error reading object {obj_dir}: {e}")

            # Score formulas
            if found_formulas["quadratic"]:
                score += 10
                feedback.append("Quadratic formula detected.")
            else:
                feedback.append("Quadratic formula content not detected in objects.")
                
            if found_formulas["derivative"]:
                score += 10
                feedback.append("Derivative definition detected.")
            else:
                feedback.append("Derivative definition content not detected.")
                
            if found_formulas["integral"]:
                score += 10
                feedback.append("Integral detected.")
            else:
                feedback.append("Integral content not detected.")

        # 4. VLM Verification (Visual Check)
        # This catches cases where they typed text but somehow it looked like a math object
        # or if the formatting is visually correct even if internal XML is weird
        try:
            query_vlm_fn = env_info.get('query_vlm')
            final_screenshot = get_final_screenshot(traj)
            
            if query_vlm_fn and final_screenshot:
                prompt = """
                Analyze this screenshot of a LibreOffice Writer document.
                I am looking for three specific mathematical equations that should be professionally formatted (not just plain text).
                
                1. Quadratic Formula (fraction with square root)
                2. Derivative Limit Definition (lim h->0)
                3. Definite Integral (integral sign with bounds a and b)
                
                Do you see these three equations visually rendered?
                Are they formatted as proper math equations (e.g., proper fraction bars, big integral signs)?
                
                Respond in JSON:
                {
                    "quadratic_visible": true/false,
                    "derivative_visible": true/false,
                    "integral_visible": true/false,
                    "looks_professional": true/false
                }
                """
                vlm_res = query_vlm_fn(prompt=prompt, image=final_screenshot)
                if vlm_res['success']:
                    parsed = vlm_res['parsed']
                    vlm_score = 0
                    if parsed.get('quadratic_visible'): vlm_score += 3
                    if parsed.get('derivative_visible'): vlm_score += 3
                    if parsed.get('integral_visible'): vlm_score += 4
                    
                    # If XML check failed but VLM says it looks good, give some credit
                    # If XML check passed, this confirms it
                    if vlm_score == 10:
                         feedback.append("Visual verification passed (Equations visible).")
                    else:
                         feedback.append(f"Visual verification partial: {vlm_score}/10")
                    
                    score = min(100, score + vlm_score) # Cap at 100
                    
        except Exception as e:
            logger.warning(f"VLM check failed: {e}")

    except Exception as e:
        logger.error(f"Verification failed with error: {e}")
        return {"passed": False, "score": score, "feedback": f"System error during verification: {str(e)}"}
    finally:
        shutil.rmtree(temp_dir)

    passed = score >= 70
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }