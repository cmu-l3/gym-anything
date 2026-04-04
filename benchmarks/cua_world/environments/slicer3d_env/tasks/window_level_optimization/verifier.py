#!/usr/bin/env python3
"""
Verifier for Window/Level Optimization task.

VERIFICATION STRATEGY:
1. Check that report exists with valid window/level values (30 pts)
2. Verify W/L values are within clinical ranges (15 pts each preset)
3. Analyze screenshot histograms for appropriate characteristics (10 pts each)
4. Check timestamps to prevent gaming (5 pts)
5. VLM verification of visual quality (10 pts)

CLINICAL WINDOW/LEVEL RANGES:
- Lung: Width 1200-1800, Level -700 to -400
- Soft Tissue: Width 300-500, Level 20-60
- Bone: Width 1500-2500, Level 200-600
"""

import json
import os
import sys
import tempfile
import logging
from typing import Dict, Any, Tuple, Optional

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


# Clinical window/level ranges
WL_RANGES = {
    "lung": {"width_min": 1200, "width_max": 1800, "level_min": -700, "level_max": -400},
    "soft_tissue": {"width_min": 300, "width_max": 500, "level_min": 20, "level_max": 60},
    "bone": {"width_min": 1500, "width_max": 2500, "level_min": 200, "level_max": 600}
}


def check_wl_in_range(width: Optional[float], level: Optional[float], preset: str) -> Tuple[bool, str]:
    """Check if window/level values are within acceptable clinical range."""
    if width is None or level is None:
        return False, f"Missing {preset} window/level values"
    
    try:
        width = float(width)
        level = float(level)
    except (TypeError, ValueError):
        return False, f"Invalid {preset} window/level values (not numeric)"
    
    ranges = WL_RANGES.get(preset, {})
    width_ok = ranges.get("width_min", 0) <= width <= ranges.get("width_max", 10000)
    level_ok = ranges.get("level_min", -10000) <= level <= ranges.get("level_max", 10000)
    
    if width_ok and level_ok:
        return True, f"{preset.replace('_', ' ').title()}: W={width:.0f}, L={level:.0f} (valid)"
    elif not width_ok and not level_ok:
        return False, f"{preset.replace('_', ' ').title()}: W={width:.0f}, L={level:.0f} (both out of range)"
    elif not width_ok:
        return False, f"{preset.replace('_', ' ').title()}: W={width:.0f} out of range ({ranges['width_min']}-{ranges['width_max']})"
    else:
        return False, f"{preset.replace('_', ' ').title()}: L={level:.0f} out of range ({ranges['level_min']}-{ranges['level_max']})"


def analyze_lung_window_screenshot(analysis: Dict) -> Tuple[bool, str]:
    """
    Lung window should show high proportion of dark pixels (air)
    with some mid-range (lung parenchyma detail).
    """
    if not analysis.get("analyzed", False):
        return False, "Lung screenshot not analyzed"
    
    dark_frac = analysis.get("dark_fraction", 0)
    mid_frac = analysis.get("mid_fraction", 0)
    
    # Lung window: expect significant dark areas (air/lungs) and some detail
    # Good lung window: dark_fraction > 0.2 (air visible), std > 40 (contrast)
    if dark_frac > 0.15 and analysis.get("std", 0) > 30:
        return True, f"Lung window characteristics OK (dark: {dark_frac:.2%}, std: {analysis.get('std', 0):.1f})"
    else:
        return False, f"Lung window may not be correct (dark: {dark_frac:.2%}, expected >15%)"


def analyze_soft_tissue_screenshot(analysis: Dict) -> Tuple[bool, str]:
    """
    Soft tissue window should show balanced histogram with
    mid-range dominance (soft tissue visible).
    """
    if not analysis.get("analyzed", False):
        return False, "Soft tissue screenshot not analyzed"
    
    mid_frac = analysis.get("mid_fraction", 0)
    std = analysis.get("std", 0)
    
    # Soft tissue: expect mid-range pixels dominant, moderate contrast
    if mid_frac > 0.3 and std > 25 and std < 100:
        return True, f"Soft tissue window characteristics OK (mid: {mid_frac:.2%}, std: {std:.1f})"
    else:
        return False, f"Soft tissue window may not be optimal (mid: {mid_frac:.2%}, expected >30%)"


def analyze_bone_window_screenshot(analysis: Dict) -> Tuple[bool, str]:
    """
    Bone window should show moderate bright areas (bone)
    with most soft tissue appearing uniformly gray.
    """
    if not analysis.get("analyzed", False):
        return False, "Bone screenshot not analyzed"
    
    bright_frac = analysis.get("bright_fraction", 0)
    std = analysis.get("std", 0)
    
    # Bone window: expect some bright pixels (bone), high contrast
    if bright_frac > 0.02 and std > 20:
        return True, f"Bone window characteristics OK (bright: {bright_frac:.2%}, std: {std:.1f})"
    else:
        return False, f"Bone window may not be correct (bright: {bright_frac:.2%}, expected >2%)"


def verify_window_level_optimization(traj: Dict[str, Any], env_info: Dict[str, Any], task_info: Dict[str, Any]) -> Dict[str, Any]:
    """
    Verify window/level optimization task completion.
    
    Scoring (100 points total):
    - Lung W/L values correct: 15 points
    - Lung screenshot quality: 10 points
    - Soft tissue W/L values correct: 15 points
    - Soft tissue screenshot quality: 10 points
    - Bone W/L values correct: 15 points
    - Bone screenshot quality: 10 points
    - Report completeness: 10 points
    - Screenshots created during task: 5 points
    - VLM visual quality check: 10 points
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    # Get task metadata
    metadata = task_info.get('metadata', {})
    weights = metadata.get('scoring_weights', {})
    
    # Default weights if not specified
    w_lung_wl = weights.get('lung_wl_values', 15)
    w_lung_ss = weights.get('lung_screenshot_quality', 10)
    w_soft_wl = weights.get('soft_tissue_wl_values', 15)
    w_soft_ss = weights.get('soft_tissue_screenshot_quality', 10)
    w_bone_wl = weights.get('bone_wl_values', 15)
    w_bone_ss = weights.get('bone_screenshot_quality', 10)
    w_report = weights.get('report_completeness', 10)
    w_timestamps = weights.get('screenshot_timestamps', 5)
    w_vlm = weights.get('vlm_visual_quality', 10)
    
    # Copy result JSON from container
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    result = {}
    try:
        copy_from_env("/tmp/wl_task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except FileNotFoundError:
        return {"passed": False, "score": 0, "feedback": "Export result not found - export script may have failed"}
    except json.JSONDecodeError as e:
        return {"passed": False, "score": 0, "feedback": f"Invalid JSON in result file: {e}"}
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)
    
    # Initialize scoring
    score = 0
    feedback_parts = []
    details = {}
    
    # Check if Slicer was running
    if not result.get('slicer_was_running', False):
        feedback_parts.append("WARNING: Slicer was not running")
    
    # ============================================================
    # CRITERION 1-2: LUNG WINDOW (25 points)
    # ============================================================
    report_content = result.get('report_content', {})
    
    # Check lung W/L values
    lung_width = report_content.get('lung_width')
    lung_level = report_content.get('lung_level')
    lung_wl_ok, lung_wl_msg = check_wl_in_range(lung_width, lung_level, "lung")
    
    if lung_wl_ok:
        score += w_lung_wl
        feedback_parts.append(f"✅ {lung_wl_msg}")
    else:
        feedback_parts.append(f"❌ {lung_wl_msg}")
    
    details['lung_wl_ok'] = lung_wl_ok
    details['lung_width'] = lung_width
    details['lung_level'] = lung_level
    
    # Check lung screenshot quality
    lung_analysis = result.get('lung_analysis', {})
    lung_ss_ok, lung_ss_msg = analyze_lung_window_screenshot(lung_analysis)
    lung_ss_exists = result.get('lung_screenshot', {}).get('exists', False)
    
    if lung_ss_exists and lung_ss_ok:
        score += w_lung_ss
        feedback_parts.append(f"✅ {lung_ss_msg}")
    elif lung_ss_exists:
        score += w_lung_ss // 2  # Partial credit for having screenshot
        feedback_parts.append(f"⚠️ {lung_ss_msg}")
    else:
        feedback_parts.append("❌ Lung screenshot not found")
    
    details['lung_screenshot_exists'] = lung_ss_exists
    details['lung_screenshot_quality_ok'] = lung_ss_ok
    
    # ============================================================
    # CRITERION 3-4: SOFT TISSUE WINDOW (25 points)
    # ============================================================
    soft_width = report_content.get('soft_tissue_width')
    soft_level = report_content.get('soft_tissue_level')
    soft_wl_ok, soft_wl_msg = check_wl_in_range(soft_width, soft_level, "soft_tissue")
    
    if soft_wl_ok:
        score += w_soft_wl
        feedback_parts.append(f"✅ {soft_wl_msg}")
    else:
        feedback_parts.append(f"❌ {soft_wl_msg}")
    
    details['soft_tissue_wl_ok'] = soft_wl_ok
    details['soft_tissue_width'] = soft_width
    details['soft_tissue_level'] = soft_level
    
    # Check soft tissue screenshot quality
    soft_analysis = result.get('soft_tissue_analysis', {})
    soft_ss_ok, soft_ss_msg = analyze_soft_tissue_screenshot(soft_analysis)
    soft_ss_exists = result.get('soft_tissue_screenshot', {}).get('exists', False)
    
    if soft_ss_exists and soft_ss_ok:
        score += w_soft_ss
        feedback_parts.append(f"✅ {soft_ss_msg}")
    elif soft_ss_exists:
        score += w_soft_ss // 2
        feedback_parts.append(f"⚠️ {soft_ss_msg}")
    else:
        feedback_parts.append("❌ Soft tissue screenshot not found")
    
    details['soft_tissue_screenshot_exists'] = soft_ss_exists
    details['soft_tissue_screenshot_quality_ok'] = soft_ss_ok
    
    # ============================================================
    # CRITERION 5-6: BONE WINDOW (25 points)
    # ============================================================
    bone_width = report_content.get('bone_width')
    bone_level = report_content.get('bone_level')
    bone_wl_ok, bone_wl_msg = check_wl_in_range(bone_width, bone_level, "bone")
    
    if bone_wl_ok:
        score += w_bone_wl
        feedback_parts.append(f"✅ {bone_wl_msg}")
    else:
        feedback_parts.append(f"❌ {bone_wl_msg}")
    
    details['bone_wl_ok'] = bone_wl_ok
    details['bone_width'] = bone_width
    details['bone_level'] = bone_level
    
    # Check bone screenshot quality
    bone_analysis = result.get('bone_analysis', {})
    bone_ss_ok, bone_ss_msg = analyze_bone_window_screenshot(bone_analysis)
    bone_ss_exists = result.get('bone_screenshot', {}).get('exists', False)
    
    if bone_ss_exists and bone_ss_ok:
        score += w_bone_ss
        feedback_parts.append(f"✅ {bone_ss_msg}")
    elif bone_ss_exists:
        score += w_bone_ss // 2
        feedback_parts.append(f"⚠️ {bone_ss_msg}")
    else:
        feedback_parts.append("❌ Bone screenshot not found")
    
    details['bone_screenshot_exists'] = bone_ss_exists
    details['bone_screenshot_quality_ok'] = bone_ss_ok
    
    # ============================================================
    # CRITERION 7: REPORT COMPLETENESS (10 points)
    # ============================================================
    report_exists = result.get('report_exists', False)
    report_valid = result.get('report_valid', False)
    
    if report_exists and report_valid:
        # Check if all fields are present
        all_fields = all([
            lung_width is not None and lung_level is not None,
            soft_width is not None and soft_level is not None,
            bone_width is not None and bone_level is not None
        ])
        if all_fields:
            score += w_report
            feedback_parts.append("✅ Report complete with all W/L values")
        else:
            score += w_report // 2
            feedback_parts.append("⚠️ Report exists but incomplete")
    elif report_exists:
        score += w_report // 4
        feedback_parts.append("⚠️ Report exists but has invalid JSON")
    else:
        feedback_parts.append("❌ Report file not found")
    
    details['report_exists'] = report_exists
    details['report_valid'] = report_valid
    
    # ============================================================
    # CRITERION 8: TIMESTAMP CHECK (5 points)
    # ============================================================
    screenshots_during_task = 0
    for ss_key in ['lung_screenshot', 'soft_tissue_screenshot', 'bone_screenshot']:
        ss_info = result.get(ss_key, {})
        if ss_info.get('created_during_task', False):
            screenshots_during_task += 1
    
    if screenshots_during_task == 3:
        score += w_timestamps
        feedback_parts.append(f"✅ All 3 screenshots created during task")
    elif screenshots_during_task > 0:
        score += (w_timestamps * screenshots_during_task) // 3
        feedback_parts.append(f"⚠️ {screenshots_during_task}/3 screenshots created during task")
    else:
        feedback_parts.append("❌ No screenshots created during task (possible gaming)")
    
    details['screenshots_created_during_task'] = screenshots_during_task
    
    # ============================================================
    # CRITERION 9: VLM VISUAL QUALITY CHECK (10 points)
    # ============================================================
    query_vlm = env_info.get('query_vlm')
    vlm_score = 0
    
    if query_vlm:
        try:
            # Import trajectory frame sampling
            from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
            
            # Get trajectory frames and final screenshot
            frames = sample_trajectory_frames(traj, n=4)
            final_ss = get_final_screenshot(traj)
            
            # Also try to get the saved screenshots
            temp_dir = tempfile.mkdtemp()
            saved_screenshots = []
            
            for ss_name in ['lung_window.png', 'soft_tissue_window.png', 'bone_window.png']:
                temp_ss = os.path.join(temp_dir, ss_name)
                try:
                    copy_from_env(f"/tmp/wl_screenshots/{ss_name}", temp_ss)
                    if os.path.exists(temp_ss) and os.path.getsize(temp_ss) > 1000:
                        saved_screenshots.append(temp_ss)
                except:
                    pass
            
            # Combine images for VLM
            all_images = frames + ([final_ss] if final_ss else []) + saved_screenshots
            
            if all_images:
                vlm_prompt = """You are verifying if a medical imaging agent correctly adjusted window/level settings in 3D Slicer.

The agent should have created 3 different views of a chest CT:
1. LUNG WINDOW: Lungs appear dark gray/black, soft tissue is white, lung vessels/airways visible
2. SOFT TISSUE WINDOW: Balanced gray appearance, mediastinal structures visible, muscles/organs distinguishable  
3. BONE WINDOW: Bones appear bright white, soft tissue is uniformly gray, ribs/spine clearly visible

Look at these images from the task trajectory. Check:
- Do you see evidence of different window/level settings being applied?
- Are there views showing clear lung parenchyma (dark lungs with visible detail)?
- Are there views showing mediastinal soft tissue?
- Are there views highlighting bone structures?

Respond in JSON format:
{
    "different_windows_visible": true/false,
    "lung_window_quality": "poor/acceptable/good",
    "soft_tissue_window_quality": "poor/acceptable/good",
    "bone_window_quality": "poor/acceptable/good",
    "overall_quality": "poor/acceptable/good",
    "reasoning": "brief explanation"
}
"""
                vlm_result = query_vlm(
                    prompt=vlm_prompt,
                    images=all_images[:6]  # Limit to 6 images
                )
                
                if vlm_result.get("success"):
                    parsed = vlm_result.get("parsed", {})
                    overall = parsed.get("overall_quality", "poor")
                    
                    if overall == "good":
                        vlm_score = w_vlm
                        feedback_parts.append("✅ VLM: Good visual quality across presets")
                    elif overall == "acceptable":
                        vlm_score = w_vlm * 2 // 3
                        feedback_parts.append("⚠️ VLM: Acceptable visual quality")
                    else:
                        vlm_score = w_vlm // 3
                        feedback_parts.append(f"❌ VLM: Poor visual quality - {parsed.get('reasoning', 'no details')}")
                    
                    details['vlm_result'] = parsed
                else:
                    feedback_parts.append("⚠️ VLM verification failed")
            
            # Cleanup
            import shutil
            shutil.rmtree(temp_dir, ignore_errors=True)
            
        except Exception as e:
            logger.warning(f"VLM verification error: {e}")
            feedback_parts.append(f"⚠️ VLM verification error: {e}")
    else:
        feedback_parts.append("ℹ️ VLM verification not available")
    
    score += vlm_score
    details['vlm_score'] = vlm_score
    
    # ============================================================
    # FINAL SCORING
    # ============================================================
    
    # Key criteria for passing:
    # - At least 2 of 3 W/L presets correct
    # - Report exists
    # - At least 2 screenshots exist
    presets_correct = sum([lung_wl_ok, soft_wl_ok, bone_wl_ok])
    screenshots_exist = sum([lung_ss_exists, soft_ss_exists, bone_ss_exists])
    
    key_criteria_met = presets_correct >= 2 and report_exists and screenshots_exist >= 2
    passed = score >= 60 and key_criteria_met
    
    details['presets_correct'] = presets_correct
    details['screenshots_exist'] = screenshots_exist
    details['key_criteria_met'] = key_criteria_met
    details['final_score'] = score
    
    feedback_summary = f"Score: {score}/100 | Presets correct: {presets_correct}/3 | Screenshots: {screenshots_exist}/3"
    
    return {
        "passed": passed,
        "score": score,
        "feedback": feedback_summary + " | " + " | ".join(feedback_parts[:5]),
        "details": details
    }