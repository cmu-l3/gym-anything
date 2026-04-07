#!/usr/bin/env python3
"""
Verifier for chem_distillation_data_logger task.

Criteria:
1. Files saved correctly (.c3 and .txt).
2. Data Logger named 'VOC_Emissions' created.
3. Update Rate set to 1 second (1000 ms).
4. Retention set to 30 days.
5. Exact compliance tags added (TT_101, FT_102, AT_105) and forbidden tags absent.
6. Trend Viewer primitive added to a display page.
7. VLM Fallback: If text database fails, verify visually via screenshots.
"""

import os
import json
import re
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Paths in the Windows container
JSON_RESULT_PATH = "C:/Users/Docker/Desktop/CrimsonTasks/distillation_result.json"
TXT_EXPORT_PATH = "C:/Users/Docker/Desktop/CrimsonTasks/distillation_final_export.txt"


def parse_crimson_text_db(content: str):
    """Parse Crimson Text Database into sections."""
    sections = {}
    current_section = None
    
    for line in content.splitlines():
        line = line.strip()
        if not line or line.startswith('//'):
            continue
            
        # Match section headers like [DataLogger.VOC_Emissions]
        sec_match = re.match(r'^\[(.*?)\]$', line)
        if sec_match:
            current_section = sec_match.group(1)
            sections[current_section] = []
        elif current_section:
            sections[current_section].append(line)
            
    return sections


def verify_with_vlm(traj, env_info, task_info):
    """Fallback VLM verification if text DB is missing."""
    logger.info("Falling back to VLM verification...")
    vlm_query = env_info.get('vlm_query') or env_info.get('query_vlm')
    if not vlm_query:
        logger.warning("VLM query function not available.")
        return 0, "Text DB missing and VLM unavailable."
        
    try:
        from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
        frames = sample_trajectory_frames(traj, n=5)
        final = get_final_screenshot(traj)
        images = frames + [final] if final else frames
        
        prompt = """
        Examine these screenshots of a Red Lion Crimson 3.0 session carefully.
        The user was tasked with configuring a Data Log and a Trend Viewer.
        
        Please evaluate the following:
        1. Did the user create a Data Log named exactly "VOC_Emissions"?
        2. Did the user add a Trend Viewer primitive (a graph/chart element) to a display page?
        
        Return a JSON object:
        {
            "log_created": true/false,
            "trend_viewer_added": true/false
        }
        """
        result = vlm_query(images=images, prompt=prompt)
        
        vlm_score = 0
        vlm_feedback = []
        if result and isinstance(result, dict):
            parsed = result.get('parsed', {})
            if parsed.get('log_created'):
                vlm_score += 25
                vlm_feedback.append("VLM confirmed VOC_Emissions log created visually.")
            if parsed.get('trend_viewer_added'):
                vlm_score += 25
                vlm_feedback.append("VLM confirmed Trend Viewer visually.")
                
        return vlm_score, " ".join(vlm_feedback) if vlm_feedback else "VLM could not confirm task completion."
    except Exception as e:
        logger.error(f"VLM verification failed: {e}")
        return 0, f"VLM error: {e}"


def verify_chem_distillation_data_logger(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    score = 0
    feedback_parts = []
    
    metadata = task_info.get('metadata', {})
    req_tags = metadata.get('required_tags', ['TT_101', 'FT_102', 'AT_105'])
    forbidden_tags = metadata.get('forbidden_tags', ['PT_103', 'LT_104'])

    # 1. Retrieve the JSON result
    tmp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    result_data = {}
    try:
        copy_from_env(JSON_RESULT_PATH, tmp_json.name)
        with open(tmp_json.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        logger.error(f"Failed to read JSON result: {e}")
        return {"passed": False, "score": 0, "feedback": "Could not retrieve export JSON."}
    finally:
        if os.path.exists(tmp_json.name):
            os.unlink(tmp_json.name)

    # Base file checks
    if result_data.get("c3_exists"):
        score += 5
        feedback_parts.append("C3 project saved.")
    else:
        feedback_parts.append("C3 project NOT saved.")

    # 2. Retrieve Text Database
    tmp_txt = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
    txt_content = ""
    try:
        copy_from_env(TXT_EXPORT_PATH, tmp_txt.name)
        with open(tmp_txt.name, 'r', encoding='utf-8-sig', errors='ignore') as f:
            txt_content = f.read()
    except Exception as e:
        logger.warning(f"Failed to read text DB: {e}")
    finally:
        if os.path.exists(tmp_txt.name):
            os.unlink(tmp_txt.name)

    # Primary Verification: Programmatic Text Parsing
    if txt_content and result_data.get("txt_exists"):
        score += 5
        feedback_parts.append("Text DB exported.")
        
        sections = parse_crimson_text_db(txt_content)
        
        # Check Data Log existence
        log_section_key = None
        for key in sections.keys():
            if key.startswith('DataLogger.') and 'VOC_Emissions' in key:
                log_section_key = key
                break
                
        if log_section_key:
            score += 20
            feedback_parts.append("VOC_Emissions log found.")
            log_data = "\n".join(sections[log_section_key])
            
            # Check Update Rate (Crimson uses ms)
            if re.search(r'(?i)UpdateRate=1000|Rate=1000|1000', log_data):
                score += 15
                feedback_parts.append("Update rate set to 1 sec.")
            else:
                feedback_parts.append("Update rate incorrect.")
                
            # Check Retention
            if re.search(r'(?i)Retain=30|RetainDays=30|KeepFiles=30|30', log_data):
                score += 15
                feedback_parts.append("Retention set to 30 days.")
            else:
                feedback_parts.append("Retention incorrect.")
                
            # Check Tags
            tags_present = [t for t in req_tags if t in log_data]
            tags_forbidden = [t for t in forbidden_tags if t in log_data]
            
            if len(tags_present) == len(req_tags):
                if len(tags_forbidden) == 0:
                    score += 25
                    feedback_parts.append("Compliance tags exact match.")
                else:
                    score += 10
                    feedback_parts.append(f"Contains forbidden tags: {tags_forbidden}")
            else:
                feedback_parts.append(f"Missing required tags. Found: {tags_present}")
        else:
            feedback_parts.append("VOC_Emissions log NOT found in Text DB.")
            
        # Check Trend Viewer
        trend_found = False
        for key, lines in sections.items():
            if key.startswith('DisplayPages.') and 'Trend' in key:
                trend_found = True
                break
            # Fallback if it's a sub-primitive
            text_block = "\n".join(lines)
            if 'TrendViewer' in text_block or 'Trend' in text_block:
                trend_found = True
                break
                
        # Broad text search just in case structure parsing missed it
        if not trend_found and ('TrendViewer' in txt_content or 'Trend' in txt_content):
            trend_found = True
            
        if trend_found:
            score += 15
            feedback_parts.append("Trend Viewer primitive found.")
        else:
            feedback_parts.append("Trend Viewer primitive NOT found.")

    else:
        # Fallback to VLM if they forgot to save as text DB but made some progress
        feedback_parts.append("Text DB missing; falling back to visual verification.")
        vlm_score, vlm_fb = verify_with_vlm(traj, env_info, task_info)
        score += vlm_score
        feedback_parts.append(vlm_fb)

    passed = score >= 70
    
    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback_parts)
    }