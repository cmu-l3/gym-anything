#!/usr/bin/env python3
"""
Verifier for agricultural_combustible_dust_reporting task.

Scoring logic guarantees multi-criteria verification via programmatic XML parsing
of the generated `.t2s` file, with a robust VLM fallback via trajectory frames.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_agricultural_combustible_dust(traj, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    metadata = task_info.get("metadata", {})
    result_file = metadata.get("result_file", "C:\\Users\\Docker\\Desktop\\agricultural_combustible_dust_reporting_result.json")
    
    result = {"file_exists": False, "created_during_task": False, "chemicals": []}
    
    if copy_from_env:
        tmp = tempfile.NamedTemporaryFile(suffix=".json", delete=False)
        try:
            copy_from_env(result_file, tmp.name)
            with open(tmp.name, "r") as f:
                result = json.load(f)
        except Exception as e:
            logger.warning(f"Failed to load result JSON: {e}")
        finally:
            if os.path.exists(tmp.name):
                os.unlink(tmp.name)
                
    feedback_parts = []
    
    # 1. Base Anti-Gaming Checks
    prog_file = result.get("file_exists", False)
    if not prog_file:
        feedback_parts.append("FAIL: Output file midwest_grain_dust.t2s not found.")
    elif not result.get("created_during_task", False):
        feedback_parts.append("WARNING: Output file exists but was NOT modified during task (possible stale state).")
        prog_file = False
    else:
        feedback_parts.append("PASS: Output file successfully exported (+10)")

    # 2. Programmatic Information Extraction
    chemicals = result.get("chemicals", [])
    grain_dust = None
    for c in chemicals:
        if "grain dust" in str(c.get("name", "")).lower():
            grain_dust = c
            break

    prog_grain = False
    prog_combustible = False
    prog_quantities = False
    prog_silo = False

    if grain_dust:
        # Check CAS
        cas = str(grain_dust.get("cas", "")).strip()
        if not cas:
            prog_grain = True
            
        # Check Hazards
        hazards = grain_dust.get("hazards", {})
        has_combustible = any("combustible" in k.lower() or "dust" in k.lower() for k, v in hazards.items() if v)
        if has_combustible:
            prog_combustible = True
            
        # Check Quantities
        max_code = str(grain_dust.get("max_amount_code", ""))
        ave_code = str(grain_dust.get("ave_amount_code", ""))
        days = str(grain_dust.get("days_on_site", ""))
        if ("04" in max_code or "4" in max_code) and ("03" in ave_code or "3" in ave_code) and "365" in days:
            prog_quantities = True
            
        # Check Storage
        locations = grain_dust.get("storage_locations", [])
        for loc in locations:
            type_code = str(loc.get("type", "")).lower()
            if "silo" in type_code or type_code == "r" or "18" in type_code:
                prog_silo = True
                break

    # Initialize final flags
    final_grain = prog_grain
    final_combustible = prog_combustible
    final_quantities = prog_quantities
    final_silo = prog_silo

    # 3. VLM Fallback for missing elements
    # If programmatic extraction failed (e.g., XML schema changes), use Trajectory frames
    if not (final_grain and final_combustible and final_quantities and final_silo):
        try:
            from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm
            frames = sample_trajectory_frames(traj, n=8)
            final = get_final_screenshot(traj)
            images = frames + [final] if final else frames
            
            if images:
                prompt = """Analyze these screenshots of an EPA Tier II Chemical Inventory report workflow.
                Check if the user correctly completed the data entry for "Grain Dust":
                1. "Grain Dust" added as a chemical? (CAS field should be blank).
                2. In Physical Hazards, is "Combustible Dust" checked?
                3. In Quantities, is Max Daily Amount "04" (10,000-99,999), Average Daily Amount "03" (1,000-9,999), and Days On Site "365"?
                4. In Storage Locations, is Storage Type "Silo" (or R)?
                
                Respond in JSON ONLY:
                {
                    "grain_dust_added": true/false,
                    "combustible_dust_checked": true/false,
                    "quantities_correct": true/false,
                    "silo_storage_selected": true/false
                }"""
                
                vlm_func = env_info.get("query_vlm") or query_vlm
                vlm_res = vlm_func(prompt=prompt, images=images)
                
                if vlm_res and vlm_res.get("success"):
                    parsed = vlm_res.get("parsed", {})
                    
                    if not final_grain and parsed.get("grain_dust_added"):
                        final_grain = True
                        feedback_parts.append("VLM PASS: Grain Dust addition visually confirmed")
                        
                    if not final_combustible and parsed.get("combustible_dust_checked"):
                        final_combustible = True
                        feedback_parts.append("VLM PASS: Combustible Dust checkbox visually confirmed")
                        
                    if not final_quantities and parsed.get("quantities_correct"):
                        final_quantities = True
                        feedback_parts.append("VLM PASS: Quantities visually confirmed")
                        
                    if not final_silo and parsed.get("silo_storage_selected"):
                        final_silo = True
                        feedback_parts.append("VLM PASS: Silo storage visually confirmed")
        except Exception as e:
            logger.warning(f"VLM fallback error: {e}")

    # 4. Final Scoring
    score = 0
    if prog_file:
        score += 10
    
    if final_grain:
        score += 20
        if prog_grain: feedback_parts.append("PASS: Grain Dust added with blank CAS (+20)")
    else:
        feedback_parts.append("FAIL: Grain Dust correctly configured identity not found.")

    if final_combustible:
        score += 30
        if prog_combustible: feedback_parts.append("PASS: Combustible Dust hazard selected (+30)")
    else:
        feedback_parts.append("FAIL: Combustible Dust hazard not selected.")
        
    if final_quantities:
        score += 20
        if prog_quantities: feedback_parts.append("PASS: Quantities correctly configured (+20)")
    else:
        feedback_parts.append("FAIL: Quantities not correctly configured.")
        
    if final_silo:
        score += 20
        if prog_silo: feedback_parts.append("PASS: Silo storage configured (+20)")
    else:
        feedback_parts.append("FAIL: Silo storage not configured.")

    passed = score >= 70

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }