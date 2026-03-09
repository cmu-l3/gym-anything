# Adapt Example Code Task

**Difficulty**: 🟡 Medium  
**Skills**: Code comprehension, refactoring, contextual adaptation, integration  
**Duration**: 300 seconds  
**Steps**: ~40

## Objective

Adapt a FastAPI file validation example from documentation into a CLI-based file validator that integrates with an existing codebase.

## Real-World Scenario

You're implementing a file validation system for your data processing pipeline. You found a perfect example in the FastAPI documentation showing how to validate file uploads with custom validators, but it's written for a web API context with generic names. You need to adapt it to work in your CLI-based data pipeline with your team's naming conventions and integrate it with your existing `DataProcessor` class.

## Task Context

- **Example code location**: `docs/example_validator.py` (FastAPI-based file upload validator)
- **Target file**: `pipeline/validator.py` (CLI-based file validator - currently incomplete)
- **Validation checks to preserve**: File size, MIME type, file extension validation
- **Adaptation required**: Remove FastAPI dependencies, work with Path objects instead of UploadFile, match codebase naming conventions

## Expected Workflow

1. Open and examine `docs/example_validator.py` to understand the validation logic
2. Open `pipeline/validator.py` to see the existing class structure
3. Adapt the validation logic from the example into the `FileValidator` class:
   - Implement the `validate()` method with the three validation checks
   - Implement the `get_validation_errors()` method for error tracking
   - Convert from `UploadFile` to `Path` objects
   - Remove FastAPI-specific code (no `@app` decorators, no `HTTPException`)
   - Use `self.errors` or similar for storing validation errors
4. Ensure code matches the existing style (parameter named `filepath`, not `upload_file`)
5. Save the modified file

## Verification

Checks for:
1. FileValidator class exists and is modified
2. validate() method has substantial implementation (not just TODO/stub)
3. At least 2 of 3 validation checks implemented (size, MIME, extension)
4. get_validation_errors() returns stored errors
5. Error tracking mechanism exists (self.errors or similar)
6. Code adapted from FastAPI context (no FastAPI imports, uses Path)

**Pass Threshold**: 70% (minimum viable adaptation)