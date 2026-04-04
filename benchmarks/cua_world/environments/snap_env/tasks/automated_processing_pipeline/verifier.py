#!/usr/bin/env python3
"""Verifier for automated_processing_pipeline task.

Scoring breakdown (must sum to exactly 100):
  Pipeline definition file exists (XML or script):  15 pts
  Graph/script has data read operation:              15 pts
  Graph/script has processing operation:             20 pts
  Graph/script has data write operation:             10 pts
  Output product created after task start:           20 pts
  Output product contains spectral index band:       20 pts
                                              TOTAL: 100 pts
Pass threshold: 70
"""

import json
import os
import tempfile


def verify_automated_processing_pipeline(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "No copy_from_env available"}

    result_path = tempfile.mktemp(suffix='.json')
    try:
        copy_from_env('/tmp/automated_processing_pipeline_result.json', result_path)
        with open(result_path) as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve result: {e}"}
    finally:
        if os.path.exists(result_path):
            os.unlink(result_path)

    score = 0
    feedback = []

    has_graph = result.get('graph_xml_found', False)
    has_script = result.get('script_found', False)

    # Criterion 1: Pipeline definition file exists (15 pts)
    if has_graph:
        score += 15
        feedback.append("GPT graph XML found (+15)")
    elif has_script:
        score += 15
        feedback.append("Processing script found (+15)")
    else:
        feedback.append("No pipeline definition found (0/15)")

    # Criterion 2: Data read operation (15 pts)
    if has_graph and result.get('graph_has_read'):
        score += 15
        feedback.append("Graph has Read operator (+15)")
    elif has_script:
        # Script likely reads data implicitly
        score += 10
        feedback.append("Script found (read assumed) (+10)")
    elif has_graph:
        score += 5
        feedback.append("Graph exists but no Read operator detected (+5)")
    else:
        feedback.append("No data read operation detected (0/15)")

    # Criterion 3: Processing operation (Subset, BandMaths, etc.) (20 pts)
    if has_graph and result.get('graph_has_processing'):
        ops = result.get('graph_operator_names', [])
        proc_ops = [o for o in ops if o.lower() not in ('read', 'write')]
        if len(proc_ops) >= 2:
            score += 20
            feedback.append(f"Multiple processing ops: {proc_ops} (+20)")
        else:
            score += 15
            feedback.append(f"Processing op: {proc_ops} (+15)")
    elif has_graph:
        # Graph exists but no processing operators beyond read/write
        ops = result.get('graph_operator_names', [])
        if len(ops) >= 2:
            score += 10
            feedback.append(f"Graph has operators but unclear: {ops} (+10)")
        else:
            score += 5
            feedback.append("Graph exists but processing unclear (+5)")
    elif has_script:
        score += 10
        feedback.append("Script found (processing assumed) (+10)")
    else:
        feedback.append("No processing operation detected (0/20)")

    # Criterion 4: Data write operation (10 pts)
    if has_graph and result.get('graph_has_write'):
        score += 10
        feedback.append("Graph has Write operator (+10)")
    elif has_script and result.get('output_product_found'):
        score += 10
        feedback.append("Script produced output (+10)")
    elif result.get('output_product_found'):
        score += 8
        feedback.append("Output product exists (+8)")
    else:
        feedback.append("No write operation detected (0/10)")

    # Criterion 5: Output product created after task start (20 pts)
    if result.get('output_product_found') and result.get('output_created_after_start'):
        score += 20
        feedback.append("Output product created after task start (+20)")
    elif result.get('output_product_found'):
        score += 10
        feedback.append("Output product found but timestamp unclear (+10)")
    else:
        feedback.append("No output product found (0/20)")

    # Criterion 6: Output contains spectral index band (20 pts)
    if result.get('output_has_index_band'):
        score += 20
        feedback.append("Spectral index band in output (+20)")
    elif result.get('output_band_count', 0) > 0:
        bands = result.get('output_band_names', [])
        # Check if any band looks like it could be a derived product
        has_derived = any(
            b.lower() not in ['band_1', 'band_2', 'band_3', 'band_4']
            for b in bands
        )
        if has_derived:
            score += 15
            feedback.append(f"Derived bands found: {bands} (+15)")
        else:
            score += 5
            feedback.append(f"Only original bands in output ({bands}) (+5)")
    else:
        feedback.append("No bands in output product (0/20)")

    passed = score >= 70
    return {"passed": passed, "score": score, "feedback": "; ".join(feedback)}
