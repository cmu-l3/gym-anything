#!/usr/bin/env python3
"""
Verifier for GIMP add layer mask task.
Checks if a layer mask was successfully added by analyzing the XCF file structure.
"""

import logging
from pathlib import Path
from PIL import Image
import numpy as np
import sys
import os
import tempfile

# Add the tasks directory to path so we can import verification_utils
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)) + "/..")
from verification_utils import setup_verification_environment, cleanup_verification_environment

logging.basicConfig(level=logging.DEBUG)


def detect_layer_mask_in_xcf(xcf_path):
    """
    Detect layer mask presence in GIMP XCF file by analyzing binary structure.
    
    XCF files contain specific markers and structures for layer masks.
    We'll look for key indicators without full XCF parsing.
    """
    try:
        with open(xcf_path, 'rb') as f:
            content = f.read()
        
        # XCF format indicators for layer masks
        # These are binary signatures that indicate layer mask presence
        layer_mask_signatures = [
            b'GIMP_LAYER_MASK',  # Direct layer mask identifier
            b'layer-mask',       # Configuration parameter
            b'MASK',             # Generic mask identifier
            b'mask-opacity',     # Mask opacity setting
            b'mask-visible',     # Mask visibility setting
        ]
        
        mask_indicators_found = 0
        total_signatures = len(layer_mask_signatures)
        
        for signature in layer_mask_signatures:
            if signature in content:
                mask_indicators_found += 1
                logging.debug(f"Found layer mask signature: {signature}")
        
        # Additional structural analysis
        file_size = len(content)
        
        # XCF files with layer masks are typically larger due to mask channel data
        # Reasonable threshold based on expected mask data overhead
        size_indicates_mask = file_size > 50000  # 50KB threshold for additional mask data
        
        # Combine indicators for confidence score
        confidence = mask_indicators_found / total_signatures
        
        # Check for XCF format validity first
        if not content.startswith(b'gimp xcf'):
            return False, 0.0, "File is not a valid XCF format"
        
        # High confidence if multiple signatures found
        if confidence >= 0.2:  # At least 20% of signatures found
            return True, confidence, f"Layer mask detected with {confidence:.1%} confidence"
        elif size_indicates_mask and mask_indicators_found > 0:
            return True, 0.5, "Layer mask likely present based on file structure"
        else:
            return False, confidence, f"No clear layer mask indicators found (confidence: {confidence:.1%})"
            
    except Exception as e:
        logging.error(f"Error analyzing XCF file: {e}")
        return False, 0.0, f"Error analyzing file: {str(e)}"


def analyze_xcf_layer_structure(xcf_path):
    """
    Additional analysis of XCF layer structure to detect masks.
    """
    try:
        with open(xcf_path, 'rb') as f:
            # Read file header and initial structure
            header = f.read(100)
            f.seek(0)
            full_content = f.read()
        
        analysis = {
            'file_size': len(full_content),
            'has_xcf_header': header.startswith(b'gimp xcf'),
            'layer_count_estimate': 0,
            'mask_data_detected': False
        }
        
        # Estimate layer count by looking for layer markers
        layer_markers = full_content.count(b'LAYER')
        analysis['layer_count_estimate'] = max(1, layer_markers)
        
        # Look for mask-specific data structures
        mask_data_indicators = [
            b'opacity',
            b'visible',
            b'linked',
            b'preserve-transparency',
            b'apply-mask',
            b'edit-mask',
            b'show-mask'
        ]
        
        mask_data_count = sum(1 for indicator in mask_data_indicators if indicator in full_content)
        analysis['mask_data_detected'] = mask_data_count >= 3  # Reasonable threshold
        
        return analysis
        
    except Exception as e:
        logging.error(f"Error in structural analysis: {e}")
        return {'error': str(e)}


def check_layer_mask(traj, env_info, task_info):
    """
    Main verifier function for add layer mask task.
    Checks:
    1. XCF file was created (preserving layer structure)
    2. Layer mask is present in the file structure
    3. Mask appears to be properly configured
    """
    
    # Get copy function from env_info
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Copy function not available in env_info"
        }
    
    # Set up verification environment with fallback file search
    possible_results = [
        "/home/ga/Desktop/mask_test_with_layer_mask.xcf",
        "/home/ga/Desktop/mask_test_image.xcf",
        "/home/ga/Desktop/layer_mask.xcf",
        "/home/ga/Desktop/mask_test_with_layer_mask.XCF"
    ]
    
    success, file_info = setup_verification_environment(
        "/home/ga/Desktop/mask_test_image.jpg",
        possible_results,
        copy_from_env,
        "/home/ga/Desktop"
    )
    
    if not success:
        return {
            "passed": False,
            "score": 0,
            "feedback": file_info.get("error", "Setup failed")
        }
    
    try:
        # Load original image for reference
        original_image = Image.open(file_info["original_path"])
        
        # Analyze XCF file for layer mask
        xcf_path = file_info["result_path"]
        
        # Check if file is actually XCF format
        if not xcf_path.lower().endswith('.xcf'):
            return {
                "passed": False,
                "score": 0,
                "feedback": f"Result file is not XCF format: {file_info['result_container_path']}"
            }
        
        # Detect layer mask in XCF
        mask_detected, confidence, mask_message = detect_layer_mask_in_xcf(xcf_path)
        
        # Additional structural analysis
        structure_analysis = analyze_xcf_layer_structure(xcf_path)
        
        logging.debug(f"Found XCF file at: {file_info['result_container_path']}")
        
        feedback_parts = []
        feedback_parts.append(f"Original image: {original_image.size}")
        feedback_parts.append(f"XCF file found: ✅")
        feedback_parts.append(f"File size: {structure_analysis.get('file_size', 'unknown')} bytes")
        feedback_parts.append(f"Valid XCF format: {'✅' if structure_analysis.get('has_xcf_header', False) else '❌'}")
        feedback_parts.append(f"Layer mask detected: {'✅' if mask_detected else '❌'}")
        feedback_parts.append(f"Detection confidence: {confidence:.1%}")
        feedback_parts.append(f"Mask data structures: {'✅' if structure_analysis.get('mask_data_detected', False) else '❌'}")
        
        # Calculate success based on multiple criteria
        criteria_met = 0
        total_criteria = 4
        
        # 1. Valid XCF file with proper header
        if structure_analysis.get('has_xcf_header', False):
            criteria_met += 1
        
        # 2. Layer mask detected with reasonable confidence
        if mask_detected and confidence >= 0.2:
            criteria_met += 1
        
        # 3. Mask data structures present
        if structure_analysis.get('mask_data_detected', False):
            criteria_met += 1
        
        # 4. File size indicates additional mask data
        file_size = structure_analysis.get('file_size', 0)
        if file_size > 30000:  # Reasonable threshold for image + mask data
            criteria_met += 1
        
        # Score based on criteria met
        score = int((criteria_met / total_criteria) * 100)
        passed = score >= 75  # Need at least 3/4 criteria
        
        if passed and confidence >= 0.5:
            feedback_parts.append("🎉 Layer mask successfully added!")
        elif passed:
            feedback_parts.append("✅ Layer mask appears to be added!")
        else:
            feedback_parts.append("❌ Layer mask not detected or improperly added")
            
        feedback_parts.append(f"Verification: {mask_message}")
        
        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }
        
    except Exception as e:
        logging.error(f"Error in layer mask verification: {e}")
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Verification error: {str(e)}"
        }
    finally:
        # Clean up temporary files
        cleanup_verification_environment(file_info.get("temp_dir", ""))


if __name__ == "__main__":
    # Test the verifier
    result = check_layer_mask([], {}, {})
    print(f"Test result: {result}")