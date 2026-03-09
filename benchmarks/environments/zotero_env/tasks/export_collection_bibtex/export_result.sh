#!/bin/bash
# Export result for export_collection_bibtex task

echo "=== Exporting export_collection_bibtex result ==="

OUTPUT_FILE="/home/ga/Desktop/ml_bibliography.bib"

# Take final screenshot
DISPLAY=:1 import -window root /tmp/task_end_screenshot.png 2>/dev/null || \
DISPLAY=:1 scrot /tmp/task_end_screenshot.png 2>/dev/null || true

sleep 1

python3 << 'PYEOF'
import os
import json
import re

OUTPUT_FILE = "/home/ga/Desktop/ml_bibliography.bib"

# Also check common alternative locations agents might use
ALTERNATIVE_PATHS = [
    "/home/ga/Desktop/ml_bibliography.bib",
    "/home/ga/Desktop/ML References.bib",
    "/home/ga/Desktop/MLReferences.bib",
    "/home/ga/Documents/ml_bibliography.bib",
    "/home/ga/ml_bibliography.bib",
]

result = {
    "file_exists": False,
    "file_path_used": None,
    "file_size_bytes": 0,
    "bibtex_entry_count": 0,
    "has_bibtex_entries": False,
    "found_authors": [],
    "missing_authors": [],
    "raw_content_preview": "",
}

# Expected authors (last names in BibTeX author fields)
EXPECTED_AUTHORS = ["Vaswani", "Devlin", "Brown", "Krizhevsky", "He", "Goodfellow", "LeCun", "Silver"]

# Find the file
found_path = None
for path in ALTERNATIVE_PATHS:
    if os.path.exists(path):
        found_path = path
        break

if found_path:
    result["file_exists"] = True
    result["file_path_used"] = found_path
    try:
        with open(found_path, "r", encoding="utf-8", errors="replace") as f:
            content = f.read()
        result["file_size_bytes"] = len(content.encode("utf-8"))
        result["raw_content_preview"] = content[:1000]

        # Count BibTeX entries
        entries = re.findall(r'@\w+\s*\{', content, re.IGNORECASE)
        result["bibtex_entry_count"] = len(entries)
        result["has_bibtex_entries"] = len(entries) > 0

        # Check for expected authors
        content_lower = content.lower()
        for author in EXPECTED_AUTHORS:
            if author.lower() in content_lower:
                result["found_authors"].append(author)
            else:
                result["missing_authors"].append(author)

    except Exception as e:
        result["read_error"] = str(e)
else:
    result["searched_paths"] = ALTERNATIVE_PATHS
    result["desktop_files"] = os.listdir("/home/ga/Desktop") if os.path.isdir("/home/ga/Desktop") else []

with open("/tmp/export_collection_bibtex_result.json", "w") as f:
    json.dump(result, f, indent=2)

print(f"File exists: {result['file_exists']}")
print(f"Path: {result['file_path_used']}")
print(f"Size: {result['file_size_bytes']} bytes")
print(f"BibTeX entries: {result['bibtex_entry_count']}")
print(f"Authors found: {result['found_authors']}")
print(f"Authors missing: {result['missing_authors']}")
PYEOF

echo "=== Export Complete: export_collection_bibtex ==="
