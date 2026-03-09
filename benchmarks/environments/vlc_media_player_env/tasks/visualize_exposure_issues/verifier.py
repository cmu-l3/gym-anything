#!/usr/bin/env python3
"""
Verifier for Visualize Exposure Issues task
"""

import sys
import os
import logging
import tempfile
import json

# Add utils directory to path - use relative path since verifier runs on host
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))

from vlc_verification_utils import (
    setup_verification_environment,
    cleanup_verification_environment
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Check if PIL and numpy are available for advanced image analysis
try:
    from PIL import Image
    import numpy as np
    ADVANCED_ANALYSIS = True
except ImportError:
    logger.warning("PIL or numpy not available - using basic image analysis")
    ADVANCED_ANALYSIS = False


def verify_visualize_exposure_issues(traj, env_info, task_info):
    """
    Verify visualize exposure issues task completion.
    
    Checks:
    1. Video filter enabled in VLC config
    2. Snapshot file exists and has reasonable quality
    3. Snapshot shows filtered visualization (not normal playback)
    
    VLC video filters checked:
    - gradient (edge detection)
    - extract (color/brightness extraction)
    - threshold (binary black/white)
    - posterize (reduced tones)
    - sepia (tonal range)
    - grayscale (tonal visualization)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    criteria_met = 0
    total_criteria = 3
    feedback_parts = []
    
    # Copy and parse result JSON
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    
    try:
        copy_from_env("/tmp/vlc_exposure_result.json", temp_result.name)
        
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
        
        filter_enabled = result.get('filter_enabled', False)
        filter_names = result.get('filter_names', '')
        snapshot_found = result.get('snapshot_found', False)
        snapshot_size_kb = result.get('snapshot_size_kb', 0)
        
        os.unlink(temp_result.name)
        
    except Exception as e:
        logger.error(f"Error reading result JSON: {e}", exc_info=True)
        return {"passed": False, "score": 0, "feedback": f"Error reading result: {str(e)}"}
    
    # Criterion 1: Check if video filter is enabled
    visualization_filters = ['gradient', 'extract', 'threshold', 'posterize', 'sepia', 'grayscale']
    
    if filter_enabled and any(f in filter_names.lower() for f in visualization_filters):
        criteria_met += 1
        matched_filters = [f for f in visualization_filters if f in filter_names.lower()]
        feedback_parts.append(f"✅ Video filter enabled: {', '.join(matched_filters)}")
    elif filter_enabled:
        criteria_met += 0.5  # Some filter enabled, but not ideal for visualization
        feedback_parts.append(f"⚠️ Video filter enabled ({filter_names}), but not optimal for exposure visualization")
    else:
        feedback_parts.append("❌ No video filter detected in VLC config")
    
    # Criterion 2: Check if snapshot exists and has reasonable quality
    if not snapshot_found:
        feedback_parts.append("❌ Snapshot not found")
        
        # Calculate score and return early
        score = int((criteria_met / total_criteria) * 100)
        feedback = " | ".join(feedback_parts)
        
        return {
            "passed": False,
            "score": score,
            "feedback": feedback + " | You need to capture a snapshot (Shift+S) showing the filtered visualization"
        }
    
    # Snapshot exists
    if snapshot_size_kb > 50:
        criteria_met += 1
        feedback_parts.append(f"✅ Snapshot captured ({snapshot_size_kb} KB)")
    elif snapshot_size_kb > 10:
        criteria_met += 0.5
        feedback_parts.append(f"⚠️ Snapshot captured but small ({snapshot_size_kb} KB)")
    else:
        feedback_parts.append(f"❌ Snapshot too small ({snapshot_size_kb} KB)")
    
    # Criterion 3: Analyze snapshot to verify it shows filtered video
    if snapshot_found:
        success, file_info, error = setup_verification_environment(
            copy_from_env,
            "/tmp/vlc_exposure_snapshot.png",
            file_type='image'
        )
        
        if success and ADVANCED_ANALYSIS:
            try:
                img = Image.open(file_info['data']['filepath'])
                img_array = np.array(img)
                
                # Check image characteristics that suggest filtering
                # Filtered images typically have:
                # 1. Reduced color diversity (fewer unique colors)
                # 2. Higher contrast (higher std deviation)
                # 3. Unusual color distributions
                
                if len(img_array.shape) == 3 and img_array.shape[2] >= 3:
                    # Color image
                    # Calculate unique colors (sample to avoid memory issues)
                    sample_size = min(img_array.shape[0] * img_array.shape[1], 100000)
                    flat_img = img_array.reshape(-1, img_array.shape[2])
                    sample_indices = np.random.choice(flat_img.shape[0], sample_size, replace=False)
                    sampled = flat_img[sample_indices]
                    unique_colors = len(np.unique(sampled, axis=0))
                    color_diversity = unique_colors / sample_size
                    
                    # Calculate contrast
                    gray = np.mean(img_array, axis=2)
                    std_dev = np.std(gray)
                    
                    # Check for high contrast edges (gradient-like)
                    edges = np.abs(np.diff(gray, axis=0)).mean() + np.abs(np.diff(gray, axis=1)).mean()
                    
                    # Heuristics for filtered images:
                    # - Low color diversity (< 0.3) suggests posterize, threshold, or extract
                    # - High std dev (> 70) suggests high contrast filters
                    # - High edge intensity (> 20) suggests gradient filter
                    
                    looks_filtered = (color_diversity < 0.3) or (std_dev > 70) or (edges > 20)
                    
                    # Check for near-grayscale (gradient/threshold often produce grayscale-ish output)
                    r_std = np.std(img_array[:, :, 0])
                    g_std = np.std(img_array[:, :, 1])
                    b_std = np.std(img_array[:, :, 2])
                    channel_diff = max(r_std, g_std, b_std) - min(r_std, g_std, b_std)
                    is_grayscale_ish = channel_diff < 20
                    
                    if looks_filtered:
                        criteria_met += 1
                        feedback_parts.append(
                            f"✅ Snapshot shows filtered visualization "
                            f"(diversity: {color_diversity:.2%}, contrast: {std_dev:.1f}, edges: {edges:.1f})"
                        )
                    elif is_grayscale_ish and std_dev > 40:
                        criteria_met += 0.7
                        feedback_parts.append(
                            f"⚠️ Snapshot may show filtering (grayscale-like, contrast: {std_dev:.1f})"
                        )
                    else:
                        criteria_met += 0.3  # Partial credit for having a snapshot
                        feedback_parts.append(
                            f"⚠️ Snapshot may show normal playback rather than filtered view "
                            f"(diversity: {color_diversity:.2%}, contrast: {std_dev:.1f})"
                        )
                else:
                    # Grayscale image - likely filtered
                    std_dev = np.std(img_array)
                    if std_dev > 40:
                        criteria_met += 1
                        feedback_parts.append(f"✅ Snapshot shows grayscale filtered view (contrast: {std_dev:.1f})")
                    else:
                        criteria_met += 0.5
                        feedback_parts.append(f"⚠️ Grayscale snapshot but low contrast ({std_dev:.1f})")
                
                cleanup_verification_environment(file_info.get('temp_dir'))
                
            except Exception as e:
                logger.error(f"Error analyzing snapshot: {e}", exc_info=True)
                criteria_met += 0.5  # Partial credit if analysis fails but snapshot exists
                feedback_parts.append(f"⚠️ Snapshot exists but analysis failed: {str(e)}")
        
        elif success and not ADVANCED_ANALYSIS:
            # Basic analysis without PIL/numpy
            # If filter is enabled and snapshot exists, give partial credit
            if filter_enabled:
                criteria_met += 0.7
                feedback_parts.append("⚠️ Snapshot captured (advanced analysis unavailable, assuming filtered)")
            else:
                criteria_met += 0.3
                feedback_parts.append("⚠️ Snapshot captured but no filter detected")
            
            cleanup_verification_environment(file_info.get('temp_dir'))
        
        else:
            feedback_parts.append(f"❌ Error analyzing snapshot: {error}")
    
    # Calculate final score
    score = int((criteria_met / total_criteria) * 100)
    passed = score >= 70
    
    feedback = " | ".join(feedback_parts)
    
    # Additional guidance if failed
    if not passed:
        if not filter_enabled:
            feedback += " | HINT: Open Tools → Effects and Filters (Ctrl+E), go to Video Effects, enable Gradient or Extract filter"
        elif not snapshot_found:
            feedback += " | HINT: After enabling filter, press Shift+S to capture snapshot"
    
    return {
        "passed": passed,
        "score": score,
        "feedback": feedback
    }