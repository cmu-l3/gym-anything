#!/usr/bin/env python3
"""
Verifier for evaluate_road_diet_lane_reduction task.
"""

import json
import tempfile
import os
import xml.etree.ElementTree as ET
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_evaluate_road_diet_lane_reduction(traj, env_info, task_info):
    """
    Verifies that the agent correctly identified the target multi-lane edge, 
    built a correct patch, produced a valid new network, and accurately reported
    trip statistics for both simulated scenarios.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    score = 0
    feedback_parts = []
    
    # Files to pull from environment
    files = {
        'result': '/tmp/task_result.json',
        'original_net': '/tmp/original.net.xml',
        'patch': '/tmp/roaddiet.edg.xml',
        'new_net': '/tmp/acosta_roaddiet.net.xml',
        'baseline_trip': '/tmp/baseline_tripinfo.xml',
        'diet_trip': '/tmp/roaddiet_tripinfo.xml'
    }
    
    temp_dir = tempfile.mkdtemp()
    paths = {}
    
    try:
        # Copy files to local temp directory
        for key, env_path in files.items():
            local_path = os.path.join(temp_dir, os.path.basename(env_path))
            try:
                copy_from_env(env_path, local_path)
                paths[key] = local_path
            except Exception as e:
                paths[key] = None
                
        if not paths.get('result') or not os.path.exists(paths['result']):
            return {"passed": False, "score": 0, "feedback": "Result JSON not found"}
            
        with open(paths['result'], 'r') as f:
            result = json.load(f)
            
        # ================================================================
        # 1. Logic to Find Correct Target Edge dynamically
        # ================================================================
        correct_edge = None
        original_lanes = 0
        if paths.get('original_net') and os.path.exists(paths['original_net']):
            try:
                tree = ET.parse(paths['original_net'])
                root = tree.getroot()
                max_len = -1
                for edge in root.findall('edge'):
                    edge_id = edge.get('id', '')
                    if edge_id.startswith(':') or edge.get('function') == 'internal':
                        continue
                    
                    lanes = edge.findall('lane')
                    if len(lanes) >= 2:
                        length = float(lanes[0].get('length', 0))
                        if length > max_len:
                            max_len = length
                            correct_edge = edge_id
                        elif length == max_len:
                            # Break ties alphabetically
                            if correct_edge is None or edge_id < correct_edge:
                                correct_edge = edge_id
                
                if correct_edge:
                    original_lanes = len(root.find(f".//edge[@id='{correct_edge}']").findall('lane'))
            except Exception as e:
                feedback_parts.append(f"Error parsing original net: {e}")
                
        # Parse the agent's report
        report_content = result.get('report_content', '')
        report_dict = {}
        for part in report_content.split('|'):
            if ':' in part:
                k, v = part.split(':', 1)
                report_dict[k.strip()] = v.strip()
                
        reported_edge = report_dict.get('Target_Edge')
        if correct_edge and reported_edge == correct_edge:
            score += 20
            feedback_parts.append(f"Target edge correctly identified as {correct_edge}")
        else:
            feedback_parts.append(f"Target edge incorrect: expected {correct_edge}, got {reported_edge}")
            
        # ================================================================
        # 2. Verify Patch File (20 points)
        # ================================================================
        patch_valid = False
        if paths.get('patch') and os.path.exists(paths['patch']):
            try:
                tree = ET.parse(paths['patch'])
                root = tree.getroot()
                for edge in root.findall('edge'):
                    if edge.get('id') == correct_edge and edge.get('numLanes') == '1':
                        patch_valid = True
                        break
            except Exception:
                pass
        
        if patch_valid:
            score += 20
            feedback_parts.append("Patch file is valid")
        else:
            feedback_parts.append("Patch file is invalid or missing")
            
        # ================================================================
        # 3. Verify Rebuilt Network (20 points)
        # ================================================================
        net_rebuilt = False
        if paths.get('new_net') and os.path.exists(paths['new_net']):
            try:
                tree = ET.parse(paths['new_net'])
                root = tree.getroot()
                edge = root.find(f".//edge[@id='{correct_edge}']")
                if edge is not None and len(edge.findall('lane')) == 1:
                    net_rebuilt = True
            except Exception:
                pass
                
        if net_rebuilt:
            score += 20
            feedback_parts.append("Network rebuilt correctly")
        else:
            feedback_parts.append("Network rebuilt incorrectly or missing")
            
        # ================================================================
        # 4. Verify Simulations Completed (20 points)
        # ================================================================
        sims_completed = result.get('baseline_tripinfo_exists', False) and result.get('diet_tripinfo_exists', False)
        if sims_completed:
            score += 20
            feedback_parts.append("Both simulations completed")
        else:
            feedback_parts.append("One or both simulations missing")
            
        # ================================================================
        # 5. Verify Analytics match ground truth values from the XMLs (20 points)
        # ================================================================
        analytics_accurate = False
        
        def calc_avg(path):
            if not path or not os.path.exists(path): return None
            try:
                tree = ET.parse(path)
                trips = tree.getroot().findall('tripinfo')
                if not trips: return 0.0
                return sum(float(t.get('duration', 0)) for t in trips) / len(trips)
            except Exception:
                return None
                
        real_base_avg = calc_avg(paths.get('baseline_trip'))
        real_diet_avg = calc_avg(paths.get('diet_trip'))
        
        if real_base_avg is not None and real_diet_avg is not None:
            rep_base = report_dict.get('Baseline_Average_Duration')
            rep_diet = report_dict.get('Diet_Average_Duration')
            
            try:
                rep_base = float(rep_base)
                rep_diet = float(rep_diet)
                # Apply 0.1s tolerance
                if abs(rep_base - real_base_avg) <= 0.15 and abs(rep_diet - real_diet_avg) <= 0.15:
                    analytics_accurate = True
            except (ValueError, TypeError):
                pass
                
        if analytics_accurate:
            score += 20
            feedback_parts.append("Analytics match XML output (within tolerance)")
        else:
            feedback_parts.append("Analytics inaccurate or not verifiable")

    finally:
        # Cleanup local temp files
        for p in paths.values():
            if p and os.path.exists(p):
                os.unlink(p)
        os.rmdir(temp_dir)
        
    # Must meet key criteria and score >= 80 to pass
    passed = (score >= 80) and bool(correct_edge) and (reported_edge == correct_edge) and analytics_accurate
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }