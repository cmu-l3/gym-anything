#!/usr/bin/env python3
"""
Verifier for packaging_oee_calculation_tags task.

HYBRID VERIFICATION: 
1. Programmatic File Check: Evaluates if the project was saved and parses exported CSV.
2. Logic Normalization: Cleans and matches algebraic formulas for the OEE calculations.
3. VLM Trajectory Check: Uses visual trajectory frames to ensure the agent interacted 
   with the expression fields in the Data Tags pane (Anti-gaming).

Scoring (100 points total):
  - Project Saved & File Time valid: 10 pts
  - Base Tags Created (PLC_GoodCount, etc.): 10 pts (2 pts each)
  - Calculated Tags Created (TotalParts, etc.): 10 pts (2 pts each)
  - Data Type set to Float for Calculated Tags: 10 pts (2 pts each)
  - OEE Math Logic (Data Source): 45 pts (9 pts per valid expression)
  - VLM Verification (Trajectory confirms UI interaction): 15 pts

Pass threshold: 75 / 100.
"""

import json
import os
import re
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

RESULT_PATH = "C:/Users/Docker/Desktop/CrimsonTasks/flexo_gluer_result.json"
START_TIME_PATH = "C:/tmp/task_start_time.txt"


def normalize_formula(expr: str) -> str:
    """Strip whitespace and outer grouping parens to normalize mathematical expressions."""
    if not expr:
        return ""
    # Remove all whitespace
    s = re.sub(r'\s+', '', str(expr).lower())
    # Remove outer parentheses if they wrap the entire string
    while s.startswith('(') and s.endswith(')'):
        # Ensure they are actually matching outer parens
        depth = 0
        outer_match = True
        for i, char in enumerate(s):
            if char == '(':
                depth += 1
            elif char == ')':
                depth -= 1
            if depth == 0 and i < len(s) - 1:
                outer_match = False
                break
        if outer_match:
            s = s[1:-1]
        else:
            break
    return s


def build_vlm_prompt():
    """Build VLM prompt to verify trajectory frames for Data Source expression entry."""
    return """Examine these sequential screenshots of a user operating Red Lion Crimson 3.0.
Task: Verify if the user successfully interacted with the 'Data Tags' pane and entered mathematical formulas.

Look for:
1. Is the user in the "Data Tags" section (Navigation pane on the left)?
2. Are they creating new tags?
3. Did they type mathematical expressions (e.g., addition, multiplication, division with PLC_ tags) into a "Data", "Source", or "Expression" field in the tag properties?

Respond in JSON format exactly like this:
{
    "interacted_with_tags": true/false,
    "entered_expressions": true/false,
    "confidence": "low/medium/high",
    "reasoning": "Brief explanation of what is visible in the frames."
}"""


def verify_packaging_oee_calculation_tags(traj, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Framework error: copy_from_env unavailable."}

    score = 0
    feedback_parts = []
    
    metadata = task_info.get("metadata", {})
    base_tags_required = [t.lower() for t in metadata.get("base_tags", [])]
    calc_tags_required = [t.lower() for t in metadata.get("calc_tags", [])]
    acceptable_formulas = metadata.get("acceptable_formulas", {})

    # 1. Read Start Time
    start_time = 0
    tmp_start = tempfile.NamedTemporaryFile(delete=False)
    tmp_start.close()
    try:
        copy_from_env(START_TIME_PATH, tmp_start.name)
        with open(tmp_start.name, 'r') as f:
            start_time = int(f.read().strip())
    except Exception as e:
        logger.warning(f"Could not read start time: {e}")
    finally:
        os.unlink(tmp_start.name)

    # 2. Read Export Result JSON
    result = {}
    tmp_res = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
    tmp_res.close()
    try:
        copy_from_env(RESULT_PATH, tmp_res.name)
        with open(tmp_res.name, "r", encoding="utf-8-sig") as f:
            result = json.load(f)
    except FileNotFoundError:
        return {"passed": False, "score": 0, "feedback": "Result file not found - export hook failed or project not saved."}
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Error parsing result: {e}"}
    finally:
        os.unlink(tmp_res.name)

    # CRITERION 1: Project Saved (10 pts)
    project_found = result.get("project_found", False)
    file_mtime = result.get("file_mtime", 0)
    
    if project_found:
        if start_time > 0 and file_mtime >= start_time:
            score += 10
            feedback_parts.append("Project saved during session (10/10)")
        else:
            score += 5
            feedback_parts.append("Project saved but timestamp precedes session (5/10)")
    else:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Project 'flexo_gluer_oee.c3' was not found. Agent did not save the project."
        }

    # CRITERION 2, 3, 4, 5: Tag Parsing
    export_success = result.get("export_success", False)
    tags_exported = result.get("tags", [])
    
    # Map exported tags by lowercase name
    # Crimson CSV headers often look like "Name", "TreatAs", "Source"
    tag_map = {}
    for t in tags_exported:
        # Find the name column, it might be exactly "Name" or have weird spacing
        name_key = next((k for k in t.keys() if 'name' in k.lower()), None)
        if name_key and t[name_key]:
            tag_map[t[name_key].strip().lower()] = t

    if export_success and tag_map:
        # Base Tags (10 pts)
        base_found = 0
        for b_tag in base_tags_required:
            if b_tag in tag_map:
                base_found += 1
        b_score = base_found * 2
        score += b_score
        feedback_parts.append(f"Base Tags created: {base_found}/5 ({b_score}/10)")

        # Calc Tags & Properties
        calc_found = 0
        float_correct = 0
        formulas_correct = 0
        
        for c_tag in calc_tags_required:
            if c_tag in tag_map:
                calc_found += 1
                t_data = tag_map[c_tag]
                
                # Check TreatAs = Float
                treat_key = next((k for k in t_data.keys() if 'treat' in k.lower()), None)
                if treat_key:
                    treat_val = str(t_data[treat_key]).lower()
                    if 'float' in treat_val or 'real' in treat_val:
                        float_correct += 1

                # Check Formula / Source
                source_key = next((k for k in t_data.keys() if 'source' in k.lower() or 'data' in k.lower()), None)
                if source_key:
                    actual_expr = normalize_formula(t_data[source_key])
                    valid_exprs = [normalize_formula(e) for e in acceptable_formulas.get(c_tag, [])]
                    if actual_expr in valid_exprs:
                        formulas_correct += 1
                    else:
                        logger.info(f"Formula mismatch for {c_tag}: Expected one of {valid_exprs}, got {actual_expr}")
        
        c_score = calc_found * 2
        f_score = float_correct * 2
        m_score = formulas_correct * 9
        
        score += (c_score + f_score + m_score)
        feedback_parts.append(f"Calc Tags created: {calc_found}/5 ({c_score}/10)")
        feedback_parts.append(f"Float Types correct: {float_correct}/5 ({f_score}/10)")
        feedback_parts.append(f"OEE Formulas correct: {formulas_correct}/5 ({m_score}/45)")
    else:
        feedback_parts.append("Tag export failed or empty. Skipping programmatic tag checks (0/75)")

    # CRITERION 6: VLM Trajectory Verification (15 pts)
    # Used as an anti-gaming check and a fallback if UI automation fails
    vlm_score = 0
    try:
        from gym_anything.vlm import sample_trajectory_frames, query_vlm
        frames = sample_trajectory_frames(traj, n=4)
        if frames:
            vlm_res = query_vlm(images=frames, prompt=build_vlm_prompt())
            if vlm_res and vlm_res.get("parsed"):
                parsed = vlm_res["parsed"]
                if parsed.get("interacted_with_tags"):
                    vlm_score += 5
                if parsed.get("entered_expressions"):
                    vlm_score += 10
                
                feedback_parts.append(f"VLM Confirmed UI Interaction: {vlm_score}/15 pts")
                logger.info(f"VLM reasoning: {parsed.get('reasoning')}")
        else:
            feedback_parts.append("VLM Verification: No frames available (0/15)")
    except Exception as e:
        logger.warning(f"VLM verification failed: {e}")
        feedback_parts.append("VLM Verification: Skipped due to error (0/15)")

    score += vlm_score

    # Determine pass/fail
    passed = score >= 75
    
    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback_parts)
    }