#!/usr/bin/env python3
"""
Verifier for GIMP layer duplication task.
Checks if the current layer was successfully duplicated by analyzing XCF file structure.
"""

import logging
from pathlib import Path
from PIL import Image
import numpy as np
import sys
import os
import struct

# Add the tasks directory to path so we can import verification_utils
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)) + "/..")
from verification_utils import setup_verification_environment, cleanup_verification_environment

logging.basicConfig(level=logging.DEBUG)


def analyze_xcf_structure(xcf_path):
    """
    Analyze XCF file structure to detect layer information.
    Returns dict with layer analysis results.
    """
    analysis_results = {
        'layer_count': 0,
        'file_size': 0,
        'has_multiple_layers': False,
        'structure_valid': False
    }
    
    try:
        # Get basic file info
        analysis_results['file_size'] = os.path.getsize(xcf_path)
        
        with open(xcf_path, 'rb') as f:
            # Read XCF header
            magic = f.read(9)
            if magic != b'gimp xcf ':
                logging.debug("Not a valid XCF file")
                return analysis_results
            
            analysis_results['structure_valid'] = True
            
            # Read version string (variable length, null terminated)
            version = b""
            while True:
                char = f.read(1)
                if char == b'\x00' or len(char) == 0:
                    break
                version += char
            
            logging.debug(f"XCF version: {version.decode('ascii', errors='ignore')}")
            
            # Read image properties
            width = struct.unpack('>I', f.read(4))[0]
            height = struct.unpack('>I', f.read(4))[0]  
            base_type = struct.unpack('>I', f.read(4))[0]
            
            logging.debug(f"Image: {width}x{height}, type: {base_type}")
            
            # Skip image properties by reading until we find layer offsets
            # This is a simplified approach - full XCF parsing is quite complex
            layer_offsets = []
            while True:
                try:
                    offset_data = f.read(4)
                    if len(offset_data) != 4:
                        break
                    offset = struct.unpack('>I', offset_data)[0]
                    if offset == 0:
                        break
                    layer_offsets.append(offset)
                except:
                    break
            
            analysis_results['layer_count'] = len(layer_offsets)
            analysis_results['has_multiple_layers'] = len(layer_offsets) >= 2
            
            logging.debug(f"Found {len(layer_offsets)} layer offsets: {layer_offsets[:5]}...")  # Show first 5
            
    except Exception as e:
        logging.debug(f"XCF analysis failed: {e}")
        # Fall back to file size heuristics
        if analysis_results['file_size'] > 0:
            analysis_results['structure_valid'] = True
            
    return analysis_results


def check_duplication_heuristics(xcf_path, original_path):
    """
    Use various heuristics to determine if layer duplication likely occurred.
    """
    heuristics = {
        'size_increase': False,
        'reasonable_size': False,
        'xcf_format': False
    }
    
    try:
        if not os.path.exists(xcf_path):
            return heuristics
            
        xcf_size = os.path.getsize(xcf_path)
        
        # Check if result is XCF format
        heuristics['xcf_format'] = xcf_path.endswith('.xcf')
        
        # Check if file size is reasonable for having layers
        heuristics['reasonable_size'] = xcf_size > 10000  # At least 10KB
        
        # Compare with original if available
        if os.path.exists(original_path):
            orig_size = os.path.getsize(original_path)
            # Duplicated layers should increase file size, but XCF vs JPG makes this complex
            # Just check that XCF is reasonably larger (accounting for format differences)
            if xcf_size > orig_size * 0.5:  # XCF should be at least half the size even with compression
                heuristics['size_increase'] = True
        else:
            # If no original, assume size increase if file is reasonable size
            heuristics['size_increase'] = heuristics['reasonable_size']
            
    except Exception as e:
        logging.debug(f"Heuristic analysis failed: {e}")
        
    return heuristics


def check_layer_duplication(traj, env_info, task_info):
    """
    Main verifier function for layer duplication task.
    Checks:
    1. XCF file exists with valid structure
    2. Evidence of multiple layers in the file
    3. File size and format are consistent with layer duplication
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
        "/home/ga/Desktop/duplicated_layers.xcf",
        "/home/ga/Desktop/simple_image.xcf", 
        "/home/ga/Desktop/duplicated.xcf",
        "/home/ga/Desktop/layers.xcf"
    ]
    
    success, file_info = setup_verification_environment(
        "/home/ga/Desktop/simple_image.jpg",
        possible_results,
        copy_from_env,
        "/home/ga/Desktop"
    )
    
    if not success:
        return {
            "passed": False,
            "score": 0,
            "feedback": file_info.get("error", "Setup failed - XCF file not found")
        }
    
    try:
        # Analyze the XCF file structure
        xcf_path = file_info["result_path"]
        original_path = file_info["original_path"]
        
        logging.debug(f"Analyzing XCF file: {file_info['result_container_path']}")
        
        # Perform XCF structure analysis
        xcf_analysis = analyze_xcf_structure(xcf_path)
        
        # Perform heuristic checks
        heuristics = check_duplication_heuristics(xcf_path, original_path)
        
        feedback_parts = []
        feedback_parts.append(f"XCF file found: ✅")
        feedback_parts.append(f"File size: {xcf_analysis['file_size']} bytes")
        feedback_parts.append(f"Valid XCF structure: {'✅' if xcf_analysis['structure_valid'] else '❌'}")
        
        if xcf_analysis['layer_count'] > 0:
            feedback_parts.append(f"Layers detected: {xcf_analysis['layer_count']}")
        
        # Evaluate success criteria
        criteria_met = 0
        total_criteria = 4
        
        # Criterion 1: Valid XCF file structure
        if xcf_analysis['structure_valid'] and heuristics['xcf_format']:
            criteria_met += 1
        feedback_parts.append(f"Valid XCF format: {'✅' if heuristics['xcf_format'] else '❌'}")
        
        # Criterion 2: Multiple layers detected
        if xcf_analysis['has_multiple_layers'] or xcf_analysis['layer_count'] >= 2:
            criteria_met += 1
        feedback_parts.append(f"Multiple layers: {'✅' if xcf_analysis['has_multiple_layers'] else '❌'}")
        
        # Criterion 3: Reasonable file size
        if heuristics['reasonable_size']:
            criteria_met += 1
        feedback_parts.append(f"Appropriate file size: {'✅' if heuristics['reasonable_size'] else '❌'}")
        
        # Criterion 4: File size increase consistent with duplication
        if heuristics['size_increase']:
            criteria_met += 1
        feedback_parts.append(f"Size consistent with layers: {'✅' if heuristics['size_increase'] else '❌'}")
        
        # Calculate score based on criteria met
        score = int((criteria_met / total_criteria) * 100)
        passed = score >= 75  # Need at least 3/4 criteria
        
        if passed and score >= 90:
            feedback_parts.append("🎉 Perfect layer duplication!")
        elif passed:
            feedback_parts.append("✅ Layer duplication successful!")
        else:
            feedback_parts.append("❌ Layer duplication not clearly detected")
            
        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }
        
    except Exception as e:
        logging.error(f"Error in layer duplication verification: {e}")
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
    result = check_layer_duplication([], {}, {})
    print(f"Test result: {result}")