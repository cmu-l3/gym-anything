#!/usr/bin/env python3
"""Verifier for gpt_chain_processing task.

Scoring breakdown (must sum to exactly 100):
  GPT graph XML file exists:                  10 pts
  Graph has 2 Read nodes (both inputs):       10 pts
  Graph has Collocate operator:               15 pts
  Graph has BandMaths with index expression:  15 pts
  Graph has Subset operator:                  10 pts
  Graph has Write operator:                   5 pts
  Nodes are properly connected (sources):     10 pts
  Output product created after task start:    15 pts
  Output contains spectral index band:        10 pts
                                       TOTAL: 100 pts
Pass threshold: 70
"""

import json
import os
import tempfile


def verify_gpt_chain_processing(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "No copy_from_env available"}

    result_path = tempfile.mktemp(suffix='.json')
    try:
        copy_from_env('/tmp/gpt_chain_processing_result.json', result_path)
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

    # Criterion 1: GPT graph XML file exists (10 pts)
    if has_graph:
        score += 10
        feedback.append("GPT graph XML found (+10)")
    else:
        feedback.append("No GPT graph XML found (0/10)")

    # Criterion 2: Graph has 2 Read nodes for both inputs (10 pts)
    read_count = result.get('graph_read_count', 0)
    if has_graph and read_count >= 2:
        score += 10
        feedback.append(f"Graph has {read_count} Read nodes (+10)")
    elif has_graph and result.get('graph_has_read'):
        score += 5
        feedback.append("Graph has 1 Read node (+5)")
    elif has_graph:
        score += 2
        feedback.append("Graph exists but no Read operator detected (+2)")
    else:
        feedback.append("No Read operators (0/10)")

    # Criterion 3: Graph has Collocate operator (15 pts)
    if has_graph and result.get('graph_has_collocate'):
        score += 15
        feedback.append("Collocate operator found (+15)")
    elif has_graph:
        # Check if any operator name suggests merging/combining
        ops = [o.lower() for o in result.get('graph_operator_names', [])]
        has_merge = any(kw in o for o in ops
                        for kw in ['merge', 'stack', 'combine', 'mosaic'])
        if has_merge:
            score += 10
            feedback.append("Merge/combine operator found (partial) (+10)")
        else:
            feedback.append("No Collocate operator found (0/15)")
    else:
        feedback.append("No Collocate operator (0/15)")

    # Criterion 4: Graph has BandMaths with expression (15 pts)
    bm_expr = result.get('bandmaths_expression', '')
    if has_graph and result.get('graph_has_bandmaths') and bm_expr:
        el = bm_expr.lower().replace(' ', '')
        has_arith = '/' in el and ('-' in el or '+' in el)
        if has_arith:
            score += 15
            feedback.append(f"BandMaths with index expression (+15)")
        else:
            score += 12
            feedback.append("BandMaths with expression (+12)")
    elif has_graph and result.get('graph_has_bandmaths'):
        score += 10
        feedback.append("BandMaths operator found but no expression detected (+10)")
    elif has_graph:
        feedback.append("No BandMaths operator found (0/15)")
    else:
        feedback.append("No BandMaths operator (0/15)")

    # Criterion 5: Graph has Subset operator (10 pts)
    if has_graph and result.get('graph_has_subset'):
        score += 10
        feedback.append("Subset operator found (+10)")
    elif has_graph:
        ops = [o.lower() for o in result.get('graph_operator_names', [])]
        has_spatial = any(kw in o for o in ops
                         for kw in ['resample', 'reproject', 'crop'])
        if has_spatial:
            score += 7
            feedback.append("Spatial processing operator found (partial) (+7)")
        else:
            feedback.append("No Subset operator found (0/10)")
    else:
        feedback.append("No Subset operator (0/10)")

    # Criterion 6: Graph has Write operator (5 pts)
    if has_graph and result.get('graph_has_write'):
        score += 5
        feedback.append("Write operator found (+5)")
    elif has_graph:
        feedback.append("No Write operator found (0/5)")
    else:
        feedback.append("No Write operator (0/5)")

    # Criterion 7: Nodes are properly connected via source references (10 pts)
    if has_graph and result.get('graph_has_node_connections'):
        op_count = result.get('graph_operator_count', 0)
        if op_count >= 5:
            score += 10
            feedback.append(f"Nodes connected, {op_count} operators in chain (+10)")
        elif op_count >= 3:
            score += 7
            feedback.append(f"Nodes connected, {op_count} operators (+7)")
        else:
            score += 5
            feedback.append("Nodes connected (+5)")
    elif has_graph:
        score += 3
        feedback.append("Graph exists but node connections unclear (+3)")
    else:
        feedback.append("No node connections (0/10)")

    # Criterion 8: Output product created after task start (15 pts)
    if result.get('output_product_found') and result.get('output_created_after_start'):
        score += 15
        feedback.append("Output product created after task start (+15)")
    elif result.get('output_product_found'):
        score += 8
        feedback.append("Output product found but timestamp unclear (+8)")
    else:
        feedback.append("No output product found (0/15)")

    # Criterion 9: Output contains spectral index band (10 pts)
    if result.get('output_has_index_band'):
        score += 10
        feedback.append("Spectral index band in output (+10)")
    elif result.get('output_band_count', 0) > 0:
        bands = result.get('output_band_names', [])
        has_derived = any(
            b.lower() not in ['band_1', 'band_2', 'band_3', 'band_4',
                               'b04', 'b08', 'red', 'nir']
            for b in bands
        )
        if has_derived:
            score += 7
            feedback.append(f"Derived bands found: {bands} (+7)")
        else:
            score += 3
            feedback.append(f"Only source bands in output ({bands}) (+3)")
    else:
        feedback.append("No bands in output (0/10)")

    passed = score >= 70
    return {"passed": passed, "score": score, "feedback": "; ".join(feedback)}
