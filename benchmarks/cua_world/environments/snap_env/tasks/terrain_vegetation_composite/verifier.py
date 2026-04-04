#!/usr/bin/env python3
"""Verifier for terrain_vegetation_composite task.

Scoring breakdown (must sum to exactly 100):
  Product saved in DIMAP format:              10 pts
  Multi-source integration (DEM + optical):   15 pts
  Vegetation index from optical bands:        15 pts
  Terrain steepness metric from DEM:          15 pts
  Combined terrain-vegetation composite:      10 pts
  Suitability classification (conditionals):  20 pts
  GeoTIFF exported with non-trivial size:     15 pts
                                       TOTAL: 100 pts
Pass threshold: 70
"""

import json
import os
import tempfile


def verify_terrain_vegetation_composite(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "No copy_from_env available"}

    result_path = tempfile.mktemp(suffix='.json')
    try:
        copy_from_env('/tmp/terrain_vegetation_composite_result.json', result_path)
        with open(result_path) as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve result: {e}"}
    finally:
        if os.path.exists(result_path):
            os.unlink(result_path)

    score = 0
    feedback = []

    # Criterion 1: Product saved in DIMAP format (10 pts)
    if result.get('dim_found') and result.get('dim_created_after_start'):
        score += 10
        feedback.append("Product saved (+10)")
    elif result.get('dim_found'):
        score += 7
        feedback.append("Product found but timestamp unclear (+7)")
    else:
        feedback.append("No saved product found (0/10)")

    # Criterion 2: Multi-source integration — DEM + optical in same product (15 pts)
    if result.get('has_multisource_bands'):
        score += 15
        feedback.append("DEM + optical bands in same product (+15)")
    elif result.get('has_dem_band') and result.get('has_optical_bands'):
        score += 12
        feedback.append("Both data sources found (+12)")
    elif result.get('has_dem_band') or result.get('has_optical_bands'):
        score += 5
        feedback.append("Only one data source found (+5)")
    else:
        # Check total band count as proxy
        if result.get('total_band_count', 0) >= 5:
            score += 5
            feedback.append("Multiple bands suggest integration (+5)")
        else:
            feedback.append("No multi-source integration detected (0/15)")

    # Criterion 3: Vegetation index from optical bands (15 pts)
    veg_expr = result.get('vegetation_expression', '')
    if result.get('has_vegetation_index') and veg_expr:
        el = veg_expr.lower().replace(' ', '')
        has_nir = any(kw in el for kw in ['band_2', 'nir', 'b2'])
        has_red = any(kw in el for kw in ['band_3', 'red', 'b3'])
        has_arith = '/' in el and '-' in el
        if has_nir and has_red and has_arith:
            score += 15
            feedback.append("Vegetation index with correct expression (+15)")
        else:
            score += 12
            feedback.append("Vegetation index with expression (+12)")
    elif result.get('has_vegetation_index'):
        score += 8
        feedback.append("Vegetation index found but no expression (+8)")
    else:
        feedback.append("No vegetation index found (0/15)")

    # Criterion 4: Terrain steepness metric from DEM (15 pts)
    terr_expr = result.get('terrain_expression', '')
    if result.get('has_terrain_metric') and terr_expr:
        el = terr_expr.lower().replace(' ', '')
        refs_dem = any(kw in el for kw in ['elevation', 'dem', 'srtm', 'height',
                                            'band_1', 'altitude'])
        if refs_dem:
            score += 15
            feedback.append("Terrain metric referencing DEM data (+15)")
        else:
            score += 12
            feedback.append("Terrain metric with expression (+12)")
    elif result.get('has_terrain_metric'):
        score += 8
        feedback.append("Terrain metric found but no expression (+8)")
    else:
        # Check for any band derived from DEM
        vbands = result.get('virtual_bands', {})
        dem_derived = any(
            any(kw in e.lower() for kw in ['elevation', 'dem', 'srtm', 'height'])
            for e in vbands.values()
        )
        if dem_derived:
            score += 8
            feedback.append("DEM-derived band found (+8)")
        else:
            feedback.append("No terrain metric found (0/15)")

    # Criterion 5: Combined terrain-vegetation composite (10 pts)
    comp_expr = result.get('composite_expression', '')
    if result.get('has_composite') and comp_expr:
        score += 10
        feedback.append("Terrain-vegetation composite found (+10)")
    elif result.get('has_composite'):
        score += 7
        feedback.append("Composite band exists (+7)")
    else:
        # Check if suitability expression references both sources
        suit_expr = result.get('suitability_expression', '')
        if suit_expr:
            el = suit_expr.lower().replace(' ', '')
            refs_veg = any(kw in el for kw in ['ndvi', 'vegetation', 'veg'])
            refs_terr = any(kw in el for kw in ['slope', 'elevation', 'dem',
                                                 'terrain', 'steep'])
            if refs_veg and refs_terr:
                score += 7
                feedback.append("Suitability references both sources (+7)")
            else:
                feedback.append("No composite band found (0/10)")
        else:
            feedback.append("No composite band found (0/10)")

    # Criterion 6: Suitability classification with conditionals (20 pts)
    suit_expr = result.get('suitability_expression', '')
    if result.get('has_suitability_class') and suit_expr:
        el = suit_expr.lower().replace(' ', '')
        has_cond = any(kw in el for kw in ['if(', 'if (', '?'])
        nested = el.count('if(') + el.count('if (')
        has_nums = any(c.isdigit() for c in el)
        if has_cond and nested >= 2 and has_nums:
            score += 20
            feedback.append("Suitability with nested conditionals (+20)")
        elif has_cond and has_nums:
            score += 15
            feedback.append("Suitability with conditional thresholds (+15)")
        elif has_cond:
            score += 10
            feedback.append("Suitability with basic conditional (+10)")
        else:
            score += 8
            feedback.append("Suitability band with expression (+8)")
    elif result.get('has_suitability_class'):
        score += 8
        feedback.append("Suitability band exists but no expression (+8)")
    else:
        vbands = result.get('virtual_bands', {})
        has_conditional = any(
            'if(' in e.lower().replace(' ', '') or '?' in e
            for e in vbands.values()
        )
        if has_conditional:
            score += 8
            feedback.append("Conditional expression in unnamed band (+8)")
        else:
            feedback.append("No suitability classification found (0/20)")

    # Criterion 7: GeoTIFF exported with non-trivial size (15 pts)
    tif_size = result.get('tif_file_size', 0)
    if result.get('tif_found') and result.get('tif_created_after_start') and tif_size > 1024:
        score += 15
        feedback.append(f"GeoTIFF exported ({tif_size} bytes) (+15)")
    elif result.get('tif_found') and result.get('tif_created_after_start'):
        score += 10
        feedback.append(f"GeoTIFF exported but small ({tif_size} bytes) (+10)")
    elif result.get('tif_found'):
        score += 5
        feedback.append("GeoTIFF found but timestamp unclear (+5)")
    else:
        feedback.append("No GeoTIFF export found (0/15)")

    passed = score >= 70
    return {"passed": passed, "score": score, "feedback": "; ".join(feedback)}
