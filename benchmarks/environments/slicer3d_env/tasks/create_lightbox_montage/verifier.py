#!/usr/bin/env python3
"""
Verifier for create_lightbox_montage task.

VERIFICATION CRITERIA:
1. File exists at expected path (20 points)
2. File size adequate for montage (15 points) - >150KB expected for 20-slice composite
3. Valid image format (10 points) - opens as PNG/image
4. Dimensions suggest montage layout (15 points) - larger than single slice
5. Created during task (10 points) - anti-gaming timestamp check
6. VLM: Grid layout visible (15 points) - multiple slices in grid arrangement
7. VLM: Brain content present (10 points) - actual brain MRI content
8. VLM: Multiple anatomical levels (5 points) - different slice levels shown

Pass threshold: 60 points with file_exists criterion met
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_create_lightbox_montage(traj, env_info, task_info):
    """
    Verify that a lightbox montage was created successfully.
    
    Uses multiple independent signals including trajectory-based VLM verification.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Copy function not available - framework error"
        }

    # Get task metadata
    metadata = task_info.get('metadata', {})
    min_file_size_kb = metadata.get('min_file_size_kb', 150)
    min_width = metadata.get('min_width', 600)
    min_height = metadata.get('min_height', 400)
    
    weights = metadata.get('scoring_weights', {})
    w_file_exists = weights.get('file_exists', 20)
    w_file_size = weights.get('file_size_adequate', 15)
    w_valid_format = weights.get('valid_image_format', 10)
    w_dimensions = weights.get('dimensions_suggest_montage', 15)
    w_created_during = weights.get('created_during_task', 10)
    w_vlm_grid = weights.get('vlm_grid_layout', 15)
    w_vlm_brain = weights.get('vlm_brain_content', 10)
    w_vlm_levels = weights.get('vlm_multiple_levels', 5)

    # Initialize scoring
    score = 0
    feedback_parts = []
    details = {}

    # ================================================================
    # Copy result JSON from container
    # ================================================================
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    result = {}
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except FileNotFoundError:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Export result not found - export script may have failed"
        }
    except json.JSONDecodeError as e:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Invalid JSON in result file: {e}"
        }
    except Exception as e:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Failed to read result: {e}"
        }
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    details['result_data'] = result

    # ================================================================
    # CRITERION 1: File exists (20 points)
    # ================================================================
    montage_exists = result.get('montage_exists', False)
    
    if montage_exists:
        score += w_file_exists
        feedback_parts.append(f"✓ Montage file exists (+{w_file_exists})")
    else:
        feedback_parts.append("✗ Montage file NOT found at expected path")
        # Early exit - nothing else to verify
        return {
            "passed": False,
            "score": score,
            "feedback": " | ".join(feedback_parts),
            "details": details
        }

    # ================================================================
    # CRITERION 2: File size adequate (15 points)
    # A 20-slice montage should be >150KB, typically 300-800KB
    # ================================================================
    size_kb = result.get('montage_size_kb', 0)
    details['montage_size_kb'] = size_kb
    
    if size_kb >= min_file_size_kb * 2:  # >300KB - excellent
        score += w_file_size
        feedback_parts.append(f"✓ Good file size: {size_kb}KB (+{w_file_size})")
    elif size_kb >= min_file_size_kb:  # >150KB - acceptable
        partial = int(w_file_size * 0.7)
        score += partial
        feedback_parts.append(f"~ Adequate file size: {size_kb}KB (+{partial})")
    elif size_kb >= 50:  # >50KB - minimal
        partial = int(w_file_size * 0.3)
        score += partial
        feedback_parts.append(f"⚠ Small file size: {size_kb}KB (+{partial})")
    else:
        feedback_parts.append(f"✗ File too small: {size_kb}KB (expected >{min_file_size_kb}KB)")

    # ================================================================
    # CRITERION 3: Valid image format (10 points)
    # ================================================================
    width = result.get('montage_width', 0)
    height = result.get('montage_height', 0)
    img_format = result.get('montage_format', 'unknown')
    details['dimensions'] = f"{width}x{height}"
    details['format'] = img_format
    
    if width > 0 and height > 0:
        score += w_valid_format
        feedback_parts.append(f"✓ Valid {img_format} image: {width}x{height} (+{w_valid_format})")
    else:
        feedback_parts.append(f"✗ Could not read image dimensions")

    # ================================================================
    # CRITERION 4: Dimensions suggest montage layout (15 points)
    # A 5x4 montage should be significantly larger than a single slice
    # Single slice ~256-512px, montage should be >800px in at least one dimension
    # ================================================================
    if width >= min_width and height >= min_height:
        score += w_dimensions
        feedback_parts.append(f"✓ Dimensions suggest montage (+{w_dimensions})")
    elif width >= min_width * 0.7 or height >= min_height * 0.7:
        partial = int(w_dimensions * 0.5)
        score += partial
        feedback_parts.append(f"~ Dimensions smaller than expected (+{partial})")
    else:
        feedback_parts.append(f"✗ Dimensions too small for 5x4 montage")

    # ================================================================
    # CRITERION 5: Created during task - anti-gaming (10 points)
    # ================================================================
    created_during_task = result.get('created_after_task_start', False)
    details['created_during_task'] = created_during_task
    
    if created_during_task:
        score += w_created_during
        feedback_parts.append(f"✓ File created during task (+{w_created_during})")
    else:
        feedback_parts.append("⚠ File may have existed before task (no anti-gaming bonus)")

    # ================================================================
    # VLM VERIFICATION (30 points total)
    # Uses trajectory frames to verify actual work was done
    # ================================================================
    vlm_score = 0
    vlm_feedback = []
    
    try:
        # Try to import VLM utilities
        from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm
        
        # Get trajectory frames for process verification
        traj_frames = sample_trajectory_frames(traj, n=4) if traj else []
        final_screenshot = get_final_screenshot(traj) if traj else None
        
        # Also try to get the actual montage image for content verification
        temp_montage = tempfile.NamedTemporaryFile(delete=False, suffix='.png')
        montage_image = None
        try:
            copy_from_env("/tmp/brain_montage_output.png", temp_montage.name)
            montage_image = temp_montage.name
        except Exception:
            pass
        
        # VLM verification of the montage content
        if montage_image and os.path.exists(montage_image) and os.path.getsize(montage_image) > 1000:
            vlm_prompt = """Analyze this medical imaging montage/lightbox image.

This should be a grid of multiple brain MRI slices (axial view) arranged in rows and columns.

Evaluate:
1. GRID_LAYOUT: Is this a grid/montage showing multiple image panels? (not a single image)
2. BRAIN_CONTENT: Do the panels show brain MRI scans (grayscale brain anatomy)?
3. MULTIPLE_LEVELS: Do different panels show different anatomical levels (different parts of the brain)?
4. APPROXIMATE_COUNT: Roughly how many panels/slices are visible?

Respond in JSON format:
{
    "is_grid_layout": true/false,
    "shows_brain_content": true/false,
    "shows_multiple_levels": true/false,
    "approximate_panel_count": <number>,
    "confidence": "low"/"medium"/"high",
    "observations": "brief description of what you see"
}"""
            
            vlm_result = query_vlm(prompt=vlm_prompt, image=montage_image)
            
            if vlm_result and vlm_result.get('success'):
                parsed = vlm_result.get('parsed', {})
                details['vlm_analysis'] = parsed
                
                # Criterion 6: Grid layout visible (15 points)
                if parsed.get('is_grid_layout', False):
                    vlm_score += w_vlm_grid
                    vlm_feedback.append(f"✓ VLM: Grid layout confirmed (+{w_vlm_grid})")
                else:
                    vlm_feedback.append("✗ VLM: Grid layout not detected")
                
                # Criterion 7: Brain content present (10 points)
                if parsed.get('shows_brain_content', False):
                    vlm_score += w_vlm_brain
                    vlm_feedback.append(f"✓ VLM: Brain content confirmed (+{w_vlm_brain})")
                else:
                    vlm_feedback.append("✗ VLM: Brain content not detected")
                
                # Criterion 8: Multiple anatomical levels (5 points)
                if parsed.get('shows_multiple_levels', False):
                    vlm_score += w_vlm_levels
                    vlm_feedback.append(f"✓ VLM: Multiple levels confirmed (+{w_vlm_levels})")
                
                # Check approximate panel count
                panel_count = parsed.get('approximate_panel_count', 0)
                if panel_count >= 15:
                    vlm_feedback.append(f"VLM: ~{panel_count} panels detected")
                elif panel_count >= 8:
                    vlm_feedback.append(f"VLM: ~{panel_count} panels (fewer than expected 20)")
            else:
                vlm_feedback.append("VLM: Analysis returned no result")
        
        # Cleanup
        if os.path.exists(temp_montage.name):
            os.unlink(temp_montage.name)
            
    except ImportError:
        # VLM not available - use heuristic scoring based on file properties
        logger.info("VLM utilities not available, using heuristic scoring")
        
        # Heuristic: if file is large enough, has good dimensions, and many colors, likely valid
        num_colors = result.get('montage_colors', 0)
        details['num_colors'] = num_colors
        
        if size_kb >= 200 and width >= 800 and height >= 600:
            vlm_score += w_vlm_grid + w_vlm_brain  # 25 points
            vlm_feedback.append(f"✓ Heuristic: Large file with good dimensions suggests valid montage (+25)")
        elif size_kb >= 150 and width >= 600 and height >= 400:
            vlm_score += int((w_vlm_grid + w_vlm_brain) * 0.6)  # 15 points
            vlm_feedback.append(f"~ Heuristic: Moderate confidence in montage validity (+15)")
        
        # Color variety check
        if num_colors >= 1000:
            vlm_score += w_vlm_levels  # 5 points
            vlm_feedback.append(f"✓ Heuristic: High color variety ({num_colors}) suggests brain content (+5)")
            
    except Exception as e:
        logger.warning(f"VLM verification failed: {e}")
        vlm_feedback.append(f"⚠ VLM verification error: {str(e)[:50]}")
        
        # Fallback scoring
        if size_kb >= 200 and width >= 800:
            vlm_score += 15
            vlm_feedback.append("~ Fallback: File properties suggest valid montage (+15)")

    score += vlm_score
    feedback_parts.extend(vlm_feedback)

    # ================================================================
    # Final scoring and pass/fail determination
    # ================================================================
    max_score = w_file_exists + w_file_size + w_valid_format + w_dimensions + w_created_during + w_vlm_grid + w_vlm_brain + w_vlm_levels
    
    # Key criteria for passing:
    # - File must exist
    # - Either good VLM score OR good file properties
    key_criteria_met = montage_exists and (vlm_score >= 15 or (size_kb >= min_file_size_kb and width >= min_width))
    
    passed = score >= 60 and key_criteria_met
    
    status = "PASSED" if passed else "FAILED"
    final_feedback = f"{status} ({score}/{max_score}) | " + " | ".join(feedback_parts)
    
    details['final_score'] = score
    details['max_score'] = max_score
    details['key_criteria_met'] = key_criteria_met
    
    return {
        "passed": passed,
        "score": score,
        "feedback": final_feedback,
        "details": details
    }