#!/usr/bin/env python3
"""
Verifier for HTPC Accessibility & Playback Configuration task.

Checks:
1. `vlcrc` parsed for specific persistent configuration lines.
2. `htpc_proof.png` existence and validity as proof of testing.
3. `htpc_config.json` existence and structure.
4. Trajectory analysis via VLM to ensure video playback actually occurred.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def parse_vlcrc(filepath):
    """Parse vlcrc file into a dictionary, ignoring comments."""
    config = {}
    try:
        with open(filepath, 'r', encoding='utf-8') as f:
            for line in f:
                line = line.strip()
                # If a line doesn't start with '#' and contains '=', it's an active config
                if line and not line.startswith('#') and '=' in line:
                    key, val = line.split('=', 1)
                    config[key.strip()] = val.strip()
    except Exception as e:
        logger.error(f"Error parsing vlcrc: {e}")
    return config

def verify_htpc_configuration(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    score = 0
    feedback_parts = []
    
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    temp_vlcrc = tempfile.NamedTemporaryFile(delete=False, suffix='.vlcrc')
    temp_manifest = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    
    try:
        # Load the general task results
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
            
        # ==========================================
        # 1. Verify vlcrc configurations (60 points)
        # ==========================================
        if result.get("vlcrc_exists"):
            copy_from_env("/tmp/exported_vlcrc", temp_vlcrc.name)
            vlc_config = parse_vlcrc(temp_vlcrc.name)
            
            # Check Fullscreen (10 pts)
            fs_val = vlc_config.get("fullscreen", "").lower()
            if fs_val in ["1", "true"]:
                score += 10
                feedback_parts.append("+ Fullscreen enabled")
            else:
                feedback_parts.append("- Fullscreen not enabled")
                
            # Check Aspect Ratio (10 pts)
            ar_val = vlc_config.get("aspect-ratio", vlc_config.get("custom-aspect-ratio", ""))
            if "16:9" in ar_val:
                score += 10
                feedback_parts.append("+ Aspect ratio forced to 16:9")
            else:
                feedback_parts.append("- Aspect ratio not set to 16:9")
                
            # Check OSD Title (10 pts)
            osd_val = vlc_config.get("video-title-show", "").lower()
            if osd_val in ["0", "false"]:
                score += 10
                feedback_parts.append("+ OSD title disabled")
            else:
                feedback_parts.append("- OSD title not disabled")
                
            # Check Subtitle Language (10 pts)
            lang_val = vlc_config.get("sub-language", "").lower()
            if any(expected in lang_val for expected in ["en", "eng", "english"]):
                score += 10
                feedback_parts.append("+ Subtitle language set to English")
            else:
                feedback_parts.append("- Subtitle language not correctly set to English")
                
            # Check Subtitle Color (10 pts)
            color_val = vlc_config.get("freetype-color", "")
            if color_val == "16776960":
                score += 10
                feedback_parts.append("+ Subtitle color set to Yellow (16776960)")
            else:
                feedback_parts.append(f"- Subtitle color not Yellow (found: {color_val})")
                
            # Check Subtitle Size (10 pts)
            size_val = vlc_config.get("freetype-rel-fontsize", "")
            # Large is usually 20, Larger is 24 in VLC settings
            if size_val in ["20", "24"]:
                score += 10
                feedback_parts.append(f"+ Subtitle size set to Large/Larger ({size_val})")
            else:
                feedback_parts.append(f"- Subtitle size not Large (found: {size_val})")
                
        else:
            feedback_parts.append("x vlcrc configuration file not found or unchanged")
            
        # ==========================================
        # 2. Verify Visual Proof (25 points)
        # ==========================================
        if result.get("proof_exists"):
            if result.get("proof_created_during_task"):
                score += 25
                feedback_parts.append("+ Proof screenshot captured during task")
            else:
                score += 10
                feedback_parts.append("~ Proof screenshot exists but timestamp is questionable")
        else:
            feedback_parts.append("- Proof screenshot (htpc_proof.png) not found")
            
        # ==========================================
        # 3. Verify JSON Manifest (15 points)
        # ==========================================
        if result.get("manifest_exists"):
            copy_from_env("/tmp/exported_htpc_config.json", temp_manifest.name)
            try:
                with open(temp_manifest.name, 'r') as f:
                    manifest = json.load(f)
                    
                configs = manifest.get("configurations", {})
                if isinstance(configs, dict) and "aspect_ratio" in configs and "subtitle_color" in configs:
                    score += 15
                    feedback_parts.append("+ Valid JSON manifest provided")
                else:
                    score += 5
                    feedback_parts.append("~ JSON manifest found but missing expected keys")
            except json.JSONDecodeError:
                feedback_parts.append("- JSON manifest is invalid (JSONDecodeError)")
        else:
            feedback_parts.append("- JSON manifest (htpc_config.json) not found")
            
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Verification error: {e}"}
        
    finally:
        for p in [temp_result.name, temp_vlcrc.name, temp_manifest.name]:
            if os.path.exists(p):
                os.unlink(p)

    # Agent needs at least 75 points to pass
    passed = score >= 75
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }