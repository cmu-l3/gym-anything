# Refine Regex Validator Task

**Difficulty**: 🟡 Medium  
**Skills**: Regex, Testing, Iterative Development, Documentation  
**Duration**: 480 seconds (8 minutes)  
**Steps**: ~40

## Objective

You're implementing email validation for a signup form. A partially-working regex pattern exists in `validator.py`, but it fails on several edge cases. Your job is to:

1. Create a test runner that validates the regex against all test cases in `test_cases.txt`
2. Iteratively refine the regex pattern until all 12 test cases pass
3. Document the regex with explanatory comments

## Context

Product gave you a specification with 12 email examples (8 valid, 4 invalid). Your current regex is too restrictive—it rejects valid emails like `john.doe@example.com` and `alice+spam@test-domain.org`.

The form launches tomorrow, and QA found that legitimate users are being blocked. You need systematic testing to fix this.

## Files Provided

- **`validator.py`**: Contains the broken `EMAIL_PATTERN` regex
- **`test_cases.txt`**: 12 test cases with expected results
- **`README.md`**: This file

## Expected Workflow

1. **Create a test runner script** (e.g., `test_validator.py`):
   - Read test cases from `test_cases.txt`
   - Parse each line: `email | expected_result`
   - Apply the regex from `validator.py`
   - Report pass/fail for each test

2. **Run tests** to see which cases fail

3. **Iteratively fix the regex**:
   - Modify `EMAIL_PATTERN` in `validator.py`
   - Re-run tests
   - Repeat until all 12 pass

4. **Document the regex** with comments explaining:
   - What each part matches
   - Edge cases handled
   - Why certain patterns are allowed/disallowed

## Test Cases Summary

**Valid emails (should accept):**
- `user@example.com`
- `john.doe@company.co.uk` (dots in username, multi-part TLD)
- `alice+spam@test-domain.org` (plus addressing, hyphen in domain)
- `user123@subdomain.example.com` (numbers, subdomains)
- `first_last@example.io` (underscores)
- `admin@test.museum` (uncommon TLD)
- `user@123.456.789.012` (numeric domains/IPs)
- `a@b.co` (minimal valid email)

**Invalid emails (should reject):**
- `@example.com` (no username)
- `user@.com` (no domain name)
- `user name@example.com` (space in username)
- `user@example` (no TLD)

## Verification

The verifier checks:
1. ✅ Test runner script exists (`test_*.py` or `run_*.py`)
2. ✅ Regex pattern was modified from initial version
3. ✅ Pattern has documentation comments (at least 2 lines)
4. ✅ All 12 tests pass when test runner executes

**Pass Threshold**: All 4 criteria must be met