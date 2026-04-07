#!/usr/bin/env python3
"""
Verifier for floor_plan_drawing_generation task.

Verification Checks:
1. IFC saved during task session (15 pts) - Anti-gaming
2. SVG exported in project directory (15 pts)
3. SVG semantics: Contains IfcWall cuts (10 pts)
4. SVG semantics: Contains IfcDoor/IfcWindow elements (10 pts)
5. SVG complexity: >= 20 geometric tags proving realistic drawing depth (20 pts)
6. VLM Trajectory: Verifies interaction with Bonsai UI specifically (30 pts)
"""

import json
import os
import tempfile
import re
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def _vlm_query(query_vlm, prompt, images):
    if not query_vlm or not images:
        return None
    try:
        result = query_vlm(prompt=prompt, images=images)
        if result.get("success"):
            return result.get("parsed", {})
        logger.warning(f"VLM query failed: {result.get('error', 'unknown')}")
    except Exception as e:
        logger.warning(f"VLM query exception: {e}")
    return None

def verify_floor_plan_drawing(traj, env_info, task_info):
    score = 0
    feedback_lines = []
    
    copy_from_env = env_info.get("copy_from_env")
    query_vlm = env_info.get("query_vlm")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available."}

    # Extract JSON results securely
    with tempfile.NamedTemporaryFile(suffix=".json", delete=False) as f:
        tmp_json = f.name
        
    try:
        copy_from_env("/tmp/drawing_result.json", tmp_json)
        with open(tmp_json, "r") as f:
            result = json.load(f)
    except FileNotFoundError:
        return {"passed": False, "score": 0, "feedback": "Result file not found."}
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Could not read result file: {e}"}
    finally:
        if os.path.exists(tmp_json):
            os.unlink(tmp_json)

    # =======================================================
    # 1. IFC Checks (Timestamps & Existance)
    # =======================================================
    if not result.get("ifc_exists", False):
        feedback_lines.append("FAIL: Output IFC file fzk_with_drawings.ifc was not created. (+0)")
    else:
        file_mtime = result.get("ifc_mtime", 0.0)
        task_start = result.get("task_start", 0.0)
        if task_start > 0 and file_mtime > task_start:
            score += 15
            feedback_lines.append("PASS: Output IFC was created/saved during task session. (+15)")
        else:
            feedback_lines.append("FAIL: Output IFC was not modified during task. (+0)")

    # =======================================================
    # 2. SVG Existence Check
    # =======================================================
    svg_exists = result.get("svg_exists", False)
    svg_content = ""
    if svg_exists:
        score += 15
        feedback_lines.append("PASS: SVG drawing file was generated in project folder. (+15)")
        
        # Safely copy SVG to analyze
        with tempfile.NamedTemporaryFile(suffix=".svg", delete=False) as f:
            tmp_svg = f.name
        try:
            copy_from_env("/tmp/floor_plan_output.svg", tmp_svg)
            with open(tmp_svg, "r") as f:
                svg_content = f.read()
        except Exception as e:
            logger.warning(f"Could not read SVG content: {e}")
        finally:
            if os.path.exists(tmp_svg):
                os.unlink(tmp_svg)
    else:
        feedback_lines.append("FAIL: No SVG drawing file was generated. (+0)")

    # =======================================================
    # 3-5. SVG Content & Structural Parsing
    # =======================================================
    if svg_content:
        # Check walls (semantic ID from Bonsai generation)
        if "IfcWall" in svg_content:
            score += 10
            feedback_lines.append("PASS: SVG accurately reflects IFC semantics (IfcWall tags present). (+10)")
        else:
            feedback_lines.append("FAIL: SVG missing IfcWall semantic tags. (+0)")
            
        # Check openings
        if "IfcDoor" in svg_content or "IfcWindow" in svg_content:
            score += 10
            feedback_lines.append("PASS: SVG reflects complex models (IfcDoor/IfcWindow tags present). (+10)")
        else:
            feedback_lines.append("FAIL: SVG missing IfcDoor/IfcWindow tags. (+0)")
            
        # Check geometry complexity 
        geom_tags = len(re.findall(r'<(path|rect|polygon|polyline|line|circle)\b', svg_content, re.IGNORECASE))
        if geom_tags >= 20:
            score += 20
            feedback_lines.append(f"PASS: SVG geometry complexity is high ({geom_tags} geometric elements). (+20)")
        elif geom_tags > 0:
            score += 10
            feedback_lines.append(f"PARTIAL: SVG geometry complexity is suspiciously low ({geom_tags} elements). (+10)")
        else:
            feedback_lines.append("FAIL: SVG contains no geometric vector elements. (+0)")
            
    # =======================================================
    # 6. VLM Verification (Trajectory Checking)
    # =======================================================
    vlm_score = 0
    if query_vlm:
        try:
            from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
            frames = sample_trajectory_frames(traj, n=5)
            final = get_final_screenshot(traj)
            images = frames + [final]
            
            prompt = """You are evaluating an AI agent performing a 2D drawing generation task in BlenderBIM.
The agent must:
1. Navigate to Drawings & Documents module.
2. Create a Plan drawing for the Ground Floor.
3. Publish/generate the SVG.

Analyze the screenshots chronologically. Did the agent perform these actions? Look for:
- The Drawings & Documents panel open in the right-hand Blender UI.
- A camera boundary wireframe box appearing in the 3D viewport representing the drawing plan cut.
- Clicking the "Add Drawing", "Activate", or "Publish" buttons inside the BIM panels.

Respond ONLY with a valid JSON object:
{
    "drawings_panel_used": true/false,
    "drawing_generated": true/false,
    "confidence": "high/medium/low",
    "reasoning": "short explanation"
}"""
            vlm_res = _vlm_query(query_vlm, prompt, images)
            
            if vlm_res:
                panel_used = vlm_res.get("drawings_panel_used", False)
                generated = vlm_res.get("drawing_generated", False)
                if panel_used and generated:
                    vlm_score = 30
                    feedback_lines.append("PASS: VLM verified complete drawing generation workflow trajectory. (+30)")
                elif panel_used:
                    vlm_score = 15
                    feedback_lines.append("PARTIAL: VLM verified drawings panel opened, but generation is unclear. (+15)")
                else:
                    feedback_lines.append("FAIL: VLM did not detect drawing generation workflow. (+0)")
            else:
                feedback_lines.append("WARNING: VLM query returned no valid result. (+0)")
        except ImportError:
            feedback_lines.append("WARNING: Could not import VLM trajectory helpers. Skipping VLM check. (+0)")
        except Exception as e:
            feedback_lines.append(f"WARNING: VLM verification error: {e}")
    else:
        feedback_lines.append("WARNING: VLM not available in this environment. (+0)")
        
    score += vlm_score
    
    passed = score >= 70
    feedback_lines.append(f"\nTotal score: {score}/100. {'PASSED' if passed else 'FAILED'} (threshold: 70).")
    
    return {
        "passed": passed,
        "score": score,
        "feedback": "\n".join(feedback_lines)
    }