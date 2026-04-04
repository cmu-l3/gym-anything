#!/bin/bash
echo "=== Setting up increase_test_coverage ==="

. /workspace/scripts/task_utils.sh 2>/dev/null || true

TASK_NAME="increase_test_coverage"
PROJECT_DIR="/home/ga/PycharmProjects/clinical_validator"

rm -rf "$PROJECT_DIR"
rm -f /tmp/${TASK_NAME}_start_ts /tmp/${TASK_NAME}_result.json

mkdir -p "$PROJECT_DIR/validator"
mkdir -p "$PROJECT_DIR/tests"

# requirements.txt
cat > "$PROJECT_DIR/requirements.txt" << 'REQUIREMENTS'
pytest>=7.0
pytest-cov>=4.0
REQUIREMENTS

# ============================================================
# validator/__init__.py
# ============================================================
touch "$PROJECT_DIR/validator/__init__.py"

# ============================================================
# validator/demographics.py
# Validates patient demographic records
# ============================================================
cat > "$PROJECT_DIR/validator/demographics.py" << 'PYEOF'
"""Validates patient demographic records."""
import re
from datetime import date, datetime
from typing import Optional


class DemographicsValidationError(ValueError):
    pass


def validate_mrn(mrn: str) -> str:
    """
    Validate Medical Record Number.
    Must be 8-12 alphanumeric characters, uppercase letters only.
    Returns cleaned (stripped, uppercased) MRN.
    Raises DemographicsValidationError if invalid.
    """
    if not isinstance(mrn, str):
        raise DemographicsValidationError(f"MRN must be a string, got {type(mrn).__name__}")
    mrn = mrn.strip().upper()
    if not mrn:
        raise DemographicsValidationError("MRN cannot be empty")
    if not re.match(r'^[A-Z0-9]{8,12}$', mrn):
        raise DemographicsValidationError(
            f"MRN '{mrn}' is invalid: must be 8-12 uppercase alphanumeric characters"
        )
    return mrn


def validate_date_of_birth(dob: str) -> date:
    """
    Parse and validate date of birth.
    Accepts formats: YYYY-MM-DD, MM/DD/YYYY, DD-Mon-YYYY (e.g. 15-Jan-1980).
    Patient must be between 0 and 130 years old.
    Raises DemographicsValidationError if invalid.
    """
    if not isinstance(dob, str):
        raise DemographicsValidationError("Date of birth must be a string")
    dob = dob.strip()

    parsed = None
    for fmt in ("%Y-%m-%d", "%m/%d/%Y", "%d-%b-%Y"):
        try:
            parsed = datetime.strptime(dob, fmt).date()
            break
        except ValueError:
            continue

    if parsed is None:
        raise DemographicsValidationError(
            f"Unrecognized date format: '{dob}'. Accepted: YYYY-MM-DD, MM/DD/YYYY, DD-Mon-YYYY"
        )

    today = date.today()
    if parsed > today:
        raise DemographicsValidationError(f"Date of birth {parsed} is in the future")

    age_years = (today - parsed).days / 365.25
    if age_years > 130:
        raise DemographicsValidationError(
            f"Date of birth {parsed} implies age > 130 years, which is implausible"
        )

    return parsed


def validate_sex(sex: str) -> str:
    """
    Validate biological sex field.
    Accepts: M, F, Male, Female, male, female (case-insensitive).
    Returns normalized: 'M' or 'F'.
    """
    if not isinstance(sex, str):
        raise DemographicsValidationError("Sex must be a string")
    normalized = sex.strip().upper()
    if normalized in ('M', 'MALE'):
        return 'M'
    if normalized in ('F', 'FEMALE'):
        return 'F'
    raise DemographicsValidationError(
        f"Sex '{sex}' is not recognized. Accepted: M, F, Male, Female"
    )


def validate_zip_code(zip_code: str) -> str:
    """
    Validate US ZIP code (5-digit or ZIP+4 format).
    Returns cleaned ZIP.
    """
    if not isinstance(zip_code, str):
        raise DemographicsValidationError("ZIP code must be a string")
    zip_code = zip_code.strip()
    if re.match(r'^\d{5}$', zip_code):
        return zip_code
    if re.match(r'^\d{5}-\d{4}$', zip_code):
        return zip_code
    raise DemographicsValidationError(
        f"ZIP code '{zip_code}' is invalid: must be 5 digits or 5+4 format (e.g. 12345 or 12345-6789)"
    )


def validate_patient_record(record: dict) -> dict:
    """
    Validate a complete patient demographics record.
    Required fields: mrn, date_of_birth, sex
    Optional fields: zip_code
    Returns validated record with normalized values.
    """
    errors = []
    validated = {}

    for field in ('mrn', 'date_of_birth', 'sex'):
        if field not in record:
            errors.append(f"Missing required field: {field}")

    if errors:
        raise DemographicsValidationError("; ".join(errors))

    try:
        validated['mrn'] = validate_mrn(record['mrn'])
    except DemographicsValidationError as e:
        errors.append(str(e))

    try:
        validated['date_of_birth'] = validate_date_of_birth(record['date_of_birth'])
    except DemographicsValidationError as e:
        errors.append(str(e))

    try:
        validated['sex'] = validate_sex(record['sex'])
    except DemographicsValidationError as e:
        errors.append(str(e))

    if 'zip_code' in record:
        try:
            validated['zip_code'] = validate_zip_code(record['zip_code'])
        except DemographicsValidationError as e:
            errors.append(str(e))

    if errors:
        raise DemographicsValidationError("; ".join(errors))

    return validated
PYEOF

# ============================================================
# validator/labs.py
# Validates laboratory test results
# ============================================================
cat > "$PROJECT_DIR/validator/labs.py" << 'PYEOF'
"""Validates laboratory test results against reference ranges."""
from typing import Optional


class LabValidationError(ValueError):
    pass


# Reference ranges for common lab tests
# (test_code, unit): (critical_low, low_normal, high_normal, critical_high)
LAB_REFERENCE_RANGES = {
    ("WBC",  "10^3/uL"): (0.5,  4.5,  11.0, 30.0),
    ("HGB",  "g/dL"):    (5.0,  12.0, 17.5, 20.0),
    ("PLT",  "10^3/uL"): (20.0, 150.0, 400.0, 1000.0),
    ("NA",   "mEq/L"):   (120.0, 136.0, 145.0, 160.0),
    ("K",    "mEq/L"):   (2.5,  3.5,  5.0,  6.5),
    ("CR",   "mg/dL"):   (0.1,  0.6,  1.2,  10.0),
    ("GLU",  "mg/dL"):   (40.0, 70.0, 100.0, 500.0),
    ("TROP", "ng/mL"):   (0.0,  0.0,  0.04, 10.0),
}


def validate_lab_value(test_code: str, value: float, unit: str) -> dict:
    """
    Validate a lab result value.
    Returns dict with keys: test_code, value, unit, status
    status is one of: 'normal', 'low', 'high', 'critical_low', 'critical_high'
    Raises LabValidationError if test_code/unit pair is unknown or value is negative.
    """
    if not isinstance(test_code, str) or not test_code.strip():
        raise LabValidationError("test_code must be a non-empty string")
    test_code = test_code.strip().upper()

    if not isinstance(unit, str) or not unit.strip():
        raise LabValidationError("unit must be a non-empty string")

    if not isinstance(value, (int, float)):
        raise LabValidationError(f"value must be numeric, got {type(value).__name__}")

    if value < 0:
        raise LabValidationError(f"Lab value {value} cannot be negative")

    key = (test_code, unit)
    if key not in LAB_REFERENCE_RANGES:
        raise LabValidationError(
            f"Unknown test/unit combination: {test_code} / {unit}. "
            f"Supported: {list(LAB_REFERENCE_RANGES.keys())}"
        )

    crit_low, low_normal, high_normal, crit_high = LAB_REFERENCE_RANGES[key]

    if value < crit_low:
        status = 'critical_low'
    elif value < low_normal:
        status = 'low'
    elif value <= high_normal:
        status = 'normal'
    elif value <= crit_high:
        status = 'high'
    else:
        status = 'critical_high'

    return {
        'test_code': test_code,
        'value': float(value),
        'unit': unit,
        'status': status,
    }


def validate_lab_panel(results: list) -> list:
    """
    Validate a list of lab result dicts, each with keys: test_code, value, unit.
    Returns list of validated result dicts.
    Raises LabValidationError if any result is invalid or list is empty.
    """
    if not isinstance(results, list):
        raise LabValidationError("Lab panel must be a list")
    if len(results) == 0:
        raise LabValidationError("Lab panel cannot be empty")

    validated = []
    for i, result in enumerate(results):
        if not isinstance(result, dict):
            raise LabValidationError(f"Result at index {i} must be a dict")
        for key in ('test_code', 'value', 'unit'):
            if key not in result:
                raise LabValidationError(f"Result at index {i} missing field '{key}'")
        validated.append(
            validate_lab_value(result['test_code'], result['value'], result['unit'])
        )
    return validated
PYEOF

# ============================================================
# validator/medications.py
# Validates medication dosage orders
# ============================================================
cat > "$PROJECT_DIR/validator/medications.py" << 'PYEOF'
"""Validates medication dosage orders."""
from typing import Optional


class MedicationValidationError(ValueError):
    pass


# Max single-dose limits per medication (in mg), based on standard formulary
MAX_SINGLE_DOSE_MG = {
    "acetaminophen": 1000.0,
    "ibuprofen":     800.0,
    "amoxicillin":   875.0,
    "metformin":     1000.0,
    "lisinopril":    40.0,
    "atorvastatin":  80.0,
    "metoprolol":    200.0,
    "furosemide":    600.0,
    "morphine":      30.0,
    "warfarin":      15.0,
}

VALID_ROUTES = {"oral", "iv", "im", "subcutaneous", "topical", "rectal", "inhalation"}
VALID_FREQUENCIES = {"daily", "bid", "tid", "qid", "q4h", "q6h", "q8h", "q12h", "prn", "once"}


def validate_medication_name(name: str) -> str:
    """
    Validate and normalize medication name.
    Returns lowercased, stripped name.
    Raises MedicationValidationError if name not in formulary.
    """
    if not isinstance(name, str) or not name.strip():
        raise MedicationValidationError("Medication name must be a non-empty string")
    normalized = name.strip().lower()
    if normalized not in MAX_SINGLE_DOSE_MG:
        raise MedicationValidationError(
            f"Medication '{name}' not in formulary. "
            f"Supported: {sorted(MAX_SINGLE_DOSE_MG.keys())}"
        )
    return normalized


def validate_dose(medication: str, dose_mg: float) -> dict:
    """
    Validate dose for a given medication.
    Returns dict with medication, dose_mg, max_dose_mg, exceeds_max.
    Raises MedicationValidationError if dose is non-positive.
    """
    medication = validate_medication_name(medication)

    if not isinstance(dose_mg, (int, float)):
        raise MedicationValidationError(f"dose_mg must be numeric, got {type(dose_mg).__name__}")
    if dose_mg <= 0:
        raise MedicationValidationError(f"dose_mg must be positive, got {dose_mg}")

    max_dose = MAX_SINGLE_DOSE_MG[medication]
    exceeds = dose_mg > max_dose

    return {
        'medication': medication,
        'dose_mg': float(dose_mg),
        'max_dose_mg': max_dose,
        'exceeds_max': exceeds,
    }


def validate_route(route: str) -> str:
    """Validate administration route. Returns normalized lowercase route."""
    if not isinstance(route, str) or not route.strip():
        raise MedicationValidationError("Route must be a non-empty string")
    normalized = route.strip().lower()
    if normalized not in VALID_ROUTES:
        raise MedicationValidationError(
            f"Route '{route}' is not valid. Accepted: {sorted(VALID_ROUTES)}"
        )
    return normalized


def validate_frequency(frequency: str) -> str:
    """Validate dosing frequency. Returns normalized lowercase frequency."""
    if not isinstance(frequency, str) or not frequency.strip():
        raise MedicationValidationError("Frequency must be a non-empty string")
    normalized = frequency.strip().lower()
    if normalized not in VALID_FREQUENCIES:
        raise MedicationValidationError(
            f"Frequency '{frequency}' is not recognized. Accepted: {sorted(VALID_FREQUENCIES)}"
        )
    return normalized


def validate_medication_order(order: dict) -> dict:
    """
    Validate a complete medication order.
    Required fields: medication, dose_mg, route, frequency
    Returns validated order dict with normalized values.
    Raises MedicationValidationError if any field is invalid.
    """
    required = ('medication', 'dose_mg', 'route', 'frequency')
    errors = []

    for field in required:
        if field not in order:
            errors.append(f"Missing required field: {field}")

    if errors:
        raise MedicationValidationError("; ".join(errors))

    validated = {}
    try:
        dose_result = validate_dose(order['medication'], order['dose_mg'])
        validated.update(dose_result)
    except MedicationValidationError as e:
        errors.append(str(e))

    try:
        validated['route'] = validate_route(order['route'])
    except MedicationValidationError as e:
        errors.append(str(e))

    try:
        validated['frequency'] = validate_frequency(order['frequency'])
    except MedicationValidationError as e:
        errors.append(str(e))

    if errors:
        raise MedicationValidationError("; ".join(errors))

    return validated
PYEOF

# ============================================================
# tests/__init__.py
# ============================================================
touch "$PROJECT_DIR/tests/__init__.py"

# ============================================================
# tests/test_validator.py — INITIAL (low coverage, ~32%)
# Agent must add tests to this file to reach 75%+ coverage
# ============================================================
cat > "$PROJECT_DIR/tests/test_validator.py" << 'PYEOF'
"""
Tests for clinical_validator library.
Current coverage: ~32% (only happy-path cases covered).
Goal: achieve >= 75% line coverage by adding tests to this file.
"""
import pytest
from validator.demographics import (
    validate_mrn, validate_date_of_birth, validate_sex,
    validate_zip_code, validate_patient_record, DemographicsValidationError
)
from validator.labs import validate_lab_value, validate_lab_panel, LabValidationError
from validator.medications import (
    validate_medication_name, validate_dose, validate_route,
    validate_frequency, validate_medication_order, MedicationValidationError
)


# ===== DEMOGRAPHICS =====

class TestMRN:
    def test_valid_mrn(self):
        assert validate_mrn("ABC12345") == "ABC12345"

    def test_mrn_is_uppercased(self):
        assert validate_mrn("abc12345") == "ABC12345"


class TestDateOfBirth:
    def test_iso_format(self):
        dob = validate_date_of_birth("1985-06-15")
        assert dob.year == 1985 and dob.month == 6 and dob.day == 15


class TestSex:
    def test_male_abbreviation(self):
        assert validate_sex("M") == "M"

    def test_female_full(self):
        assert validate_sex("Female") == "F"


class TestZipCode:
    def test_five_digit(self):
        assert validate_zip_code("12345") == "12345"


# ===== LABS =====

class TestLabValue:
    def test_normal_wbc(self):
        result = validate_lab_value("WBC", 7.5, "10^3/uL")
        assert result['status'] == 'normal'
        assert result['test_code'] == 'WBC'

    def test_case_insensitive_test_code(self):
        result = validate_lab_value("wbc", 7.5, "10^3/uL")
        assert result['test_code'] == 'WBC'


class TestLabPanel:
    def test_single_result(self):
        panel = [{'test_code': 'HGB', 'value': 14.0, 'unit': 'g/dL'}]
        results = validate_lab_panel(panel)
        assert len(results) == 1
        assert results[0]['status'] == 'normal'


# ===== MEDICATIONS =====

class TestMedicationName:
    def test_valid_medication(self):
        assert validate_medication_name("acetaminophen") == "acetaminophen"

    def test_case_insensitive(self):
        assert validate_medication_name("Ibuprofen") == "ibuprofen"


class TestMedicationOrder:
    def test_valid_order(self):
        order = {
            'medication': 'acetaminophen',
            'dose_mg': 500.0,
            'route': 'oral',
            'frequency': 'tid'
        }
        result = validate_medication_order(order)
        assert result['medication'] == 'acetaminophen'
        assert result['exceeds_max'] is False
PYEOF

# Set ownership
chown -R ga:ga "$PROJECT_DIR"

# Install dependencies
echo "Installing Python dependencies..."
su - ga -c "pip3 install --quiet pytest pytest-cov 2>&1 | tail -3" || true

# PyCharm .idea files
mkdir -p "$PROJECT_DIR/.idea"
cat > "$PROJECT_DIR/.idea/misc.xml" << 'XML'
<?xml version="1.0" encoding="UTF-8"?>
<project version="4">
  <component name="ProjectRootManager" version="2" project-jdk-name="Python 3.11" project-jdk-type="Python SDK" />
</project>
XML

cat > "$PROJECT_DIR/.idea/modules.xml" << 'XML'
<?xml version="1.0" encoding="UTF-8"?>
<project version="4">
  <component name="ProjectModuleManager">
    <modules>
      <module fileurl="file://$PROJECT_DIR$/clinical_validator.iml" filepath="$PROJECT_DIR$/clinical_validator.iml" />
    </modules>
  </component>
</project>
XML

cat > "$PROJECT_DIR/.idea/clinical_validator.iml" << 'XML'
<?xml version="1.0" encoding="UTF-8"?>
<module type="PYTHON_MODULE" version="4">
  <component name="NewModuleRootManager">
    <content url="file://$MODULE_DIR$" />
    <orderEntry type="inheritedJdk" />
    <orderEntry type="sourceFolder" forTests="false" />
  </component>
</module>
XML

chown -R ga:ga "$PROJECT_DIR/.idea"

# Record start timestamp
date +%s > /tmp/${TASK_NAME}_start_ts

# Open in PyCharm
echo "Opening project in PyCharm..."
if type setup_pycharm_project &>/dev/null; then
    setup_pycharm_project "$PROJECT_DIR"
else
    su - ga -c "DISPLAY=:1 /opt/pycharm/bin/pycharm.sh '$PROJECT_DIR' >> /home/ga/pycharm.log 2>&1 &"
    sleep 15
fi

sleep 2
DISPLAY=:1 import -window root /tmp/${TASK_NAME}_start_screenshot.png 2>/dev/null || \
    DISPLAY=:1 scrot /tmp/${TASK_NAME}_start_screenshot.png 2>/dev/null || true

echo "=== Setup Complete ==="
