#!/usr/bin/env python3
"""
Verifier for create_venn_diagram task.

Verification Strategy:
1. File Verification (Programmatic):
   - Check if /home/ga/Documents/cloud_services_venn.eddx exists and is a valid ZIP/EDDX.
   - Extract XML content and search for required text labels (IaaS, PaaS, SaaS, etc.).
   - Check file timestamp to prevent pre-caching cheat.

2. Visual Verification (VLM):
   - Use trajectory frames to confirm the agent actually built a Venn diagram.
   - Verify visual structure: 3 overlapping circles, distinct colors, labels visible.
"""

import json
import os
import tempfile
import zipfile
import logging
import time

# Framework VLM imports (assumed available in environment)
try:
    from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm
except ImportError:
    # Fallback for testing outside framework
    def sample_trajectory_frames(traj, n=5): return []
    def get_final_screenshot(traj): return None
    def query_vlm(images, prompt): return {"success": False, "error": "VLM not available"}

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_venn_diagram(traj, env_info, task_info):
    """
    Verify the creation of a Cloud Services Venn diagram.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    required_strings = metadata.get('required_strings', [])
    min_size = metadata.get('min_file_size_bytes', 5000)

    score = 0
    feedback_parts = []
    
    # 1. Get task result JSON
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load task result: {e}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    # 2. Check File Existence & Timestamp (Anti-gaming)
    if not result.get('output_exists', False):
        return {"passed": False, "score": 0, "feedback": "Output file cloud_services_venn.eddx not found."}
    
    score += 10
    feedback_parts.append("File exists")

    if result.get('file_created_during_task', False):
        score += 10
        feedback_parts.append("File created during task")
    else:
        feedback_parts.append("File timestamp invalid (created before task)")

    if result.get('output_size_bytes', 0) > min_size:
        score += 5
        feedback_parts.append("File size legitimate")
    else:
        feedback_parts.append("File too small (likely empty)")

    # 3. Content Verification (Unzip .eddx and search XML)
    temp_eddx = tempfile.NamedTemporaryFile(delete=False, suffix='.eddx')
    content_score = 0
    found_strings = []
    
    try:
        copy_from_env(result['output_path'], temp_eddx.name)
        
        # EdrawMax files are ZIP archives containing XMLs
        with zipfile.ZipFile(temp_eddx.name, 'r') as zf:
            # Aggregate all text content from XML files in the archive
            full_text = ""
            for filename in zf.namelist():
                if filename.endswith(".xml"):
                    try:
                        full_text += zf.read(filename).decode('utf-8', errors='ignore')
                    except:
                        pass
            
            # Check for required strings
            # Weight: 35 points total for content
            # Labels (IaaS, PaaS, SaaS): 5 pts each (15 total)
            # Title: 5 pts
            # Region content: 15 pts distributed
            
            if "IaaS" in full_text: content_score += 5; found_strings.append("IaaS")
            if "PaaS" in full_text: content_score += 5; found_strings.append("PaaS")
            if "SaaS" in full_text: content_score += 5; found_strings.append("SaaS")
            
            if "Cloud Service Models" in full_text: content_score += 5; found_strings.append("Title")
            
            regions_found = 0
            if "Virtual Machines" in full_text: regions_found += 1
            if "App Engine" in full_text: regions_found += 1
            if "Office Suite" in full_text: regions_found += 1
            if "Scalability" in full_text: regions_found += 1
            
            # 15 points max for regions (approx 4 pts each)
            content_score += min(15, regions_found * 4)
            if regions_found > 0:
                found_strings.append(f"{regions_found} region descriptions")

    except zipfile.BadZipFile:
        feedback_parts.append("File is not a valid EdrawMax (.eddx) archive")
    except Exception as e:
        feedback_parts.append(f"Error inspecting file content: {str(e)}")
    finally:
        if os.path.exists(temp_eddx.name):
            os.unlink(temp_eddx.name)
            
    score += content_score
    feedback_parts.append(f"Content check found: {', '.join(found_strings)}")

    # 4. VLM Verification (Visual Structure)
    # 40 points allocated to visual confirmation
    vlm_score = 0
    
    frames = sample_trajectory_frames(traj, n=4)
    final_frame = get_final_screenshot(traj)
    if final_frame:
        frames.append(final_frame)
    
    if frames:
        prompt = """
        You are verifying a task to create a Venn diagram in EdrawMax.
        Look at these screenshots of the agent's workflow.
        
        Check for:
        1. Three overlapping circles (Venn diagram structure).
        2. Text labels 'IaaS', 'PaaS', 'SaaS' visible on the circles.
        3. Different colors used for the circles (e.g., blue, green, orange).
        4. A title 'Cloud Service Models Comparison' at the top.
        
        JSON Output:
        {
            "is_venn_diagram": boolean,
            "has_three_circles": boolean,
            "has_distinct_colors": boolean,
            "labels_visible": boolean,
            "confidence": "high/medium/low"
        }
        """
        
        vlm_resp = query_vlm(images=frames, prompt=prompt)
        
        if vlm_resp and vlm_resp.get("success"):
            parsed = vlm_resp.get("result", {}) # Assuming result key based on typical usage, or 'parsed'
            if not parsed and "parsed" in vlm_resp:
                parsed = vlm_resp["parsed"]
                
            if isinstance(parsed, str):
                # Handle case where result might be a raw string
                try:
                    import re
                    json_match = re.search(r'\{.*\}', parsed, re.DOTALL)
                    if json_match:
                        parsed = json.loads(json_match.group(0))
                    else:
                        parsed = {}
                except:
                    parsed = {}

            if parsed.get("is_venn_diagram") or parsed.get("has_three_circles"):
                vlm_score += 20
                feedback_parts.append("VLM confirmed Venn structure")
                
            if parsed.get("has_distinct_colors"):
                vlm_score += 10
                feedback_parts.append("VLM confirmed colors")
                
            if parsed.get("labels_visible"):
                vlm_score += 10
                feedback_parts.append("VLM confirmed labels")
        else:
            # Fallback if VLM fails but file content was good
            if content_score > 20:
                vlm_score += 20
                feedback_parts.append("VLM failed, fallback credit based on text content")

    score += vlm_score

    # Final Pass Logic
    # Must have file, valid timestamp, and either strong content matches OR strong visual confirmation
    passed = (
        result.get('output_exists', False) and 
        result.get('file_created_during_task', False) and
        score >= 60
    )

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }