# Migrate Order ID Type (`migrate_order_id_type@1`)

## Overview
This task evaluates the agent's ability to perform a deep refactoring operation—changing the data type of a core domain field—using IntelliJ IDEA's "Type Migration" feature. The agent must convert an `int` field to `long` in a Java project, ensuring that the change propagates correctly through getters, setters, method parameters, and local variables across multiple classes, without breaking the build.

## Rationale
**Why this task is valuable:**
- **Tests Advanced Refactoring**: "Type Migration" is a specific, powerful IDE feature distinct from simple finding/replacing.
- **Evaluates Consistency**: The change affects the entire call stack (Entity → Repository → Service → Controller).
- **Validates Build Integrity**: The agent must ensure the project remains compilable after the structural change.
- **Real-world Scenario**: ID field exhaustion (integer overflow) is a classic scaling problem that requires this exact maintenance task.

**Real-world Context:** An e-commerce platform's `order-service` was originally designed with `int` for order IDs (max ~2.1 billion). The business is growing, and they are approaching the integer limit. A developer needs to migrate the `id` field to `long` to support future growth.

## Task Description

**Goal:** Refactor the `order-service` project to change the `id` field in the `Order` class from `int` to `long`.

**Starting State:**
- IntelliJ IDEA is open with the `order-service` Maven project loaded.
- The project is fully functional, compiles, and passes tests.
- The `com.ecommerce.model.Order` class has a field `private int id;`.
- Multiple other classes (`OrderRepository`, `OrderService`, `OrderController`) reference this ID as an `int`.

**Expected Actions:**
1. Open `src/main/java/com/ecommerce/model/Order.java`.
2. Locate the `id` field.
3. Use IntelliJ's **Type Migration** refactoring tool (Refactor > Type Migration) to change the type from `int` to `long`.
4. Review the proposed changes to ensure they cascade to dependent methods (e.g., `findById(int)` becomes `findById(long)`).
5. Apply the refactoring.
6. Verify the project still compiles and tests pass (run `mvn clean test` or use IDE tools).

**Final State:**
- The `Order.id` field is of type `long`.
- All referencing methods (getters, setters, repository lookups) use `long`.
- The project compiles successfully.
- All unit tests pass.

## Verification Strategy

### Primary Verification: Build & Test Execution
The verifier runs the project's build and test suite inside the environment.
- `mvn compile`: Must succeed (Exit Code 0).
- `mvn test`: Must succeed (Exit Code 0).
- If the agent only changed the field definition but not the usages, compilation will fail.

### Secondary Verification: Static Analysis
The verifier parses the `Order.java` source file to confirm the specific field type change.
- Check that `private long id;` (or `Long`) is present.
- Check that `getId()` returns `long`.

### Scoring System
| Criterion | Points | Description |
|-----------|--------|-------------|
| **Compile Success** | 40 | `mvn compile` succeeds (implies consistent types) |
| **Test Success** | 30 | `mvn test` passes (implies logic integrity) |
| **Field Type Converted** | 20 | `Order.java` contains `long id` |
| **Method Signature Converted** | 10 | `OrderRepository` uses `findById(long)` |
| **Total** | **100** | |

**Pass Threshold:** 70 points (Must compile and have correct type).