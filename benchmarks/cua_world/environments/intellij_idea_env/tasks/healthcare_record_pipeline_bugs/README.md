# Task: healthcare_record_pipeline_bugs

**Difficulty:** Very Hard
**Domain:** Healthcare IT
**Environment:** IntelliJ IDEA (intellij_idea_env)

## Overview

A patient record pipeline for a hospital information system has failing tests. The pipeline ingests patient records, maps them to ICD-10 diagnostic codes, and stores them in a registry. Three implementation files have bugs that cause incorrect behaviour and test failures.

## What the agent must do

1. Open the `healthcare-pipeline` project in IntelliJ IDEA
2. Run `PatientRegistryTest` and read the failure messages
3. Identify the bugs across three implementation files
4. Fix **all three bugs** without modifying the test file

## Bugs (hidden from agent)

| # | File | Bug | Test that catches it |
|---|------|-----|---------------------|
| 1 | `Patient.java` | `equals()/hashCode()` only compare `fullName`, not `dateOfBirth` — two patients with the same name are treated as identical | `testPatientsWithSameNameButDifferentDOBAreDistinct` |
| 2 | `PatientRegistry.java` | `addRecord()` catches `IllegalArgumentException` but never re-throws it — validation failures silently disappear | `testAddingInvalidRecordThrowsException` |
| 3 | `DiagnosticCoder.java` | `isValidCode(null)` throws `NullPointerException` instead of returning `false` | `testNullDiagnosticCodeReturnsFalseNotNPE` |

## Scoring

| Criterion | Points |
|-----------|--------|
| Patient.equals()/hashCode() includes DOB (Bug 1) | 25 |
| PatientRegistry re-throws validation exception (Bug 2) | 30 |
| DiagnosticCoder null-safe (Bug 3) | 25 |
| All 6 tests pass | 10 |
| Test file unmodified | 5 |
| VLM bonus | 5 |
| **Total** | **100** |

**Pass threshold:** ≥ 70 points AND all 6 tests pass
