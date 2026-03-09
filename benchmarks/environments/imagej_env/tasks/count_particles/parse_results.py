#!/usr/bin/env python3
"""
Parse ImageJ/Fiji results files and create task_result.json.

This script is called by export_result.sh and reads shell variables
from /tmp/export_shell_vars.json to avoid HEREDOC interpolation issues.
"""

import csv
import json
import os
import sys
from datetime import datetime


def parse_results_file(filepath):
    """Parse individual particle Results CSV file."""
    if not filepath or not os.path.exists(filepath):
        return None

    print(f"Parsing Results file: {filepath}")

    try:
        with open(filepath, 'r', encoding='utf-8', errors='replace') as f:
            content = f.read()
            print(f"File content (first 500 chars):\n{content[:500]}")

        areas = []
        with open(filepath, 'r', encoding='utf-8', errors='replace') as f:
            # Try to detect delimiter
            first_line = f.readline()
            f.seek(0)

            delimiter = ',' if ',' in first_line else '\t'
            reader = csv.DictReader(f, delimiter=delimiter)

            for row in reader:
                # ImageJ uses "Area" column
                area_val = row.get('Area') or row.get('area') or row.get(' Area')
                if area_val:
                    try:
                        area = float(area_val.strip())
                        areas.append(area)
                    except (ValueError, TypeError) as e:
                        print(f"  Skipping invalid area value: {area_val} ({e})")

        if areas:
            result = {
                "particle_count": len(areas),
                "avg_area": round(sum(areas) / len(areas), 2),
                "min_area": round(min(areas), 2),
                "max_area": round(max(areas), 2),
                "total_area": round(sum(areas), 2)
            }
            print(f"Parsed {len(areas)} particles from Results file")
            print(f"  avg_area={result['avg_area']}, min={result['min_area']}, max={result['max_area']}")
            return result
        else:
            print("No valid Area data found in Results file")
            return None

    except Exception as e:
        print(f"Error parsing Results file: {e}")
        import traceback
        traceback.print_exc()
        return None


def parse_summary_file(filepath):
    """Parse Summary CSV file from Analyze Particles with Summarize option."""
    if not filepath or not os.path.exists(filepath):
        return None

    print(f"Parsing Summary file: {filepath}")

    try:
        with open(filepath, 'r', encoding='utf-8', errors='replace') as f:
            content = f.read()
            print(f"File content:\n{content}")

        with open(filepath, 'r', encoding='utf-8', errors='replace') as f:
            # Try to detect delimiter
            first_line = f.readline()
            f.seek(0)

            delimiter = ',' if ',' in first_line else '\t'
            reader = csv.DictReader(f, delimiter=delimiter)

            for row in reader:
                print(f"Row keys: {list(row.keys())}")
                print(f"Row values: {row}")

                # Parse Count - try multiple column name variations
                count = 0
                for key in ['Count', 'count', ' Count', 'COUNT']:
                    if key in row:
                        try:
                            count = int(row[key].strip())
                            print(f"  Found Count={count} in column '{key}'")
                            break
                        except (ValueError, TypeError):
                            pass

                # Parse Total Area
                total_area = 0.0
                for key in ['Total Area', 'total area', ' Total Area', 'TotalArea', 'TOTAL AREA']:
                    if key in row:
                        try:
                            total_area = float(row[key].strip())
                            print(f"  Found Total Area={total_area} in column '{key}'")
                            break
                        except (ValueError, TypeError):
                            pass

                # Parse Average Size
                avg_area = 0.0
                for key in ['Average Size', 'average size', ' Average Size', 'AverageSize', 'AVERAGE SIZE', 'Avg Size']:
                    if key in row:
                        try:
                            avg_area = float(row[key].strip())
                            print(f"  Found Average Size={avg_area} in column '{key}'")
                            break
                        except (ValueError, TypeError):
                            pass

                if count > 0:
                    result = {
                        "particle_count": count,
                        "avg_area": round(avg_area, 2),
                        "total_area": round(total_area, 2)
                    }
                    print(f"Successfully parsed Summary: count={count}, avg={avg_area}, total={total_area}")
                    return result

                # Only process first data row
                break

        print("No valid data found in Summary file")
        return None

    except Exception as e:
        print(f"Error parsing Summary file: {e}")
        import traceback
        traceback.print_exc()
        return None


def main():
    # Read shell variables from temp file
    vars_file = "/tmp/export_shell_vars.json"

    if not os.path.exists(vars_file):
        print(f"ERROR: Shell variables file not found: {vars_file}")
        sys.exit(1)

    try:
        with open(vars_file, 'r') as f:
            shell_vars = json.load(f)
        print(f"Loaded shell variables: {json.dumps(shell_vars, indent=2)}")
    except Exception as e:
        print(f"ERROR: Failed to load shell variables: {e}")
        sys.exit(1)

    # Extract variables
    results_file = shell_vars.get('results_file', '')
    summary_file = shell_vars.get('summary_file', '')
    results_window = shell_vars.get('results_window', 'false') == 'true'
    summary_window = shell_vars.get('summary_window', 'false') == 'true'
    image_window = shell_vars.get('image_window', 'false') == 'true'
    image_name = shell_vars.get('image_name', '')
    threshold_applied = shell_vars.get('threshold_applied', 'false') == 'true'
    final_screenshot = shell_vars.get('final_screenshot', '')
    windows_list = shell_vars.get('windows_list', '')

    # Initialize results
    particle_count = 0
    avg_area = 0.0
    min_area = 0.0
    max_area = 0.0
    total_area = 0.0
    has_measurements = False
    results_file_found = bool(results_file and os.path.exists(results_file))
    summary_file_found = bool(summary_file and os.path.exists(summary_file))

    print(f"\nResults file: {results_file} (exists: {results_file_found})")
    print(f"Summary file: {summary_file} (exists: {summary_file_found})")

    # Parse Results file first (has individual particle data with min/max)
    if results_file_found:
        results_data = parse_results_file(results_file)
        if results_data:
            particle_count = results_data['particle_count']
            avg_area = results_data['avg_area']
            min_area = results_data['min_area']
            max_area = results_data['max_area']
            total_area = results_data['total_area']
            has_measurements = True

    # Parse Summary file (may have better count if Results file is incomplete)
    if summary_file_found:
        summary_data = parse_summary_file(summary_file)
        if summary_data:
            # Use Summary data if it has more particles or if we have no data yet
            if summary_data['particle_count'] > 0:
                if particle_count == 0 or summary_data['particle_count'] >= particle_count:
                    particle_count = summary_data['particle_count']
                    avg_area = summary_data['avg_area']
                    total_area = summary_data['total_area']
                    has_measurements = True
                    print(f"Updated from Summary: count={particle_count}, avg={avg_area}")

    # Create final result
    result = {
        "particle_count": particle_count,
        "avg_area": avg_area,
        "min_area": min_area,
        "max_area": max_area,
        "total_area": total_area,
        "has_measurements": has_measurements,
        "results_file_found": results_file_found,
        "results_file_path": results_file if results_file_found else "",
        "summary_file_found": summary_file_found,
        "summary_file_path": summary_file if summary_file_found else "",
        "results_window_visible": results_window,
        "summary_window_visible": summary_window,
        "image_window_visible": image_window,
        "image_name": image_name,
        "threshold_applied": threshold_applied,
        "screenshot_path": final_screenshot,
        "windows_list": windows_list,
        "timestamp": datetime.now().isoformat()
    }

    print(f"\n=== Final Result ===")
    print(json.dumps(result, indent=2))

    # Write to output file
    output_file = "/tmp/task_result.json"
    try:
        with open(output_file, 'w') as f:
            json.dump(result, f, indent=2)
        os.chmod(output_file, 0o666)
        print(f"\nResult written to {output_file}")
    except Exception as e:
        print(f"ERROR: Failed to write result: {e}")
        sys.exit(1)


if __name__ == "__main__":
    main()
