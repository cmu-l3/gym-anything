# Transform CSV to JSON Task

**Difficulty**: 🟡 Medium  
**Skills**: Data transformation, scripting, file I/O, data validation  
**Duration**: 240 seconds  
**Steps**: ~60

## Objective

Transform a flat CSV file containing employee department assignments into a nested JSON structure required by a new API service. This simulates a real-world data migration scenario.

## Background

You're migrating from a legacy HR system to a new access control microservice. The legacy system exports employee-department-role data as a flat CSV (one row per assignment). The new service requires JSON with nested structure where departments contain employees, and employees contain arrays of roles.

## Input Data

**File**: `employee_access.csv`  
**Format**: Flat CSV with columns: `department`, `employee_id`, `employee_name`, `role`

**Edge Cases to Handle**:
- Employees may have multiple roles (multiple CSV rows with same employee_id)
- Department names may contain commas (properly quoted in CSV)
- Some fields may have extra whitespace that needs trimming
- Total of 15 rows representing various department-employee-role combinations

## Required Output

**File**: `access_control.json`  
**Format**: Nested JSON structure
