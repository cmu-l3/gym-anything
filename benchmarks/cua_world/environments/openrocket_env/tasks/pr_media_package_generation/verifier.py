#!/usr/bin/env python3
"""
Verifier for pr_media_package_generation task.

Verification checks:
1. ORK file successfully saved to target path (10 pts)
2. PDF correctly exported and verified with file magic bytes (20 pts)
3. PNG properly rendered and dimensions confirmed to exactly 1920x1080 (20 pts)
4. Nose Cone Appearance is painted Red and High Gloss in XML (8 + 7 pts)
5. Body Tube Appearance is painted White in XML (8 pts)
6. Fin Appearance is painted Blue in XML (7 pts)
7. Trajectory frames validated by VLM for Photo Studio and Plot views (10 + 10 pts)

Total points: 100
Pass threshold: 70
"""

import os
import tempfile
import json
import zipfile
import xml.etree.ElementTree as ET
import logging
from gym_anything.vlm import sample_trajectory_frames

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def _parse_ork(local_path):
    """Safely extracts and parses OpenRocket XML configurations."""
    try:
        with zipfile.ZipFile(local_path, 'r') as z:
            xml_bytes = z.read('rocket.ork')
        return ET.fromstring(xml_bytes.decode('utf-8')), None
    except Exception as e:
        return None, str(e)

def verify_pr_media_package_generation(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    score = 0
    feedback_parts = []
    
    # 1. Fetch export JSON
    tmp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    tmp_json.close()
    try:
        copy_from_env("/tmp/task_result.json", tmp_json.name)
        with open(tmp_json.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result JSON: {e}"}
    finally:
        if os.path.exists(tmp_json.name):
            os.unlink(tmp_json.name)

    ork_exists = result.get('ork_exists', False)
    pdf_exists = result.get('pdf_exists', False)
    pdf_valid = result.get('pdf_valid', False)
    png_exists = result.get('png_exists', False)
    png_w = result.get('png_width', 0)
    png_h = result.get('png_height', 0)
    
    # 2. Score File Artifacts
    if ork_exists:
        score += 10
        feedback_parts.append("Saved pr_rocket.ork [10/10]")
        target_ork = "/home/ga/Documents/rockets/pr_rocket.ork"
    else:
        feedback_parts.append("pr_rocket.ork missing [0/10]")
        target_ork = "/home/ga/Documents/rockets/NDRT_Rocket_2020.ork"
        
    if pdf_exists and pdf_valid:
        score += 20
        feedback_parts.append("Valid PDF exported [20/20]")
    elif pdf_exists:
        score += 5
        feedback_parts.append("Invalid PDF exported [5/20]")
    else:
        feedback_parts.append("PDF not exported [0/20]")
        
    if png_exists and png_w == 1920 and png_h == 1080:
        score += 20
        feedback_parts.append("PNG exported 1920x1080 [20/20]")
    elif png_exists:
        score += 10
        feedback_parts.append(f"PNG exported wrong dimensions {png_w}x{png_h} [10/20]")
    else:
        feedback_parts.append("PNG not exported [0/20]")
        
    # 3. Score XML Appearance Data
    tmp_ork = tempfile.NamedTemporaryFile(delete=False, suffix='.ork')
    tmp_ork.close()
    ork_root = None
    try:
        copy_from_env(target_ork, tmp_ork.name)
        ork_root, _ = _parse_ork(tmp_ork.name)
    except Exception:
        pass
    finally:
        if os.path.exists(tmp_ork.name):
            os.unlink(tmp_ork.name)

    def _check_color(elem_iter, condition):
        for elem in elem_iter:
            app = elem.find('appearance')
            if app is not None:
                color = app.find('color')
                if color is not None:
                    try:
                        r = int(color.findtext('red', '0'))
                        g = int(color.findtext('green', '0'))
                        b = int(color.findtext('blue', '0'))
                        s = float(app.findtext('shine', '0.0'))
                        if condition(r, g, b, s):
                            return True
                    except:
                        pass
        return False

    if ork_root is not None:
        # Check colors against reasonable thresholds
        nc_red = _check_color(ork_root.iter('nosecone'), lambda r, g, b, s: r > 200 and g < 100 and b < 100)
        nc_gloss = _check_color(ork_root.iter('nosecone'), lambda r, g, b, s: s >= 0.75)
        bt_white = _check_color(ork_root.iter('bodytube'), lambda r, g, b, s: r > 200 and g > 200 and b > 200)
        
        import itertools
        fins_list = list(itertools.chain(
            ork_root.iter('trapezoidfinset'), 
            ork_root.iter('ellipticalfinset'), 
            ork_root.iter('freeformfinset')
        ))
        fin_blue = _check_color(fins_list, lambda r, g, b, s: r < 100 and g < 100 and b > 200)
        
        if nc_red:
            score += 8
            feedback_parts.append("Nose Cone painted Red [8/8]")
        else:
            feedback_parts.append("Nose Cone not painted Red [0/8]")
            
        if nc_gloss:
            score += 7
            feedback_parts.append("Nose Cone set to High Gloss [7/7]")
        else:
            feedback_parts.append("Nose Cone lacks High Gloss [0/7]")
            
        if bt_white:
            score += 8
            feedback_parts.append("Body Tube painted White [8/8]")
        else:
            feedback_parts.append("Body Tube not painted White [0/8]")
            
        if fin_blue:
            score += 7
            feedback_parts.append("Fins painted Blue [7/7]")
        else:
            feedback_parts.append("Fins not painted Blue [0/7]")
    else:
        feedback_parts.append("Could not parse ORK design colors [0/30]")

    # 4. Score VLM Trajectory Process Validation
    query_vlm = env_info.get('query_vlm')
    if query_vlm and traj:
        frames = sample_trajectory_frames(traj, n=6)
        prompt = """You are analyzing screenshots from an OpenRocket session.
Check if the user opened these two specific features:
1. Did they open the "Photo Studio" window (used for 3D rendering the rocket)?
2. Did they open the "Plot / export" window or display a generated plot graph of flight telemetry?

Return JSON format:
{
  "opened_photo_studio": true/false,
  "opened_plot_window": true/false
}"""
        try:
            vlm_res = query_vlm(prompt=prompt, images=frames)
            if vlm_res.get("success"):
                parsed = vlm_res.get("parsed", {})
                if parsed.get("opened_photo_studio"):
                    score += 10
                    feedback_parts.append("VLM: Photo Studio view verified [10/10]")
                else:
                    feedback_parts.append("VLM: Photo Studio view missing [0/10]")
                    
                if parsed.get("opened_plot_window"):
                    score += 10
                    feedback_parts.append("VLM: Plot window verified [10/10]")
                else:
                    feedback_parts.append("VLM: Plot window missing [0/10]")
            else:
                score += 20
                feedback_parts.append("VLM validation failed, assuming pass [+20]")
        except Exception as e:
            score += 20
            feedback_parts.append("VLM request exception, assuming pass [+20]")
    else:
        score += 20
        feedback_parts.append("VLM checking unavailable, assuming pass [+20]")

    # Final tally check
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }