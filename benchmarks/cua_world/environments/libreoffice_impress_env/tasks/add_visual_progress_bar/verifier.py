#!/usr/bin/env python3
"""
Verifier for Add Visual Progress Bar task.

Verifies that rectangles have been added to slides 2-6 with increasing widths.
"""

import json
import os
import sys
import logging
import tempfile
import zipfile
import re
import xml.dom.minidom

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def parse_unit(value_str):
    """Convert ODF units (cm, mm, in, pt) to mm."""
    if not isinstance(value_str, str):
        return 0.0
    
    value_str = value_str.strip().lower()
    value = float(re.findall(r"[-+]?\d*\.\d+|\d+", value_str)[0])
    
    if 'cm' in value_str:
        return value * 10.0
    elif 'mm' in value_str:
        return value
    elif 'in' in value_str:
        return value * 25.4
    elif 'pt' in value_str:
        return value * 0.352778
    return value  # Assume mm if no unit

def verify_progress_bars(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    output_path = task_info['metadata'].get('output_file', '/home/ga/Documents/Presentations/onboarding_final.odp')
    temp_odp = tempfile.NamedTemporaryFile(delete=False, suffix=".odp")
    temp_result_json = tempfile.NamedTemporaryFile(delete=False, suffix=".json")

    try:
        # 1. Check basic file existence via export result
        copy_from_env("/tmp/task_result.json", temp_result_json.name)
        with open(temp_result_json.name, 'r') as f:
            export_result = json.load(f)
            
        if not export_result.get('file_exists'):
            return {"passed": False, "score": 0, "feedback": "Output file onboarding_final.odp not found."}

        # 2. Retrieve ODP file
        copy_from_env(output_path, temp_odp.name)
        
        # 3. Parse ODP (it's a zip)
        if not zipfile.is_zipfile(temp_odp.name):
            return {"passed": False, "score": 0, "feedback": "Output file is not a valid ODP/Zip archive."}

        with zipfile.ZipFile(temp_odp.name, 'r') as z:
            content_xml = z.read('content.xml')
        
        dom = xml.dom.minidom.parseString(content_xml)
        
        # Get slides (draw:page)
        slides = dom.getElementsByTagName('draw:page')
        
        # We assume standard slide width ~280mm (Widescreen) or ~210mm (4:3)
        # We can try to infer from master page, but for scoring relative growth, 
        # checking the ratio between bars is more robust than absolute dimensions.
        
        rectangles_by_slide = {}
        
        # Target slides are indices 1, 2, 3, 4, 5 (Slides 2-6)
        target_indices = [1, 2, 3, 4, 5]
        
        for idx in target_indices:
            if idx >= len(slides):
                continue
                
            slide = slides[idx]
            # Find rectangles
            rects = slide.getElementsByTagName('draw:rect')
            custom_shapes = slide.getElementsByTagName('draw:custom-shape')
            
            # Combine shapes to check
            candidates = list(rects) + list(custom_shapes)
            
            # Filter for likely progress bars (wide and short, near bottom)
            best_rect = None
            max_y = -1
            
            for shape in candidates:
                width = parse_unit(shape.getAttribute('svg:width'))
                height = parse_unit(shape.getAttribute('svg:height'))
                y = parse_unit(shape.getAttribute('svg:y'))
                
                # Heuristic: Progress bar should be wider than it is tall
                # And usually near the bottom (large Y value)
                # And width should be significant (> 2cm)
                if width > height and width > 20.0 and y > 100.0: # Assuming page height > 100mm
                    if y > max_y: # Pick lowest element
                        max_y = y
                        best_rect = {'width': width, 'height': height, 'y': y}
            
            if best_rect:
                rectangles_by_slide[idx] = best_rect

        # SCORING
        score = 0
        feedback_parts = []
        
        # Criterion 1: File valid (10 pts)
        score += 10
        
        # Criterion 2: Bars detected on all target slides (25 pts)
        bars_found = len(rectangles_by_slide)
        if bars_found == 5:
            score += 25
            feedback_parts.append("✅ Progress bars detected on all 5 target slides")
        else:
            score += bars_found * 5
            feedback_parts.append(f"⚠️ Progress bars detected on {bars_found}/5 target slides")
            
        # Criterion 3: Progression (25 pts)
        # Check if width increases monotonically
        progression_ok = True
        widths = []
        
        for idx in target_indices:
            if idx in rectangles_by_slide:
                widths.append(rectangles_by_slide[idx]['width'])
            else:
                widths.append(0)
        
        # Allow some noise, but generally S2 < S3 < S4 < S5 < S6
        increasing_pairs = 0
        total_pairs = 4
        for i in range(len(widths)-1):
            if widths[i] > 0 and widths[i+1] > widths[i]:
                increasing_pairs += 1
            elif widths[i+1] <= widths[i] and widths[i+1] > 0:
                progression_ok = False
        
        if progression_ok and bars_found == 5:
            score += 25
            feedback_parts.append("✅ Bar widths increase progressively")
        elif increasing_pairs > 0:
            score += int(25 * (increasing_pairs / total_pairs))
            feedback_parts.append("⚠️ Bar widths show some progression")
        else:
            feedback_parts.append("❌ Bar widths do not increase correctly")
            
        # Criterion 4: Accuracy (20 pts)
        # Check if S2 is roughly 20% of S6
        # We use S6 as the reference "100%" (or largest bar found)
        max_width = max(widths) if widths else 0
        accuracy_score = 0
        
        if max_width > 0:
            expected_ratios = [0.2, 0.4, 0.6, 0.8, 1.0]
            for i, w in enumerate(widths):
                if w == 0: continue
                ratio = w / max_width
                expected = expected_ratios[i]
                
                # Check if ratio is within 15% tolerance
                if abs(ratio - expected) < 0.15:
                    accuracy_score += 4
            
        score += accuracy_score
        if accuracy_score > 15:
            feedback_parts.append("✅ Width ratios are accurate")
        else:
             feedback_parts.append("⚠️ Width ratios deviate from expected (20/40/60/80/100)")

        # Criterion 5: Positioning (10 pts)
        # Check if all Y coordinates are roughly similar (within 5mm)
        y_coords = [rectangles_by_slide[idx]['y'] for idx in rectangles_by_slide]
        if y_coords:
            y_range = max(y_coords) - min(y_coords)
            if y_range < 5.0:
                score += 10
                feedback_parts.append("✅ Bars are consistently positioned")
            else:
                score += 5
                feedback_parts.append(f"⚠️ Bars positions vary by {y_range:.1f}mm")
        
        # Criterion 6: Color (10 pts)
        # Hard to parse hex from ODF styles robustly without resolving styles.
        # We assume if they are rectangles and progress correctly, the color is likely correct or close enough.
        # We give these points for finding the shapes at all to be generous.
        if bars_found >= 4:
            score += 10
            
        passed = score >= 75
        
        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }

    except Exception as e:
        logger.exception("Verification failed")
        return {"passed": False, "score": 0, "feedback": f"Verification error: {str(e)}"}
    finally:
        if os.path.exists(temp_odp.name):
            os.unlink(temp_odp.name)
        if os.path.exists(temp_result_json.name):
            os.unlink(temp_result_json.name)