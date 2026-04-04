#!/usr/bin/env python3
"""
Verifier for Enhance Dark Dashcam task
"""

import sys
import os
import logging
import tempfile

# Add utils directory to path - use relative path since verifier runs on host
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))

from vlc_verification_utils import parse_vlc_config

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Try to import image libraries for visual verification
try:
    from PIL import Image
    import numpy as np
    IMAGE_LIBS_AVAILABLE = True
except ImportError:
    IMAGE_LIBS_AVAILABLE = False
    logger.warning("PIL/numpy not available - visual verification will be skipped")


def verify_enhance_dark_dashcam(traj, env_info, task_info):
    """
    Verify enhance dark dashcam task completion.
    
    Checks:
    1. VLC configuration shows brightness increased significantly (≥1.4x)
    2. VLC configuration shows contrast increased (≥1.2x)
    3. Settings are within reasonable bounds (not extreme)
    4. (Optional) Visual frame analysis confirms actual improvement
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    criteria_met = 0
    max_criteria = 6  # Weighted scoring
    feedback_parts = []
    
    # === Part 1: Configuration-Based Verification (Primary) ===
    
    temp_config = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
    
    try:
        # Copy VLC config
        try:
            copy_from_env("/tmp/vlc_enhance_config.txt", temp_config.name)
        except Exception as e:
            logger.error(f"Error copying VLC config: {e}", exc_info=True)
            return {"passed": False, "score": 0, "feedback": f"VLC config not found: {str(e)}"}
        
        if not os.path.exists(temp_config.name) or os.path.getsize(temp_config.name) == 0:
            return {"passed": False, "score": 0, "feedback": "VLC config is empty"}
        
        # Parse configuration
        config = parse_vlc_config(temp_config.name)
        
        # Extract brightness/contrast/gamma settings
        # VLC stores these as float multipliers (1.0 = default/unchanged)
        brightness = float(config.get('brightness', 1.0))
        contrast = float(config.get('contrast', 1.0))
        gamma = float(config.get('gamma', 1.0))
        
        logger.info(f"Detected settings - Brightness: {brightness:.3f}, Contrast: {contrast:.3f}, Gamma: {gamma:.3f}")
        feedback_parts.append(f"Settings: B={brightness:.2f}, C={contrast:.2f}, G={gamma:.2f}")
        
        # Criterion 1: Check brightness increase (weight: 3 points)
        if brightness >= 1.6:
            criteria_met += 3
            feedback_parts.append(f"✅ Excellent brightness increase: {brightness:.2f}x")
        elif brightness >= 1.4:
            criteria_met += 2.5
            feedback_parts.append(f"✅ Good brightness increase: {brightness:.2f}x")
        elif brightness >= 1.2:
            criteria_met += 1.5
            feedback_parts.append(f"⚠️ Moderate brightness increase: {brightness:.2f}x (target ≥1.4x)")
        elif brightness > 1.05:
            criteria_met += 0.5
            feedback_parts.append(f"❌ Insufficient brightness: {brightness:.2f}x (target ≥1.4x)")
        else:
            feedback_parts.append(f"❌ No brightness increase: {brightness:.2f}x")
        
        # Criterion 2: Check contrast increase (weight: 2 points)
        if contrast >= 1.3:
            criteria_met += 2
            feedback_parts.append(f"✅ Strong contrast enhancement: {contrast:.2f}x")
        elif contrast >= 1.2:
            criteria_met += 1.5
            feedback_parts.append(f"✅ Good contrast enhancement: {contrast:.2f}x")
        elif contrast >= 1.1:
            criteria_met += 0.8
            feedback_parts.append(f"⚠️ Modest contrast: {contrast:.2f}x (target ≥1.2x)")
        else:
            feedback_parts.append(f"❌ Insufficient contrast: {contrast:.2f}x")
        
        # Criterion 3: Check gamma adjustment (weight: 1 point, optional bonus)
        if gamma > 1.15:
            criteria_met += 1
            feedback_parts.append(f"✅ Gamma adjusted: {gamma:.2f}")
        elif gamma > 1.05:
            criteria_met += 0.5
            feedback_parts.append(f"ℹ️ Gamma slightly adjusted: {gamma:.2f}")
        else:
            feedback_parts.append(f"ℹ️ Gamma unchanged: {gamma:.2f} (optional)")
        
        # Sanity check: Detect over-processing
        if brightness > 3.0 or contrast > 3.0:
            criteria_met -= 1
            feedback_parts.append(f"⚠️ Warning: Extreme settings (may be over-processed)")
        
        # Check if any enhancement was applied at all
        if brightness <= 1.05 and contrast <= 1.05:
            feedback_parts.append("❌ No meaningful enhancement detected")
            os.unlink(temp_config.name)
            return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}
        
        os.unlink(temp_config.name)
        
    except Exception as e:
        logger.error(f"Config verification failed: {e}", exc_info=True)
        if os.path.exists(temp_config.name):
            os.unlink(temp_config.name)
        return {"passed": False, "score": 0, "feedback": f"Config parsing error: {str(e)}"}
    
    # === Part 2: Visual Frame Analysis (Optional, Bonus Points) ===
    
    visual_bonus = 0
    
    if IMAGE_LIBS_AVAILABLE:
        try:
            # Try to copy enhanced and original frames
            temp_enhanced = tempfile.NamedTemporaryFile(delete=False, suffix='.png')
            temp_original = tempfile.NamedTemporaryFile(delete=False, suffix='.png')
            
            has_frames = True
            try:
                copy_from_env("/tmp/vlc_enhanced_frame.png", temp_enhanced.name)
                copy_from_env("/tmp/vlc_dark_reference.png", temp_original.name)
            except:
                has_frames = False
                logger.info("Visual frames not available for comparison")
            
            if has_frames and os.path.exists(temp_enhanced.name) and os.path.exists(temp_original.name):
                # Analyze brightness improvement
                try:
                    orig_img = Image.open(temp_original.name).convert('L')
                    enhanced_img = Image.open(temp_enhanced.name).convert('L')
                    
                    orig_array = np.array(orig_img)
                    enhanced_array = np.array(enhanced_img)
                    
                    orig_mean = orig_array.mean()
                    enhanced_mean = enhanced_array.mean()
                    
                    if orig_mean > 0:
                        improvement_ratio = (enhanced_mean - orig_mean) / orig_mean
                    else:
                        improvement_ratio = 0
                    
                    logger.info(f"Visual analysis - Original: {orig_mean:.1f}, Enhanced: {enhanced_mean:.1f}, Improvement: {improvement_ratio*100:.1f}%")
                    
                    # Award bonus points for visual improvement
                    if improvement_ratio >= 0.8:
                        visual_bonus = 2
                        feedback_parts.append(f"🌟 Bonus: Excellent visual improvement ({improvement_ratio*100:.0f}%)")
                    elif improvement_ratio >= 0.5:
                        visual_bonus = 1.5
                        feedback_parts.append(f"✅ Bonus: Strong visual improvement ({improvement_ratio*100:.0f}%)")
                    elif improvement_ratio >= 0.3:
                        visual_bonus = 1
                        feedback_parts.append(f"ℹ️ Bonus: Moderate visual improvement ({improvement_ratio*100:.0f}%)")
                    
                    # Check for over-processing (clipping)
                    clipped_pixels = np.sum(enhanced_array >= 250) / enhanced_array.size
                    if clipped_pixels > 0.25:
                        visual_bonus -= 0.5
                        feedback_parts.append(f"⚠️ Warning: {clipped_pixels*100:.0f}% pixels clipped")
                    
                except Exception as e:
                    logger.warning(f"Visual analysis failed: {e}")
            
            # Cleanup temp files
            if os.path.exists(temp_enhanced.name):
                os.unlink(temp_enhanced.name)
            if os.path.exists(temp_original.name):
                os.unlink(temp_original.name)
                
        except Exception as e:
            logger.warning(f"Visual verification error: {e}")
    else:
        feedback_parts.append("ℹ️ Visual verification skipped (libraries not available)")
    
    # Add visual bonus to score
    criteria_met += visual_bonus
    
    # === Part 3: Check Completion Marker ===
    
    temp_marker = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
    try:
        copy_from_env("/tmp/vlc_enhance_completed.txt", temp_marker.name)
        feedback_parts.append("✅ Task completed")
        os.unlink(temp_marker.name)
    except Exception:
        feedback_parts.append("ℹ️ Completion marker not found")
    
    # === Final Assessment ===
    
    # Calculate score (cap at 100)
    # Max possible: 6 from config + 2 from visual = 8 total
    # Scale to 100: (criteria_met / 8) * 100, but boost config-only score
    if visual_bonus > 0:
        score = int((criteria_met / 8) * 100)
    else:
        # If no visual verification, weight config score more heavily
        score = int((criteria_met / 6) * 100)
    
    score = min(score, 100)  # Cap at 100
    
    passed = score >= 70
    
    if score >= 90:
        feedback_parts.append("\n🎉 Excellent! Dashcam footage enhanced perfectly.")
    elif score >= 70:
        feedback_parts.append("\n✅ Task complete! Video brightness improved adequately.")
    elif score >= 50:
        feedback_parts.append("\n⚠️ Partial success. Enhancement applied but could be stronger.")
    else:
        feedback_parts.append("\n❌ Task incomplete. Video remains too dark or effects not properly applied.")
    
    feedback = " | ".join(feedback_parts)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": feedback
    }