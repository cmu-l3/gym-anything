#!/usr/bin/env python3
"""Verifier for create_tabbed_project_page task."""

import json
import tempfile
import os
import re

def verify_tabbed_page(traj, env_info, task_info):
    """
    Verify that the tabbed project page and its sub-tiddlers were created correctly.
    Checks existence, tags, caption fields, text content, and tabs macro configuration.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/tabbed_page_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # Anti-gaming check: Were files saved via TiddlyWiki GUI?
    if not result.get('gui_save_detected', False):
        feedback_parts.append("WARNING: No GUI save detected in logs; agent may have manipulated files directly.")
    
    # -------------------------------------------------------------------------
    # 1. Main Tiddler (20 pts total)
    # -------------------------------------------------------------------------
    main = result.get('main', {})
    if main.get('exists'):
        score += 5
        feedback_parts.append("Main tiddler exists")
        
        if main.get('has_macro'):
            score += 10
            feedback_parts.append("Tabs macro present with correct filter")
        else:
            feedback_parts.append("FAIL: Tabs macro missing or incorrect filter")
            
        if main.get('has_default'):
            score += 5
            feedback_parts.append("Default tab set correctly")
        else:
            feedback_parts.append("FAIL: Default tab not set correctly in macro")
    else:
        feedback_parts.append("FAIL: Main tiddler 'CRISPR-Cas9 Project Overview' not found")

    # Helper function to check tab tiddlers
    def check_tab(tab_key, tab_name, expected_caption, keywords):
        tab_score = 0
        tab_data = result.get(tab_key, {})
        
        if tab_data.get('exists'):
            # Must be created during task
            if not tab_data.get('created_during_task'):
                feedback_parts.append(f"FAIL: {tab_name} tiddler was not created during this task session")
                return 0
                
            # Tag check
            tags = tab_data.get('tags', '').lower()
            if 'crispr-cas9 tabs' in tags:
                tab_score += 8
                feedback_parts.append(f"{tab_name} has correct tag")
            else:
                feedback_parts.append(f"FAIL: {tab_name} missing 'CRISPR-Cas9 Tabs' tag")
                
            # Caption check
            caption = tab_data.get('caption', '')
            if caption.strip().lower() == expected_caption.lower():
                tab_score += 4
                feedback_parts.append(f"{tab_name} caption is correct")
            else:
                feedback_parts.append(f"FAIL: {tab_name} caption incorrect or missing")
                
            # Content check (keywords)
            text = tab_data.get('text', '').lower()
            k_found = 0
            for k in keywords:
                if k.lower() in text:
                    k_found += 1
                    
            if k_found == len(keywords):
                tab_score += 8 if tab_key != 'results' and tab_key != 'references' else (5 if tab_key == 'results' else 6)
                feedback_parts.append(f"{tab_name} content has all required information")
            elif k_found > 0:
                partial = 4 if tab_key != 'results' and tab_key != 'references' else 3
                tab_score += partial
                feedback_parts.append(f"Partial content found in {tab_name} ({k_found}/{len(keywords)} expected)")
            else:
                feedback_parts.append(f"FAIL: Required content missing in {tab_name}")
                
            # Special check for Equipment Table
            if tab_key == 'equipment':
                if '|' in text and ('\n|' in text or text.startswith('|')):
                    feedback_parts.append("Equipment text contains a WikiText table")
                else:
                    tab_score = max(0, tab_score - 4)
                    feedback_parts.append("FAIL: Equipment text does not contain a WikiText table syntax (|)")
        else:
            feedback_parts.append(f"FAIL: {tab_name} tiddler not found")
            
        return tab_score

    # -------------------------------------------------------------------------
    # 2. Protocol Tab (20 pts)
    # -------------------------------------------------------------------------
    score += check_tab('protocol', 'Protocol', 'Protocol', ['tp53', 'rnp', 'electroporation', 'sgrna'])

    # -------------------------------------------------------------------------
    # 3. Equipment Tab (20 pts)
    # -------------------------------------------------------------------------
    score += check_tab('equipment', 'Equipment', 'Equipment', ['1081058', 'lonza', 'nucleofector'])

    # -------------------------------------------------------------------------
    # 4. Results Tab (17 pts)
    # -------------------------------------------------------------------------
    score += check_tab('results', 'Results', 'Results', ['73%', 'ice', 'off-target'])

    # -------------------------------------------------------------------------
    # 5. References Tab (18 pts)
    # -------------------------------------------------------------------------
    score += check_tab('references', 'References', 'References', ['10.1126/science.1258096', '10.1038/nprot.2013.143'])

    # -------------------------------------------------------------------------
    # 6. VLM Visual Verification (5 pts)
    # -------------------------------------------------------------------------
    # Use trajectory frames to prove agent progressed to viewing the final tabbed page
    from gym_anything.vlm import query_vlm, sample_trajectory_frames, get_final_screenshot
    
    frames = sample_trajectory_frames(traj, n=3)
    final = get_final_screenshot(traj)
    images_to_check = frames + [final] if final else frames
    
    if images_to_check:
        prompt = """
        You are verifying a TiddlyWiki UI task.
        Look closely at the browser window in these trajectory frames.
        
        Has the user successfully rendered a tabbed interface on a tiddler?
        You are looking for UI tabs (clickable buttons usually grouped together horizontally)
        with labels like "Protocol", "Equipment", "Results", and "References".
        
        Note: Seeing the WikiText source code `<<tabs ...>>` in an editor is NOT enough.
        The tabs must be visibly rendered in reading mode.
        
        Respond ONLY with a JSON object:
        {
            "rendered_tabs_visible": true/false
        }
        """
        try:
            vlm_result = query_vlm(prompt=prompt, images=images_to_check)
            if vlm_result and vlm_result.get("success"):
                parsed = vlm_result.get("parsed", {})
                if parsed.get("rendered_tabs_visible"):
                    score += 5
                    feedback_parts.append("VLM visual verification: Tab UI rendered successfully")
                else:
                    feedback_parts.append("VLM visual verification: Rendered Tab UI not visible in final frames")
            else:
                feedback_parts.append("VLM verification failed to process")
        except Exception as e:
            feedback_parts.append(f"VLM visual verification skipped/failed: {str(e)}")
            
    # Calculate final status
    # Must achieve 60 points minimum AND have the macro in the main tiddler
    passed = score >= 60 and main.get('has_macro', False)

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }