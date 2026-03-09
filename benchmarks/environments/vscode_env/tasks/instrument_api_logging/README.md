# VSCode Task Specification: `instrument_api_logging@1`

## Overview

This task challenges an agent to add comprehensive structured logging to a Python Flask API application to diagnose intermittent production errors. The agent must configure logging infrastructure, implement request tracking middleware, instrument multiple endpoints with structured logs, add performance timing decorators, and ensure no sensitive data is logged.

## Scenario

**Context:** You're an on-call engineer at MobileFin, a fintech startup. Your mobile app backend API (Python/Flask) has been experiencing intermittent 500 errors affecting ~2% of production requests. The current logging is sparse and inconsistent—some endpoints use `print()`, others have no logging at all.

**Your Mission:** Instrument the Flask API with proper logging infrastructure so the next error occurrence provides actionable debugging information.

## Task Requirements

You must add the following to the Flask application at `/home/ga/workspace/api_logging/`:

1. **Logging Configuration:**
   - Configure Python's logging module with appropriate formatters and handlers
   - Support JSON formatting for production logs
   - Set appropriate log levels (INFO or DEBUG)

2. **Request ID Middleware:**
   - Implement `@app.before_request` hook to generate unique request IDs (UUID)
   - Store request ID in Flask's `g` context object
   - Add `X-Request-ID` header to responses via `@app.after_request`

3. **Endpoint Instrumentation:**
   - Add logging to at least 2 out of 3 critical endpoints: `/api/payment`, `/api/balance`, `/api/transaction`
   - Log entry points with relevant parameters
   - Log exit points or errors
   - Include request_id in log context

4. **Performance Timing:**
   - Create a timing decorator (e.g., `@timed`) that measures function execution duration
   - Apply decorator to at least one endpoint
   - Log execution time in milliseconds or seconds

5. **Security - Sensitive Data Protection:**
   - Ensure passwords, tokens, credit_card numbers, and api_keys are NOT logged in plain text
   - Implement sanitization or use redaction markers like `[REDACTED]`

6. **Code Validity:**
   - All Python files must be syntactically correct
   - Application should remain functional

## Expected Workflow

1. Open the workspace at `/home/ga/workspace/api_logging/`
2. Examine the existing `app.py` with minimal logging
3. Add logging configuration (in `app.py` or separate `logging_config.py`)
4. Implement request ID middleware using `@app.before_request` and `@app.after_request`
5. Create a timing decorator function
6. Instrument the three API endpoints with logging calls
7. Apply the timing decorator to at least one endpoint
8. Add sensitive data filtering/sanitization
9. Save all changes (Ctrl+S)
10. Optionally test by running the Flask app in integrated terminal

## Verification Criteria

The verifier checks for:

1. **Logging Configuration (25 points):** Proper logging setup with formatters and handlers
2. **Request ID Middleware (20 points):** UUID generation and storage in `before_request` hook
3. **Endpoint Instrumentation (25 points):** Logging added to at least 2 out of 3 endpoints
4. **Timing Mechanism (15 points):** Decorator or timing code exists and is applied
5. **Security (10 points):** No sensitive fields logged, or sanitization function exists
6. **Code Validity (5 points):** All files parse without syntax errors

**Pass Threshold:** 60% (requires at least 60 points)

## Files to Modify

- `app.py` - Main Flask application (modify to add logging, middleware, decorators)
- `logging_config.py` (optional) - Create if you want separate logging configuration

## Important Notes

- The task description provides all necessary information to complete the task
- You do NOT need to actually run the application (though you can for testing)
- Focus on adding the logging infrastructure correctly
- Remember to save all files after modifications