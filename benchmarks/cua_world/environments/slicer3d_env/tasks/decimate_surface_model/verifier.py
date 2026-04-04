#!/usr/bin/env python3
"""
Verifier for decimate_surface_model task.

VERIFICATION CRITERIA:
1. Output file exists at expected path (20 points)
2. File was created during task execution (10 points) - anti-gaming
3. Polygon count reduced by at least 50% (30 points)
4. Output model is geometrically valid (15 points)
5. Brain shape is preserved - not over-decimated (15 points)
6. File size is smaller than original (10 points)

Pass threshold: 70 points with output_exists AND polygon_reduction >= 50%
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_decimate_surface_model(traj, env_info, task_info):
    """
    Verify that the agent successfully decimated a 3D surface model.
    
    Uses copy_from_env to retrieve results from the container.
    Multi-criteria scoring with anti-gaming timestamp checks.
    
    Args:
        traj: Trajectory data (contains screenshots)
        env_info: Environment info including copy_from_env function
        task_info: Task metadata including expected values
        
    Returns:
        dict with 'passed', 'score', 'feedback', and optional 'details'
    """
    # Get copy function from environment
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {
            "passed": False,
            "score": 0,
            "feedback": "ERROR: copy_from_env not available - framework error"
        }
    
    # Get metadata with defaults
    metadata = task_info.get('metadata', {})
    expected_output = metadata.get('expected_output_path', 
                                   '/home/ga/Documents/SlicerData/Exports/brain_decimated.vtk')
    min_reduction = metadata.get('minimum_reduction_percent', 50)
    min_valid_polys = metadata.get('min_valid_polygons', 5000)
    
    # Get scoring weights
    weights = metadata.get('scoring_weights', {})
    w_exists = weights.get('output_file_exists', 20)
    w_timestamp = weights.get('file_created_during_task', 10)
    w_reduction = weights.get('polygon_reduction_sufficient', 30)
    w_valid = weights.get('model_geometrically_valid', 15)
    w_shape = weights.get('shape_preserved', 15)
    w_size = weights.get('file_size_reduced', 10)
    
    # Initialize scoring
    score = 0.0
    feedback_parts = []
    details = {}
    
    # ================================================================
    # Copy result JSON from container
    # ================================================================
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    result = {}
    
    try:
        copy_from_env("/tmp/decimate_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
        logger.info(f"Loaded result: {result}")
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
            "feedback": f"Failed to read result from container: {e}"
        }
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)
    
    # Store raw result for debugging
    details['raw_result'] = result
    
    # ================================================================
    # CRITERION 1: Output File Exists (20 points)
    # ================================================================
    output_exists = result.get('output_exists', False)
    output_size = result.get('output_size_bytes', 0)
    
    if output_exists and output_size > 0:
        score += w_exists
        feedback_parts.append(f"✓ Output file exists ({output_size / 1024:.1f} KB)")
        details['output_exists'] = True
    else:
        feedback_parts.append(f"✗ Output file not found at {expected_output}")
        details['output_exists'] = False
        # Early exit - nothing else to verify
        return {
            "passed": False,
            "score": score,
            "feedback": " | ".join(feedback_parts),
            "details": details
        }
    
    # ================================================================
    # CRITERION 2: File Created During Task (10 points) - Anti-gaming
    # ================================================================
    timestamp_valid = result.get('timestamp_valid', False)
    task_start = result.get('task_start', 0)
    output_mtime = result.get('output_mtime', 0)
    
    if timestamp_valid:
        score += w_timestamp
        feedback_parts.append("✓ File created during task execution")
        details['timestamp_valid'] = True
    else:
        # Could be pre-existing file - suspicious
        feedback_parts.append("⚠ File may predate task start (timestamp check failed)")
        details['timestamp_valid'] = False
        details['task_start'] = task_start
        details['file_mtime'] = output_mtime
    
    # ================================================================
    # CRITERION 3: Polygon Count Reduced >= 50% (30 points)
    # ================================================================
    output_polys = result.get('output_polygons', 0)
    original_polys = result.get('original_polygons', 0)
    reduction_percent = result.get('reduction_percent', 0)
    
    details['output_polygons'] = output_polys
    details['original_polygons'] = original_polys
    details['reduction_percent'] = reduction_percent
    
    if original_polys > 0 and output_polys > 0:
        if reduction_percent >= min_reduction:
            score += w_reduction
            feedback_parts.append(
                f"✓ Polygon reduction: {reduction_percent:.1f}% "
                f"({original_polys:,} → {output_polys:,})"
            )
            details['reduction_sufficient'] = True
        elif reduction_percent >= min_reduction * 0.8:
            # Partial credit for close attempts
            partial = w_reduction * (reduction_percent / min_reduction)
            score += partial
            feedback_parts.append(
                f"△ Polygon reduction: {reduction_percent:.1f}% "
                f"(target: ≥{min_reduction}%, partial credit +{partial:.0f})"
            )
            details['reduction_sufficient'] = False
        elif reduction_percent > 0:
            # Some reduction but not enough
            feedback_parts.append(
                f"✗ Insufficient reduction: {reduction_percent:.1f}% "
                f"(need ≥{min_reduction}%)"
            )
            details['reduction_sufficient'] = False
        else:
            feedback_parts.append(
                f"✗ No polygon reduction detected "
                f"(output: {output_polys:,}, original: {original_polys:,})"
            )
            details['reduction_sufficient'] = False
    elif output_polys > 0:
        # Can't calculate reduction but file has content
        feedback_parts.append(
            f"? Cannot verify reduction (original count unknown), "
            f"output has {output_polys:,} polygons"
        )
        details['reduction_sufficient'] = None
    else:
        feedback_parts.append("✗ Output file appears empty (0 polygons)")
        details['reduction_sufficient'] = False
    
    # ================================================================
    # CRITERION 4: Model Geometrically Valid (15 points)
    # ================================================================
    model_valid = result.get('model_valid', False)
    has_geometry = result.get('has_geometry', False)
    bounding_box = result.get('bounding_box', [])
    
    if model_valid and has_geometry:
        score += w_valid
        feedback_parts.append("✓ Output model is geometrically valid")
        details['model_valid'] = True
    elif has_geometry:
        # Has some geometry but validation uncertain
        score += w_valid * 0.5
        feedback_parts.append("△ Model has geometry but validity uncertain")
        details['model_valid'] = 'partial'
    else:
        feedback_parts.append("✗ Output model appears invalid or empty")
        details['model_valid'] = False
    
    if bounding_box:
        details['bounding_box'] = bounding_box
    
    # ================================================================
    # CRITERION 5: Shape Preserved (15 points)
    # ================================================================
    # Use heuristics since we can't do full VLM analysis
    # A well-decimated model should have:
    # - Still significant number of polygons (not over-decimated)
    # - Reasonable reduction (not trivial)
    
    shape_preserved = False
    if output_polys >= min_valid_polys:
        # Model still has enough detail
        if reduction_percent >= 30 and reduction_percent <= 95:
            # Reasonable range - not too little, not too much
            score += w_shape
            feedback_parts.append(
                f"✓ Model shape likely preserved ({output_polys:,} polygons retained)"
            )
            shape_preserved = True
        elif reduction_percent > 95:
            # Over-decimated
            score += w_shape * 0.3
            feedback_parts.append(
                f"⚠ Model may be over-decimated ({reduction_percent:.1f}% reduction)"
            )
        else:
            # Under-decimated but still valid
            score += w_shape * 0.7
            feedback_parts.append(
                f"△ Model valid but reduction minimal"
            )
    elif output_polys > 0:
        # Very few polygons - likely over-decimated
        feedback_parts.append(
            f"✗ Model may be over-decimated (only {output_polys:,} polygons)"
        )
    else:
        feedback_parts.append("✗ Cannot assess shape - no geometry")
    
    details['shape_preserved'] = shape_preserved
    
    # ================================================================
    # CRITERION 6: File Size Reduced (10 points)
    # ================================================================
    original_size = result.get('original_file_size', 0)
    output_size = result.get('output_size_bytes', 0)
    
    if original_size > 0 and output_size > 0:
        size_reduction = (1 - output_size / original_size) * 100
        details['file_size_reduction_percent'] = round(size_reduction, 2)
        
        if size_reduction >= 30:
            score += w_size
            feedback_parts.append(
                f"✓ File size reduced by {size_reduction:.1f}%"
            )
        elif size_reduction >= 10:
            score += w_size * 0.5
            feedback_parts.append(
                f"△ File size reduced by {size_reduction:.1f}% (modest)"
            )
        elif size_reduction > 0:
            score += w_size * 0.2
            feedback_parts.append(
                f"△ File size marginally reduced ({size_reduction:.1f}%)"
            )
        else:
            feedback_parts.append(
                f"? File size not reduced ({size_reduction:.1f}%)"
            )
    else:
        feedback_parts.append("? Could not compare file sizes")
    
    # ================================================================
    # FINAL SCORING
    # ================================================================
    score = min(100, max(0, score))
    
    # Determine pass/fail
    # Must have: output exists AND sufficient reduction
    key_criteria_met = (
        output_exists and 
        details.get('reduction_sufficient', False) is True
    )
    
    passed = score >= 70 and key_criteria_met
    
    # Add summary
    feedback_parts.append("")
    feedback_parts.append(f"═══ Final Score: {score:.0f}/100 ═══")
    
    if passed:
        feedback_parts.append("✓ PASSED: Model successfully decimated and exported")
    elif score >= 70:
        feedback_parts.append(
            "△ Score meets threshold but key criteria not met"
        )
    else:
        feedback_parts.append(
            f"✗ FAILED: Score {score:.0f} < 70 or key criteria missing"
        )
    
    return {
        "passed": passed,
        "score": int(round(score)),
        "feedback": "\n".join(feedback_parts),
        "details": details
    }


# For standalone testing
if __name__ == "__main__":
    # Create mock data for testing
    mock_result = {
        "output_exists": True,
        "output_size_bytes": 15000000,
        "timestamp_valid": True,
        "slicer_running": True,
        "output_polygons": 200000,
        "original_polygons": 500000,
        "reduction_percent": 60.0,
        "model_valid": True,
        "has_geometry": True,
        "original_file_size": 40000000,
        "task_start": 1000000,
        "output_mtime": 1000100
    }
    
    # Write mock result
    import tempfile
    with tempfile.NamedTemporaryFile(mode='w', suffix='.json', delete=False) as f:
        json.dump(mock_result, f)
        mock_path = f.name
    
    # Mock copy function
    def mock_copy(src, dst):
        if "decimate_result" in src:
            import shutil
            shutil.copy(mock_path, dst)
        else:
            raise FileNotFoundError(f"Mock: {src} not found")
    
    # Test
    result = verify_decimate_surface_model(
        traj={},
        env_info={'copy_from_env': mock_copy},
        task_info={'metadata': {}}
    )
    
    print("\n=== Test Result ===")
    print(f"Passed: {result['passed']}")
    print(f"Score: {result['score']}")
    print(f"Feedback:\n{result['feedback']}")
    
    # Cleanup
    os.unlink(mock_path)