# Evolve API Schema Task

**Difficulty**: 🟡 Medium  
**Skills**: Data modeling, API design, backward compatibility, multi-file editing, testing  
**Duration**: 480 seconds  
**Steps**: ~50

## Objective

Add a new `email_verified` boolean field to a FastAPI user endpoint while maintaining backward compatibility with existing clients and data.

## Scenario

You're maintaining a production API that's been live for 6 months with thousands of active clients. The product team wants to add an `email_verified` field to the user response, but breaking changes would require coordinated mobile app releases (expensive and slow).

**Current Response**: