# Adapt Generated API Client Task

**Difficulty**: 🟡 Medium  
**Skills**: TypeScript, API client adaptation, error navigation, code refactoring  
**Duration**: 300 seconds  
**Steps**: ~30

## Objective

Adapt application code to breaking changes in an auto-generated API client. The backend team updated their OpenAPI specification and regenerated the TypeScript client, introducing breaking changes where the `User` type structure changed from flat fields to nested objects.

## Scenario

You arrive Monday morning to find the TypeScript build failing. Someone regenerated the API client over the weekend, and the backend's `User` type now has a nested `profile` object instead of flat `email` and `name` fields. You must update all application code that uses this API client.

## Breaking Change Details

**Old structure:**