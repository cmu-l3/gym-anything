#!/usr/bin/env python3
"""
Verifier for clean_segmentation_islands task.

VERIFICATION CRITERIA (100 points total):
1. Output file exists (15 points) - cleaned segmentation was saved
2. Island count reduced (25 points) - significantly fewer islands than original
3. Volume preserved (20 points) - 85-100% of original volume retained
4. Main structures intact (20 points) - largest components still present
5. Appropriate island count (10 points) - final count is 1-3 (anatomically correct)
6. VLM visual verification (10 points) - trajectory shows work progression

Pass threshold: 70 points with "island_count_reduced" criterion met
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_clean_segmentation_islands(traj, env_info, task_info):
    """
    Verify that the lung segmentation was cleaned using the Islands effect.
    
    Uses multiple independent signals to prevent gaming:
    - File existence and timestamps
    - Connected component analysis
    - Volume preservation checks
    - VLM trajectory verification
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
    weights = metadata.get('scoring_weights', {})
    
    w_output_exists = weights.get('output_file_exists', 15)
    w_island_reduced = weights.get('island_count_reduced', 25)
    w_volume_preserved = weights.get('volume_preserved', 20)
    w_main_intact = weights.get('main_structures_intact', 20)
    w_appropriate_count = weights.get('appropriate_island_count', 10)
    w_vlm = weights.get('vlm_visual_verification', 10)
    
    expected_cleaned_range = metadata.get('expected_cleaned_island_count', {"min": 1, "max": 3})
    volume_range = metadata.get('volume_retention_range', {"min": 0.85, "max": 1.0})
    
    # Copy result JSON from container
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    result = {}
    try:
        copy_from_env("/tmp/islands_task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except FileNotFoundError:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Export result not found - task may not have completed"
        }
    except json.JSONDecodeError as e:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Invalid JSON in result: {e}"
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
    
    # Initialize scoring
    score = 0
    feedback_parts = []
    details = {}
    
    # ================================================================
    # CRITERION 1: Output file exists (15 points)
    # ================================================================
    output_exists = result.get('output_exists', False)
    file_created = result.get('file_created_during_task', False)
    output_size = result.get('output_size_bytes', 0)
    
    if output_exists and file_created:
        score += w_output_exists
        feedback_parts.append(f"Output file created ({output_size} bytes)")
        details['output_created'] = True
    elif output_exists:
        score += w_output_exists * 0.5
        feedback_parts.append("Output file exists (may be pre-existing)")
        details['output_created'] = False
    else:
        feedback_parts.append("Output file NOT found")
        details['output_created'] = False
        # Critical failure - cannot verify further
        return {
            "passed": False,
            "score": score,
            "feedback": " | ".join(feedback_parts),
            "details": details
        }
    
    # ================================================================
    # CRITERION 2: Island count reduced (25 points)
    # ================================================================
    original_islands = result.get('original_island_count', 0)
    cleaned_islands = result.get('cleaned_island_count', 0)
    islands_removed = result.get('islands_removed', 0)
    
    details['original_islands'] = original_islands
    details['cleaned_islands'] = cleaned_islands
    details['islands_removed'] = islands_removed
    
    if original_islands > 0 and cleaned_islands > 0:
        reduction_ratio = (original_islands - cleaned_islands) / original_islands
        
        if cleaned_islands <= 5 and islands_removed >= 10:
            # Excellent - removed most artifacts
            score += w_island_reduced
            feedback_parts.append(f"Islands: {original_islands}→{cleaned_islands} (removed {islands_removed})")
            details['island_reduction_success'] = True
        elif cleaned_islands < original_islands * 0.5:
            # Good - significant reduction
            score += w_island_reduced * 0.7
            feedback_parts.append(f"Islands reduced: {original_islands}→{cleaned_islands}")
            details['island_reduction_success'] = True
        elif cleaned_islands < original_islands:
            # Some reduction
            score += w_island_reduced * 0.3
            feedback_parts.append(f"Partial reduction: {original_islands}→{cleaned_islands}")
            details['island_reduction_success'] = False
        else:
            feedback_parts.append(f"No island reduction ({cleaned_islands} islands)")
            details['island_reduction_success'] = False
    else:
        feedback_parts.append("Could not analyze island counts")
        details['island_reduction_success'] = False
    
    # ================================================================
    # CRITERION 3: Volume preserved (20 points)
    # ================================================================
    volume_retained = result.get('volume_retained_fraction', 0)
    original_voxels = result.get('original_total_voxels', 0)
    cleaned_voxels = result.get('cleaned_total_voxels', 0)
    
    details['volume_retained'] = volume_retained
    details['original_voxels'] = original_voxels
    details['cleaned_voxels'] = cleaned_voxels
    
    if volume_retained > 0:
        if volume_range['min'] <= volume_retained <= volume_range['max']:
            score += w_volume_preserved
            feedback_parts.append(f"Volume retained: {volume_retained:.1%}")
            details['volume_ok'] = True
        elif volume_retained >= 0.7:
            # Acceptable but not ideal
            score += w_volume_preserved * 0.6
            feedback_parts.append(f"Volume somewhat reduced: {volume_retained:.1%}")
            details['volume_ok'] = True
        elif volume_retained >= 0.5:
            # Too much removed
            score += w_volume_preserved * 0.2
            feedback_parts.append(f"Volume significantly reduced: {volume_retained:.1%}")
            details['volume_ok'] = False
        else:
            feedback_parts.append(f"Volume too low: {volume_retained:.1%}")
            details['volume_ok'] = False
    else:
        feedback_parts.append("Could not calculate volume retention")
        details['volume_ok'] = False
    
    # ================================================================
    # CRITERION 4: Main structures intact (20 points)
    # ================================================================
    main_preserved = result.get('main_structures_preserved', False)
    
    if main_preserved:
        score += w_main_intact
        feedback_parts.append("Main lung structures preserved")
        details['main_preserved'] = True
    elif cleaned_voxels > 0 and volume_retained >= 0.8:
        # Infer from volume retention
        score += w_main_intact * 0.7
        feedback_parts.append("Main structures likely preserved (high volume)")
        details['main_preserved'] = True
    else:
        feedback_parts.append("Main structures may be damaged")
        details['main_preserved'] = False
    
    # ================================================================
    # CRITERION 5: Appropriate island count (10 points)
    # ================================================================
    if cleaned_islands > 0:
        if expected_cleaned_range['min'] <= cleaned_islands <= expected_cleaned_range['max']:
            score += w_appropriate_count
            feedback_parts.append(f"Anatomically correct ({cleaned_islands} regions)")
            details['appropriate_count'] = True
        elif cleaned_islands <= 5:
            score += w_appropriate_count * 0.5
            feedback_parts.append(f"Nearly correct ({cleaned_islands} regions)")
            details['appropriate_count'] = False
        else:
            feedback_parts.append(f"Too many regions remain ({cleaned_islands})")
            details['appropriate_count'] = False
    
    # ================================================================
    # CRITERION 6: VLM Visual Verification (10 points)
    # Uses trajectory frames to verify actual work was done
    # ================================================================
    try:
        from gym_anything.vlm import sample_trajectory_frames, query_vlm
        
        frames = sample_trajectory_frames(traj, n=5)
        
        if frames and len(frames) >= 3:
            vlm_prompt = """Analyze these screenshots from a 3D Slicer medical imaging session.

The task was to clean a lung segmentation using the Islands effect in Segment Editor.

Look for evidence of:
1. Segment Editor module being used (effects toolbar visible)
2. Islands effect being selected or applied
3. A segmentation overlay on CT images
4. Changes to the segmentation between frames (artifacts being removed)
5. Progress through the workflow

Respond in JSON:
{
    "segment_editor_visible": true/false,
    "islands_effect_used": true/false,
    "segmentation_visible": true/false,
    "workflow_progression": true/false,
    "confidence": "low"/"medium"/"high",
    "observations": "brief description"
}"""
            
            vlm_result = query_vlm(images=frames, prompt=vlm_prompt)
            
            if vlm_result and vlm_result.get('success'):
                parsed = vlm_result.get('parsed', {})
                
                segment_editor = parsed.get('segment_editor_visible', False)
                islands_used = parsed.get('islands_effect_used', False)
                seg_visible = parsed.get('segmentation_visible', False)
                progression = parsed.get('workflow_progression', False)
                confidence = parsed.get('confidence', 'low')
                
                vlm_score = 0
                if segment_editor:
                    vlm_score += 3
                if islands_used or seg_visible:
                    vlm_score += 4
                if progression:
                    vlm_score += 3
                
                # Adjust by confidence
                if confidence == 'low':
                    vlm_score = vlm_score * 0.5
                elif confidence == 'medium':
                    vlm_score = vlm_score * 0.75
                
                score += min(vlm_score, w_vlm)
                
                obs = parsed.get('observations', 'No details')[:50]
                feedback_parts.append(f"VLM: {obs}")
                details['vlm_verification'] = parsed
            else:
                feedback_parts.append("VLM verification unavailable")
                details['vlm_verification'] = None
        else:
            feedback_parts.append("Insufficient trajectory frames for VLM")
            details['vlm_verification'] = None
            
    except ImportError:
        logger.info("VLM not available, skipping visual verification")
        feedback_parts.append("VLM not available")
        details['vlm_verification'] = None
    except Exception as e:
        logger.warning(f"VLM verification failed: {e}")
        feedback_parts.append(f"VLM error: {str(e)[:30]}")
        details['vlm_verification'] = None
    
    # ================================================================
    # DETERMINE PASS/FAIL
    # ================================================================
    
    # Key criteria for passing:
    # - Output file exists AND
    # - Island count was reduced OR volume preserved with fewer islands
    key_criteria_met = (
        output_exists and 
        (details.get('island_reduction_success', False) or 
         (cleaned_islands <= 5 and volume_retained >= 0.8))
    )
    
    passed = score >= 70 and key_criteria_met
    
    # Build final feedback
    feedback = " | ".join(feedback_parts)
    
    return {
        "passed": passed,
        "score": int(score),
        "feedback": feedback,
        "details": details
    }