#!/bin/bash
# Wrapper: seed OpenMRS O3 using the Python seeding script.
# The Python script uses real Synthea patient data and is idempotent.
set -e

echo "=== Seeding OpenMRS O3 with Synthea-derived patient data ==="

# Install requests if not present (needed by seed_openmrs.py)
python3 -c "import requests" 2>/dev/null || pip3 install requests -q

python3 /workspace/scripts/seed_openmrs.py

echo "=== Seeding complete ==="
