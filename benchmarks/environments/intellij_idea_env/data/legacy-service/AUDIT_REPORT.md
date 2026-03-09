# Q4 Security & Code-Quality Audit — Legacy Service Layer

**Audit Date:** 2024-11-28
**Auditor:** InfoSec & Engineering Enablement Team
**Component:** `com.legacy` (legacy-service)
**Risk Level:** HIGH

---

## Executive Summary

A routine code-quality audit of the legacy enterprise service layer has identified **four exception-handling violations** that create data-integrity risks, mask bugs, and prevent effective incident response. All four findings must be remediated before the next production release.

---

## Findings

### Finding 1 — `RecordParser.parseAmountCents()`: NumberFormatException Silently Swallowed

**File:** `src/main/java/com/legacy/RecordParser.java`
**Risk:** DATA INTEGRITY — HIGH

The method catches `NumberFormatException` and returns `0L` for any input that cannot be parsed as a monetary amount. Downstream callers receive a zero balance for what is actually corrupt upstream data, producing silent financial miscalculations that do not appear in logs or alerts.

**Required fix:** Remove the `catch (NumberFormatException)` block (or re-throw as `IllegalArgumentException`) so the caller receives a clear signal when input is malformed.

---

### Finding 2 — `EventLogger.log()`: Broad `catch (Exception)` Swallows NullPointerException

**File:** `src/main/java/com/legacy/EventLogger.java`
**Risk:** AUDIT TRAIL INTEGRITY — HIGH

The `log()` method wraps its body in `catch (Exception e)`, which suppresses a `NullPointerException` thrown when a caller passes a `null` event type. The audit entry is silently dropped, creating an invisible gap in the audit trail. The calling code receives no indication that logging failed.

**Required fix:** Remove the broad `try/catch` block. Null arguments should propagate as `NullPointerException` so callers discover their bugs immediately.

---

### Finding 3 — `ConfigLoader.load()`: IOException Swallowed; Resource Leak

**File:** `src/main/java/com/legacy/ConfigLoader.java`
**Risk:** OPERATIONAL — MEDIUM-HIGH (two sub-issues)

**Sub-issue A:** Any `IOException` (file not found, permission denied) is caught and suppressed; the method returns an empty `Properties` object. Services silently start with all configuration defaults, hiding deployment errors.

**Sub-issue B:** The `FileInputStream` opened by `load()` is never closed. If `props.load(is)` throws a runtime exception, the file descriptor leaks. This will exhaust OS file-descriptor limits under load.

**Required fix:** (1) Declare `load()` to `throws IOException` and remove the catch block. (2) Wrap the stream in try-with-resources to guarantee closure.

---

### Finding 4 — `BatchProcessor.processAmounts()`: Corrupt Records Silently Skipped

**File:** `src/main/java/com/legacy/BatchProcessor.java`
**Risk:** DATA INTEGRITY — HIGH

The `processAmounts()` method catches `Exception` around each record parse call and silently skips any record that raises an error. When combined with the `RecordParser` bug (Finding 1), corrupt records produce a 0 rather than an exception, and the accumulator is inflated by ghost zeroes. After fixing Finding 1, `BatchProcessor` must be fixed to propagate (not swallow) the exceptions that `RecordParser` will then throw.

**Required fix:** Remove the `catch (Exception)` block so that `IllegalArgumentException` from `RecordParser.parseAmountCents()` propagates to the batch job orchestrator, which can halt processing and alert the operator.

---

## Remediation Checklist

- [ ] `RecordParser.parseAmountCents()` throws `IllegalArgumentException` for invalid input
- [ ] `EventLogger.log()` propagates `NullPointerException` for null eventType
- [ ] `ConfigLoader.load()` declared `throws IOException`; uses try-with-resources
- [ ] `BatchProcessor.processAmounts()` propagates parse errors to caller
- [ ] All unit tests in `ExceptionHandlingTest` pass after remediation

---

*This report must be attached to the remediation PR for compliance tracking.*
