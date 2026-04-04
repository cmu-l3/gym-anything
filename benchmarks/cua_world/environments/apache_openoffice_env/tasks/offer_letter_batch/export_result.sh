#!/bin/bash
echo "=== Exporting Offer Letter Batch Result ==="
source /workspace/scripts/task_utils.sh

take_screenshot "offer_letter_export"

python3 << 'PYEOF'
import json
import os
import zipfile
import re

DOCS_DIR = "/home/ga/Documents/"
EXPECTED_FILES = [
    "offer_letter_Okonkwo_Amara.odt",
    "offer_letter_Tremblay_Kevin.odt",
    "offer_letter_Nair_Preethi.odt",
    "offer_letter_Vasquez_Jordan.odt",
    "offer_letter_Petrov_Marcus.odt"
]

# Expected content markers per hire (last name, title keyword, salary string)
HIRE_CHECKS = [
    {"file": "offer_letter_Okonkwo_Amara.odt",
     "markers": ["okonkwo", "regulatory affairs", "87,500"]},
    {"file": "offer_letter_Tremblay_Kevin.odt",
     "markers": ["tremblay", "quality systems", "92,000"]},
    {"file": "offer_letter_Nair_Preethi.odt",
     "markers": ["nair", "r&d", "118,000"]},
    {"file": "offer_letter_Vasquez_Jordan.odt",
     "markers": ["vasquez", "field service", "68,000"]},
    {"file": "offer_letter_Petrov_Marcus.odt",
     "markers": ["petrov", "clinical", "105,000"]},
]

result = {
    "letters": {},
    "letters_found": 0,
    "letters_with_correct_content": 0,
    "letters_substantial": 0
}

for fcheck in HIRE_CHECKS:
    fname = fcheck["file"]
    fpath = os.path.join(DOCS_DIR, fname)
    letter_result = {
        "exists": False,
        "file_size": 0,
        "is_substantial": False,
        "has_correct_content": False,
        "markers_found": []
    }

    if os.path.exists(fpath):
        letter_result["exists"] = True
        letter_result["file_size"] = os.path.getsize(fpath)
        letter_result["is_substantial"] = letter_result["file_size"] >= 2000
        result["letters_found"] += 1

        if letter_result["is_substantial"]:
            result["letters_substantial"] += 1

        try:
            with zipfile.ZipFile(fpath, 'r') as z:
                with z.open('content.xml') as cf:
                    content = cf.read().decode('utf-8', errors='replace')
            plain_text = re.sub(r'<[^>]+>', ' ', content).lower()

            markers_found = []
            for marker in fcheck["markers"]:
                if marker.lower() in plain_text:
                    markers_found.append(marker)

            letter_result["markers_found"] = markers_found
            letter_result["has_correct_content"] = len(markers_found) >= 2
            if letter_result["has_correct_content"]:
                result["letters_with_correct_content"] += 1

        except Exception as e:
            letter_result["parse_error"] = str(e)

    result["letters"][fname] = letter_result

with open("/tmp/task_result.json", "w") as f:
    json.dump(result, f, indent=2)

print(f"Export complete: found={result['letters_found']}/5, "
      f"substantial={result['letters_substantial']}/5, "
      f"correct_content={result['letters_with_correct_content']}/5")
PYEOF

echo "=== Export Complete ==="
