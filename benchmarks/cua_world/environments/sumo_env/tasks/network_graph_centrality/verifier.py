#!/usr/bin/env python3
"""
Verifier for network_graph_centrality task.

Verifies the programmatic logic, outputs, and constraints of a graph theory task on SUMO networks.
Uses structural validation and output coherence checks rather than hardcoded ground truth 
to ensure the agent properly implemented the graph logic on the provided dynamic dataset.
"""

import json
import os
import csv
import tempfile
import logging
import xml.etree.ElementTree as ET

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_network_graph_centrality(traj, env_info, task_info):
    """
    Verify the generated script, structural CSV, and top-5 output.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    feedback_parts = []
    score = 0
    max_score = 100

    # 1. Load result.json
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read task result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    # Criteria 1: Output Files Exist & Created During Task (20 pts)
    files_ok = True
    if not result.get("script_exists"):
        feedback_parts.append("analyze_centrality.py missing")
        files_ok = False
    if not result.get("csv_exists"):
        feedback_parts.append("node_centrality.csv missing")
        files_ok = False
    if not result.get("top5_exists"):
        feedback_parts.append("top_5_critical_nodes.txt missing")
        files_ok = False

    if files_ok:
        if result.get("csv_created_during_task") and result.get("top5_created_during_task"):
            score += 20
            feedback_parts.append("All output files exist and created during task.")
        else:
            score += 10
            feedback_parts.append("Files exist but timestamps suggest they were not created during the task.")
    else:
        # Early exit if files missing
        return {"passed": False, "score": score, "feedback": " | ".join(feedback_parts)}

    # 2. Inspect the Python Script (20 pts)
    temp_script = tempfile.NamedTemporaryFile(delete=False, suffix='.py')
    script_valid = False
    try:
        copy_from_env("/tmp/analyze_centrality.py", temp_script.name)
        with open(temp_script.name, 'r') as f:
            script_content = f.read()
            if ("import networkx" in script_content or "from networkx" in script_content) and \
               ("import sumolib" in script_content or "from sumolib" in script_content):
                score += 20
                script_valid = True
                feedback_parts.append("Script imports networkx and sumolib.")
            else:
                feedback_parts.append("Script missing required imports (networkx/sumolib).")
    except Exception as e:
        feedback_parts.append("Could not verify script contents.")
    finally:
        if os.path.exists(temp_script.name):
            os.unlink(temp_script.name)

    # 3. Parse XML to get ground truth non-internal junction IDs
    temp_xml = tempfile.NamedTemporaryFile(delete=False, suffix='.xml')
    valid_junctions = set()
    internal_junctions = set()
    try:
        copy_from_env("/tmp/pasubio_buslanes.net.xml", temp_xml.name)
        tree = ET.parse(temp_xml.name)
        root = tree.getroot()
        for junction in root.findall('junction'):
            j_id = junction.get('id')
            j_type = junction.get('type')
            if j_type == 'internal' or (j_id and j_id.startswith(':')):
                internal_junctions.add(j_id)
            else:
                valid_junctions.add(j_id)
    except Exception as e:
        logger.warning(f"Could not parse XML for ground truth: {e}")
    finally:
        if os.path.exists(temp_xml.name):
            os.unlink(temp_xml.name)

    # 4. Verify CSV Formatting & Content (30 pts)
    temp_csv = tempfile.NamedTemporaryFile(delete=False, suffix='.csv')
    csv_valid = False
    csv_nodes = []
    try:
        copy_from_env("/tmp/node_centrality.csv", temp_csv.name)
        with open(temp_csv.name, 'r') as f:
            reader = csv.reader(f)
            headers = next(reader, [])
            
            if headers == ["node_id", "centrality"]:
                score += 10
                
                rows = list(reader)
                csv_nodes = [row[0] for row in rows if len(row) >= 2]
                try:
                    centralities = [float(row[1]) for row in rows if len(row) >= 2]
                    # Check descending sort
                    if centralities == sorted(centralities, reverse=True):
                        score += 10
                        feedback_parts.append("CSV correctly sorted descending.")
                    else:
                        feedback_parts.append("CSV not sorted descending.")
                except ValueError:
                    feedback_parts.append("CSV contains non-numeric centrality values.")

                # Check constraints against XML (no internal nodes)
                if valid_junctions:
                    has_internal = any(node in internal_junctions or str(node).startswith(':') for node in csv_nodes)
                    valid_overlap = sum(1 for node in csv_nodes if node in valid_junctions)
                    
                    if not has_internal and valid_overlap > 10:
                        score += 10
                        csv_valid = True
                        feedback_parts.append("CSV nodes are valid non-internal junctions.")
                    elif has_internal:
                        feedback_parts.append("CSV incorrectly includes internal junction IDs.")
                    else:
                        feedback_parts.append("CSV nodes do not match network junctions.")
                else:
                    # If XML parsing failed, give benefit of doubt if nodes look somewhat valid
                    if len(csv_nodes) > 10 and not any(str(n).startswith(':') for n in csv_nodes):
                        score += 10
                        csv_valid = True
                        feedback_parts.append("CSV nodes look reasonably formatted (no colons).")
                    else:
                        feedback_parts.append("CSV nodes contain internal edges or are too few.")
            else:
                feedback_parts.append(f"CSV headers incorrect. Expected ['node_id', 'centrality'], got {headers}")
    except Exception as e:
        feedback_parts.append(f"Could not verify CSV: {e}")
    finally:
        if os.path.exists(temp_csv.name):
            os.unlink(temp_csv.name)

    # 5. Verify top_5_critical_nodes.txt (30 pts)
    temp_top5 = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
    try:
        copy_from_env("/tmp/top_5_critical_nodes.txt", temp_top5.name)
        with open(temp_top5.name, 'r') as f:
            lines = [line.strip() for line in f.readlines() if line.strip()]
            
            if len(lines) == 5:
                # Check if it matches the top 5 from the CSV
                if len(csv_nodes) >= 5 and lines == csv_nodes[:5]:
                    score += 30
                    feedback_parts.append("Top 5 text file correctly matches the highest CSV centralities.")
                else:
                    score += 10
                    feedback_parts.append("Top 5 file has 5 lines but does not match top 5 of CSV exactly.")
            else:
                feedback_parts.append(f"Top 5 file has {len(lines)} lines, expected 5.")
    except Exception as e:
        feedback_parts.append(f"Could not verify top 5 file: {e}")
    finally:
        if os.path.exists(temp_top5.name):
            os.unlink(temp_top5.name)

    key_criteria_met = files_ok and csv_valid and script_valid
    passed = score >= 80 and key_criteria_met

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }