#!/usr/bin/env python3
"""
Verifier for travel_package_catalog_builder@1.
Checks schema extensions, data entry, graph structure, and pricing logic.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_travel_package_catalog_builder(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load expected values from metadata
    metadata = task_info.get('metadata', {})
    expected_packages = metadata.get('expected_packages', {
        "Roman Holiday": 301.5,
        "Parisian Romance": 927.0,
        "Tokyo Tech": 828.0
    })
    tolerance = metadata.get('tolerance', 0.5)

    # Copy result file
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []

    # ------------------------------------------------------------------
    # 1. Schema Verification (15 points)
    # ------------------------------------------------------------------
    schema = result.get('schema', {})
    classes = {c['name']: c for c in schema.get('classes', [])}
    
    schema_passed = True
    missing_schema = []

    # Check Classes
    if 'Packages' not in classes:
        missing_schema.append("Class 'Packages'")
        schema_passed = False
    if 'IncludesItem' not in classes:
        missing_schema.append("Class 'IncludesItem'")
        schema_passed = False
    
    # Check Properties (Price on Hotels, Restaurants, Attractions)
    for cls_name in ['Hotels', 'Restaurants', 'Attractions']:
        if cls_name in classes:
            props = {p['name'] for p in classes[cls_name].get('properties', [])}
            if 'Price' not in props:
                missing_schema.append(f"Property 'Price' on {cls_name}")
                schema_passed = False
        else:
            missing_schema.append(f"Class '{cls_name}'")
            schema_passed = False
            
    # Check TotalPrice on Packages
    if 'Packages' in classes:
        props = {p['name'] for p in classes['Packages'].get('properties', [])}
        if 'TotalPrice' not in props:
            missing_schema.append("Property 'TotalPrice' on Packages")
            schema_passed = False

    if schema_passed:
        score += 15
        feedback.append("Schema extended correctly.")
    else:
        feedback.append(f"Schema missing: {', '.join(missing_schema)}.")

    # ------------------------------------------------------------------
    # 2. Data Entry & Pricing Verification (20 points)
    # ------------------------------------------------------------------
    entity_prices = {item.get('Name'): item.get('Price') for item in result.get('entity_prices', [])}
    
    expected_data = {
        'Hotel Artemide': 250.0,
        'Hotel de Crillon': 800.0,
        'Park Hyatt Tokyo': 600.0,
        'Roma Sparita': 60.0,
        'Le Jules Verne': 200.0,
        'Sushi Saito': 300.0,
        'Colosseum': 25.0,
        'Eiffel Tower': 30.0,
        'Tokyo Tower': 20.0
    }
    
    data_correct_count = 0
    for name, expected_price in expected_data.items():
        actual_price = entity_prices.get(name)
        if actual_price is not None and abs(actual_price - expected_price) < 0.1:
            data_correct_count += 1
    
    # Prorate score for data entry
    data_score = int((data_correct_count / len(expected_data)) * 20)
    score += data_score
    if data_correct_count == len(expected_data):
        feedback.append("All entity prices set correctly.")
    else:
        feedback.append(f"Entity prices: {data_correct_count}/{len(expected_data)} correct.")

    # ------------------------------------------------------------------
    # 3. Graph Construction Verification (35 points)
    # ------------------------------------------------------------------
    graph_structure = result.get('graph_structure', [])
    graph_map = {pkg.get('PackageName'): set(pkg.get('Items', [])) for pkg in graph_structure}
    
    expected_graph = {
        "Roman Holiday": {"Hotel Artemide", "Roma Sparita", "Colosseum"},
        "Parisian Romance": {"Hotel de Crillon", "Le Jules Verne", "Eiffel Tower"},
        "Tokyo Tech": {"Park Hyatt Tokyo", "Sushi Saito", "Tokyo Tower"}
    }
    
    graph_correct_count = 0
    for pkg_name, expected_items in expected_graph.items():
        actual_items = set(graph_map.get(pkg_name, []))
        # Check if expected items are a subset of actual items (allowing for extra noise, though ideally exact)
        # Using exact match for rigor
        if expected_items == actual_items:
            graph_correct_count += 1
    
    graph_score = int((graph_correct_count / 3) * 35)
    score += graph_score
    
    if graph_correct_count == 3:
        feedback.append("Graph structure (packages linking to items) is correct.")
    else:
        feedback.append(f"Graph structure: {graph_correct_count}/3 packages correct.")

    # ------------------------------------------------------------------
    # 4. Price Logic Verification (30 points)
    # ------------------------------------------------------------------
    packages = {p.get('Name'): p.get('TotalPrice') for p in result.get('packages', [])}
    
    logic_correct_count = 0
    for pkg_name, expected_price in expected_packages.items():
        actual_price = packages.get(pkg_name)
        if actual_price is not None and abs(actual_price - expected_price) <= tolerance:
            logic_correct_count += 1
    
    logic_score = int((logic_correct_count / 3) * 30)
    score += logic_score
    
    if logic_correct_count == 3:
        feedback.append("Package TotalPrice calculations are correct.")
    else:
        feedback.append(f"Price logic: {logic_correct_count}/3 packages correct.")

    # ------------------------------------------------------------------
    # Anti-Gaming Check
    # ------------------------------------------------------------------
    # Ensure data wasn't just statically inserted without structure
    # The graph check already validates the structure exists.
    # We can check timestamps if they were available in the query, but structure + logic is strong evidence.
    
    passed = (score >= 85)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }