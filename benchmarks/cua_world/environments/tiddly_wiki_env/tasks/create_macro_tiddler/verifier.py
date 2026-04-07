#!/usr/bin/env python3
"""
Verifier for create_macro_tiddler task.

Checks:
1. Macro definition tiddler created with correct tag and syntax
2. Dashboard tiddler created using the macro
3. Proper formatting and parameters passed
4. Validates anti-gaming using file modification timestamps & VLM
"""

import os
import json
import logging
import tempfile
import re

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_macro_tiddler(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    params = metadata.get('params', ["project", "client", "status", "deadline", "budget"])
    expected_data = metadata.get('expected_data', [])

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r', encoding='utf-8') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # Resolve contents (either from filesystem or API if file name was weird)
    macro_content = result.get('macro_file_content', '')
    if not macro_content and result.get('macro_api_data', {}).get('text'):
        macro_content = result.get('macro_api_data').get('text')
        macro_tags = str(result.get('macro_api_data').get('tags', ''))
        macro_content += f"\ntags: {macro_tags}"

    dash_content = result.get('dash_file_content', '')
    if not dash_content and result.get('dash_api_data', {}).get('text'):
        dash_content = result.get('dash_api_data').get('text')
        dash_tags = str(result.get('dash_api_data').get('tags', ''))
        dash_content += f"\ntags: {dash_tags}"

    # Anti-gaming checks
    macro_created = result.get('macro_created_during_task', False) or bool(result.get('macro_api_data', {}).get('text'))
    dash_created = result.get('dash_created_during_task', False) or bool(result.get('dash_api_data', {}).get('text'))

    # Criterion 1: Macro tiddler exists and is tagged correctly (20 pts)
    if macro_content:
        score += 10
        feedback_parts.append("Macro tiddler found")
        
        # Check system tag
        if '$:/tags/Macro' in macro_content or 'tags: Macro' in macro_content or 'tags: $:/tags/Macro' in macro_content:
            score += 10
            feedback_parts.append("Macro tag correct")
        else:
            feedback_parts.append("Missing $:/tags/Macro tag")
    else:
        feedback_parts.append("Macro tiddler not found")

    # Criterion 2: Macro valid definition & parameters (20 pts)
    if macro_content:
        # TiddlyWiki allows \define or \procedure
        has_define = re.search(r'\\define\s+project-status', macro_content, re.IGNORECASE)
        has_procedure = re.search(r'\\procedure\s+project-status', macro_content, re.IGNORECASE)
        
        if has_define or has_procedure:
            score += 10
            feedback_parts.append("Valid macro definition block found")
            
            # Check for all required parameters
            params_found = 0
            for param in params:
                if param.lower() in macro_content.lower():
                    params_found += 1
            
            if params_found == len(params):
                score += 10
                feedback_parts.append("All 5 macro parameters present")
            elif params_found >= 3:
                score += 5
                feedback_parts.append(f"Some macro parameters missing ({params_found}/5)")
            else:
                feedback_parts.append(f"Most macro parameters missing ({params_found}/5)")
        else:
            feedback_parts.append("Missing \\define project-status")

    # Criterion 3: Dashboard tiddler exists (15 pts)
    if dash_content:
        score += 15
        feedback_parts.append("Active Projects tiddler found")
    else:
        feedback_parts.append("Active Projects tiddler not found")

    # Criterion 4: Three macro invocations (15 pts)
    if dash_content:
        invocations = len(re.findall(r'<<project-status', dash_content, re.IGNORECASE))
        if invocations >= 3:
            score += 15
            feedback_parts.append(f"Found {invocations} macro invocations")
        elif invocations > 0:
            score += int(invocations * 5)
            feedback_parts.append(f"Found {invocations}/3 macro invocations")
        else:
            feedback_parts.append("No macro invocations found")

    # Criterion 5: Correct Project Data (15 pts)
    if dash_content:
        data_matches = 0
        for item in expected_data:
            if item.lower() in dash_content.lower() or item.replace("$", "").lower() in dash_content.lower():
                data_matches += 1
        
        if data_matches >= 12:  # mostly perfect (out of 15 keywords)
            score += 15
            feedback_parts.append("Project data correctly populated")
        elif data_matches >= 7:
            score += 8
            feedback_parts.append("Project data partially populated")
        else:
            feedback_parts.append(f"Project data largely missing ({data_matches}/15)")

    # Criterion 6: VLM Verification of Workflow (15 pts)
    # Checks if agent genuinely interacted with GUI rather than bypassing it
    vlm_score = 0
    try:
        from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm
        frames = sample_trajectory_frames(traj, n=4)
        final = get_final_screenshot(traj)
        images = frames + [final] if final else frames
        
        if images:
            prompt = """You are analyzing screenshots from an agent interacting with TiddlyWiki.
            Check if the agent used the UI to create tiddlers (clicking '+', typing wikitext like \define or <<project-status, clicking save).
            Respond with JSON ONLY:
            {"gui_interaction_visible": true/false}"""
            
            vlm_res = query_vlm(prompt=prompt, images=images)
            if vlm_res and vlm_res.get('success'):
                parsed = vlm_res.get('parsed', {})
                if parsed.get('gui_interaction_visible'):
                    vlm_score = 15
                    feedback_parts.append("VLM confirms GUI usage")
                else:
                    feedback_parts.append("VLM did not detect UI interactions")
            else:
                feedback_parts.append("VLM check failed/skipped")
    except ImportError:
        feedback_parts.append("VLM module not available")
        # Give partial credit if they passed timestamps check but VLM is physically absent
        if macro_created and dash_created and score >= 50:
            vlm_score = 10
            feedback_parts.append("Bypassed VLM check (system limitation) but timestamp matches")

    score += vlm_score

    # Calculate overall result
    # Crucial requirement: macro must be defined AND dashboard must exist to be a "pass"
    key_criteria_met = bool(macro_content and dash_content and (macro_created or dash_created))
    passed = score >= 60 and key_criteria_met

    if not key_criteria_met:
        feedback_parts.insert(0, "CRITICAL FAILURE: Missing required tiddlers or not created during task")

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }