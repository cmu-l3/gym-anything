# Wrap Generated gRPC Client Task

**Difficulty**: 🟡 Medium  
**Skills**: Software design patterns, code generation workflows, Python class design  
**Duration**: 300 seconds  
**Steps**: ~40

## Objective

Create a wrapper class around auto-generated gRPC client code to add custom functionality (retry logic, validation) that persists across code regeneration cycles.

## Context

A junior developer previously added retry logic directly to the generated `user_service_pb2_grpc.py` file. Yesterday, the team regenerated proto files for a schema update, and all custom changes were lost. This caused a production incident when transient network failures weren't handled.

**The Problem**: Code in `generated/` directory is auto-generated and gets overwritten. Direct edits are lost.

**The Solution**: Create a wrapper class that extends/wraps the generated client, adding custom logic outside the generated files.

## Expected Implementation

You need to create `src/user_service_client.py` that:
1. Wraps or inherits from the generated `UserServiceStub` class
2. Adds retry logic (using loops with sleep, or tenacity library)
3. Adds input validation (e.g., check age >= 18 before calling CreateUser)
4. Implements logging for RPC calls
5. Includes documentation explaining the wrapper pattern

Then update `client_example.py` to use your wrapper instead of the generated client.

## Workflow

1. Read `generated/user_service_pb2_grpc.py` to understand the generated client
2. Create `src/user_service_client.py` with wrapper class
3. Implement retry logic (3 attempts with exponential backoff)
4. Implement validation (age must be >= 18)
5. Update `client_example.py` to import and use your wrapper
6. Add docstring/comments explaining why the wrapper exists
7. Save all files (Ctrl+S)

## Verification

Checks for:
1. Wrapper file created at `src/user_service_client.py`
2. Contains a class definition
3. References the generated client
4. Implements retry logic
5. Implements validation checks
6. Example file updated to use wrapper
7. Documentation present

**Pass Threshold**: 70% (5/7 criteria)