# Knowledge Base Migration

## Occupation Context
**Software Developer / Tech Lead** (SOC importance: 90.0)
Organizing scattered technical knowledge from general chat channels into structured knowledge base channels is a common team lead responsibility.

## Task Overview
The `#engineering-chat` channel contains a mix of casual conversation and important technical content (ADRs, API docs, architecture notes). The agent must identify the technical messages, create three dedicated knowledge base channels, migrate content appropriately, and organize it with pins and invitations.

## Starting State
- Rocket.Chat is running at `http://localhost:3000`
- `#engineering-chat` exists with 10 seeded messages:
  - Casual: lunch plans, game night, CI build broken, sprint retro, PR review, wifi password
  - **ADR-001**: Microservices migration decision (monolith decomposition, database-per-service)
  - **REST API v2**: Endpoint documentation (auth, users, orders with methods/responses)
  - **Event-Driven Architecture**: Kafka, event sourcing, CQRS, saga patterns
  - **ADR-002**: API versioning strategy (URL path versioning, deprecation policy)
- Users created: `junior.dev`, `senior.dev`, `tech.architect`
- No kb-* channels exist

## Goal / End State
1. Three KB channels: `kb-architecture`, `kb-api-docs`, `kb-decisions` with appropriate topics
2. ADR content (microservices decision, API versioning) migrated to `kb-decisions`
3. API endpoint docs migrated to `kb-api-docs`
4. Event-driven architecture content migrated to `kb-architecture`
5. At least one message pinned in each KB channel
6. All 3 team members invited to all 3 KB channels
7. Index message in `#engineering-chat` listing the new KB channels
8. DM to `tech.architect` asking for content review

## Verification Strategy (9 criteria, 100 points, pass >= 70)

| ID | Points | Criterion |
|----|--------|-----------|
| C1 | 9 | All 3 KB channels created (3 pts each) |
| C2 | 9 | Topics set appropriately (architecture/API/decisions keywords) |
| C3 | 15 | ADR/microservices content in kb-decisions |
| C4 | 15 | API endpoint docs in kb-api-docs |
| C5 | 15 | Event-driven architecture in kb-architecture |
| C6 | 9 | Pinned message in each KB channel (3 pts each) |
| C7 | 10 | All 3 team members in all 3 channels (9 invites total) |
| C8 | 9 | Index message in engineering-chat mentioning all 3 KB channels |
| C9 | 9 | DM to tech.architect about reviewing content |

### Do-nothing gate
If no KB channels created, score = 0.

### Anti-gaming
- Content verification checks for domain-specific keywords (microservice/monolith, endpoint/REST, event/kafka/CQRS)
- Partial scoring: content quality matters (just having "api" isn't enough for full points)
- Index message must reference all 3 channel names
- DM checked for review/accuracy/knowledge base keywords

## Features Exercised
Read/identify content, create channels, set topics, post messages (content migration), pin messages, invite members, send DM (7 distinct features with content discovery/classification unique to this task)

## Data Sources
- ADR format follows real Architecture Decision Record templates (Michael Nygard's ADR format)
- REST API documentation follows real OpenAPI/Swagger conventions
- Event-driven architecture content follows real Apache Kafka patterns
