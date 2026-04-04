# VSCode Error Handling Task (`harden_error_handling@1`)

**Difficulty**: 🟡 Medium  
**Skills**: Exception handling, defensive programming, logging, Python error recovery  
**Duration**: 240 seconds  
**Steps**: ~30

## Overview

Add comprehensive error handling to a fragile Python script that crashes when external services fail. Transform brittle prototype code into production-ready software by wrapping risky operations in try-except blocks with specific exception types, adding meaningful error messages, and implementing graceful degradation.

## Objective

Modify `/home/ga/workspace/data_pipeline/fetch_data.py` to add robust error handling for:
- **Network operations** (API calls with requests library)
- **File operations** (reading/writing files)
- **JSON parsing** (handling malformed data)
- **Dictionary access** (avoiding KeyError)

## Expected Workflow

1. Open `fetch_data.py` in VSCode
2. Identify vulnerable operations (API calls, file I/O, JSON parsing)
3. Wrap each risky operation in try-except blocks with **specific** exception types
4. Add `import logging` and configure logger
5. Replace print statements with `logging.info/warning/error`
6. Add meaningful error messages with context (URLs, file paths)
7. Use defensive patterns like `dict.get()` instead of `dict['key']`
8. Ensure script can handle partial failures gracefully
9. Save the file (Ctrl+S)

## Verification

Verifier performs multi-layered analysis:

### Static Analysis (AST Parsing)
- ✅ Multiple try-except blocks (at least 3)
- ✅ Specific exception types used (not bare `except:`)
- ✅ Required exceptions: `requests.RequestException`, `FileNotFoundError`, `json.JSONDecodeError`
- ✅ Logging framework imported and used
- ✅ Error messages contain context information

### Code Quality
- ✅ No bare `except:` blocks (anti-pattern)
- ✅ Defensive dictionary access with `.get()`
- ✅ Informative error messages (not empty handlers)

### Scoring Criteria
- **25 pts**: Multiple try-except blocks covering different operations
- **25 pts**: Specific exception types (RequestException, FileNotFoundError, JSONDecodeError, etc.)
- **20 pts**: Logging framework properly used
- **10 pts**: Defensive programming patterns
- **20 pts**: Meaningful error messages with context
- **-10 pts penalty**: Bare except clauses

**Pass Threshold**: 75% (requires comprehensive error handling with specific exceptions and logging)

## Skills Demonstrated

- Python exception hierarchy knowledge
- Defensive programming techniques
- Production-readiness mindset
- Error message design for debugging
- Graceful degradation strategies
- Logging best practices

## Notes

- Avoid catch-all `except:` blocks - use specific exception types
- Include context in error messages (which URL failed, which file is missing)
- Use `logging.error()` for errors, `logging.warning()` for degraded operation
- Consider whether to fail fast or continue with partial data
- Test by thinking about what could go wrong (network down, file missing, malformed JSON)