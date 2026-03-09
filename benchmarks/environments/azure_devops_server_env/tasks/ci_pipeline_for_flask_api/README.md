# Task: ci_pipeline_for_flask_api

## Overview

**Difficulty**: very_hard
**Occupation**: DevOps Engineer / Computer Systems Engineer/Architect
**Domain**: Continuous Integration, CI/CD Pipeline Setup
**Azure DevOps Feature Area**: Pipelines (classic or YAML pipeline creation)

## Domain Context

DevOps Engineers and Systems Engineers/Architects use Azure DevOps Pipelines to automate testing and deployment. Creating a CI pipeline for a Python/Flask application is a core real-world DevOps task: the engineer must understand the project structure, write appropriate YAML, configure triggers, and integrate the pipeline with the repository.

## Scenario

The TailwindTraders inventory API has been developed without any CI infrastructure. Bugs like the concurrent stock deduction race condition and SQL injection vulnerability have been reaching the codebase because no automated tests run on commits. The DevOps engineer must create a proper CI pipeline.

## What the Agent Must Discover

- Navigate to the Pipelines section (not pre-opened there)
- Choose the correct repository (TailwindTraders)
- Understand the project structure (Python/Flask, requirements.txt, tests/ directory)
- Write or configure YAML with correct Python version, dependency installation, and test execution
- Configure triggers for both CI (main) and PR validation

## Pre-Task State (set by setup_task.ps1)

- All existing pipeline definitions are deleted (clean slate)
- No `azure-pipelines.yml` exists in the repository
- The Flask API code is present with `requirements.txt` and `tests/test_app.py`

## Expected Pipeline YAML Structure

A correct pipeline would look like (or equivalent):
```yaml
trigger:
  branches:
    include:
      - main

pr:
  branches:
    include:
      - main

pool:
  vmImage: 'ubuntu-latest'

steps:
- task: UsePythonVersion@0
  inputs:
    versionSpec: '3.11'

- script: pip install -r requirements.txt
  displayName: 'Install dependencies'

- script: pytest tests/ -v
  displayName: 'Run tests'
```

The agent doesn't need to write exactly this — any YAML that contains Python setup, dependency installation, and pytest execution will pass.

## Success Criteria

| Criterion | Points | Verification |
|-----------|--------|--------------|
| At least 1 pipeline definition exists | 25 | REST: `/build/definitions` count > 0 |
| Pipeline has CI trigger (includes 'main') | 20 | Pipeline YAML or definition contains 'main' trigger |
| Pipeline YAML contains Python/dependency install | 30 | YAML content contains 'requirements' or 'pip' |
| Pipeline YAML contains test execution (pytest) | 25 | YAML content contains 'pytest' or 'test' |

**Pass threshold**: 70 / 100

## Verification Strategy

`export_result.ps1`:
1. Gets all pipeline definitions via REST
2. For each pipeline, retrieves the YAML content (if file-based) or inline YAML
3. Checks YAML content for required keywords
4. Writes result JSON

## Notes

- Azure DevOps Server 2022 supports both classic (GUI-configured) and YAML pipelines
- If the agent creates a classic pipeline, the verifier checks the task/step types for Python-related tasks
- The pipeline doesn't need to actually run successfully (just be defined correctly)
