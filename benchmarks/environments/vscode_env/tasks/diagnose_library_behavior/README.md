# Diagnose Third-Party Library Behavior Task

**Difficulty**: 🟡 Medium  
**Skills**: Code investigation, third-party library debugging, configuration discovery  
**Duration**: 480 seconds (8 minutes)  
**Steps**: ~50

## Objective

Investigate why a third-party Python library (`datamorph`) is not using parallel processing despite documentation claiming it does. Read the library's source code to discover the configuration requirement, then create the necessary config file to enable parallel processing.

## Scenario

You're working on a data processing pipeline using the `datamorph` library. The `transform_batch()` function should process records in parallel, but it's running slowly - appearing to process one record at a time. The documentation is sparse and doesn't explain this behavior.

**Your goal**: Navigate into the library's source code, understand why parallel processing is disabled, and fix the configuration.

## Expected Workflow

1. Open the project in VSCode (`/home/ga/workspace/data_pipeline/`)
2. Examine `process.py` to understand the problem
3. Use "Go to Definition" (F12) on `transform_batch` to jump into library source
4. Read `datamorph/core.py` to see how parallel processing is controlled
5. Follow the code to `datamorph/config.py` to discover config file requirement
6. Discover that a `.datamorph.config` file is needed in project root
7. Create `/home/ga/workspace/data_pipeline/.datamorph.config` with proper JSON structure
8. Config must include: `{"parallel_enabled": true, "workers": 4}` (or similar)
9. Save the file
10. Verify that running the script shows parallel processing enabled

## Verification

Checks for:
1. Config file `.datamorph.config` exists in project root
2. File is valid JSON
3. Contains `"parallel_enabled": true`
4. Contains valid `"workers"` setting (positive integer)
5. Script execution output confirms parallel processing is enabled

**Pass Threshold**: 100% (all criteria must pass)

## Tips

- Use Ctrl+P to quickly open files
- F12 (Go to Definition) works on imported functions
- Read the `load_config()` function carefully to understand what it's looking for
- The config file should be in the project root, not in the library directory