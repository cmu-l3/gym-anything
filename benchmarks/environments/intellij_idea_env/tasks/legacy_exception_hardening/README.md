# Task: legacy_exception_hardening

**Difficulty:** Very Hard
**Domain:** Enterprise Software / Banking
**Environment:** IntelliJ IDEA (intellij_idea_env)

## Overview

A legacy enterprise service layer has been flagged in a security and code-quality audit. The audit report (`AUDIT_REPORT.md`, in the project root) identifies **four exception-handling violations** that create data-integrity risks and prevent effective debugging. The corresponding test class `ExceptionHandlingTest` documents the expected correct behaviour.

## What the agent must do

1. Open the `legacy-service` project in IntelliJ IDEA
2. Read `AUDIT_REPORT.md` for context on each finding
3. Run `ExceptionHandlingTest` to see which tests currently fail
4. Fix all four violations in the implementation files
5. Ensure all 9 tests pass without modifying the test file

## Bugs (hidden from agent)

| # | File | Bug | Test |
|---|------|-----|------|
| 1 | `RecordParser.java` | `parseAmountCents()` catches `NumberFormatException` and returns `0L` — caller cannot detect corrupt input | `testParseAmountThrowsOnGarbageInput` |
| 2 | `EventLogger.java` | `log()` wraps body in `catch (Exception e)` — NPE from `null` eventType silently swallowed | `testEventLoggerThrowsOnNullEventType` |
| 3 | `ConfigLoader.java` | `load()` catches `IOException` (swallows missing-file error) and does not close the stream | `testConfigLoaderThrowsOnMissingFile` |
| 4 | `BatchProcessor.java` | `processAmounts()` catches `Exception` per record — corrupt records silently dropped | `testBatchProcessorPropagatesParseErrors` |

## Scoring

| Criterion | Points |
|-----------|--------|
| RecordParser NFE propagates (Bug 1) | 20 |
| EventLogger broad catch removed (Bug 2) | 25 |
| ConfigLoader throws IOException + try-with-resources (Bug 3) | 25 |
| BatchProcessor parse errors propagate (Bug 4) | 20 |
| All 9 tests pass | 5 |
| Test file unmodified | 5 |
| **Total** | **100** |

**Pass threshold:** ≥ 70 points AND all 9 tests pass
