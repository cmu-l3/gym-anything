# increase_test_coverage

## Overview

**Occupation**: Software Quality Assurance Analysts and Testers
**Industry**: Hospitals (Clinical Data Integration)
**Difficulty**: Hard

A Python clinical data validation library (`clinical_validator`) is used by a hospital data integration team to validate patient records before loading into the EHR system. The library is correct and fully functional but has very low test coverage (~32%). The QA engineer must write additional tests to reach at least 75% line coverage.

The agent must read the source code (demographics, lab results, medications validators), understand all validation logic, and write tests that cover error paths, boundary values, and edge cases the existing suite misses.

---

## Goal

Increase line coverage of the `validator/` package from ~32% to ≥75% by adding tests to `tests/test_validator.py`. All existing tests must continue to pass.

Run with: `python -m pytest tests/ --cov=validator --cov-report=term-missing -v`

---

## Starting State

The project is at `/home/ga/PycharmProjects/clinical_validator/` and contains:

```
clinical_validator/
├── validator/
│   ├── demographics.py   # validate_mrn, validate_date_of_birth, validate_sex,
│   │                     # validate_zip_code, validate_patient_record
│   ├── labs.py           # validate_lab_value, validate_lab_panel
│   └── medications.py    # validate_medication_name, validate_dose,
│                         # validate_route, validate_frequency, validate_medication_order
├── tests/
│   └── test_validator.py # 10 tests covering only happy paths (~32% coverage)
└── requirements.txt
```

**Modules and key uncovered paths**:

| Module | Covered | Uncovered |
|--------|---------|-----------|
| `demographics.py` | valid MRN, ISO date, M/F sex, 5-digit ZIP | non-string inputs, empty strings, invalid lengths, future DOB, 130+ year DOB, slash date format, DD-Mon-YYYY format, sex variants, ZIP+4, multi-field errors |
| `labs.py` | normal WBC, case-insensitive code | negative values, unknown test/unit, non-string code, non-numeric value, critical_low/high/low/high statuses, empty panel, non-list panel, missing dict keys |
| `medications.py` | valid acetaminophen/ibuprofen name, valid order | unknown medication, non-string name, zero/negative dose, exceeds_max=True, invalid route, invalid frequency, missing required fields, multi-error order |

---

## Verification Strategy

**Coverage tier 1 (20 pts)**: Total coverage ≥ 50%
**Coverage tier 2 (20 pts)**: Total coverage ≥ 65%
**Coverage tier 3 (25 pts)**: Total coverage ≥ 75% (target)
**No regression (20 pts)**: All tests pass (pytest exit code 0)
**Per-module bonus (5 pts each × 3)**: `demographics`, `labs`, `medications` each ≥ 70% individually

**Pass threshold**: 60/100

---

## Schema Reference

```python
# demographics.py
validate_mrn(mrn: str) -> str                 # raises DemographicsValidationError
validate_date_of_birth(dob: str) -> date      # accepts YYYY-MM-DD, MM/DD/YYYY, DD-Mon-YYYY
validate_sex(sex: str) -> str                 # returns 'M' or 'F'
validate_zip_code(zip_code: str) -> str       # 5-digit or ZIP+4
validate_patient_record(record: dict) -> dict # required: mrn, date_of_birth, sex; optional: zip_code

# labs.py
LAB_REFERENCE_RANGES = {("WBC","10^3/uL"), ("HGB","g/dL"), ("PLT","10^3/uL"),
                         ("NA","mEq/L"), ("K","mEq/L"), ("CR","mg/dL"),
                         ("GLU","mg/dL"), ("TROP","ng/mL")}
validate_lab_value(test_code, value, unit) -> dict  # status: normal/low/high/critical_low/critical_high
validate_lab_panel(results: list) -> list

# medications.py
MAX_SINGLE_DOSE_MG = {acetaminophen:1000, ibuprofen:800, amoxicillin:875,
                       metformin:1000, lisinopril:40, atorvastatin:80,
                       metoprolol:200, furosemide:600, morphine:30, warfarin:15}
VALID_ROUTES = {"oral","iv","im","subcutaneous","topical","rectal","inhalation"}
VALID_FREQUENCIES = {"daily","bid","tid","qid","q4h","q6h","q8h","q12h","prn","once"}
validate_medication_order(order: dict) -> dict  # required: medication, dose_mg, route, frequency
```

---

## Edge Cases

- The agent must NOT modify any file in `validator/` (library source is correct)
- All new tests must be added to the existing `tests/test_validator.py`
- The verifier uses `pytest-cov` coverage measurement — only code that executes during tests counts
- Writing tests for `validate_patient_record` with multiple simultaneous field errors requires understanding how errors are aggregated
