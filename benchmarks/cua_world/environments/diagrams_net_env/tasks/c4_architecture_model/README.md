# Task: c4_architecture_model

**ID**: c4_architecture_model@1
**Difficulty**: very_hard
**Occupation**: Computer Systems Engineers/Architects ($3.09B GDP) + Computer Systems Analysts ($2.50B GDP)
**Timeout**: 1200 seconds | **Max Steps**: 120

## Domain Context

The C4 model (Simon Brown, 2018) is the industry-standard methodology for software architecture documentation, used by systems architects at companies ranging from startups to Fortune 500 enterprises. It provides four levels of abstraction (Context, Container, Component, Code). Levels 1 and 2 are the most commonly produced deliverables. Creating a correct C4 model requires understanding architectural decomposition, C4 notation conventions (element types, colors, relationship labeling), and the ability to read a system specification and translate it into appropriate diagram abstractions.

## Data Source

**Real open-source reference application**: Microsoft eShopOnContainers
**Source**: https://github.com/dotnet-architecture/eShopOnContainers
**Reference**: "*.NET Microservices: Architecture for Containerized .NET Applications*", Microsoft Corp. (2022)
This is Microsoft's official reference implementation for cloud-native .NET microservices on Kubernetes, widely used in industry as an architectural reference.

## Task Goal

Create a complete C4 model for the eShopOnContainers reference application from the system specification in `~/Desktop/system_spec.txt`. The diagram must be saved at `~/Diagrams/ecommerce_c4_model.drawio` with exactly three pages: (1) Level 1 System Context, (2) Level 2 Container Diagram, and (3) a Legend/notation page. Apply C4 color conventions and label all relationships with protocol/technology.

## What Makes This Hard

1. **Spec reading and abstraction**: Must read a complex 12-service system spec and translate it to the correct level of abstraction for each C4 level
2. **C4 methodology knowledge**: Must know what belongs in Level 1 vs. Level 2, and what NOT to show at each level
3. **Three-page structure**: Must create and organize 3 diagram pages correctly
4. **Color convention**: Must apply C4 standard colors (blue/grey/yellow/light-blue) without being told exactly which elements are which color
5. **Relationship labeling**: Must determine appropriate protocol labels (HTTPS/REST, AMQP event, SQL, Redis, etc.)
6. **Scale**: 12 microservices + 4 external systems + 3 user types = 25+ elements to represent correctly

## System Under Specification

eShopOnContainers (Microsoft reference microservices application):
- 3 user types: Web Customer, Mobile Customer, Back-Office User
- 4 external systems: Stripe, SendGrid, Azure Service Bus, Application Insights
- 12 internal containers: Web MVC App, SPA Client, Mobile App, API Gateway (Ocelot), Identity.API, Catalog.API, Basket.API, Ordering.API, Payment.API, Marketing.API, Location.API, Event Bus (RabbitMQ)

## Success Criteria

| Criterion | Points |
|-----------|--------|
| C4 file created during task | 10 |
| 3 pages (Context + Container + Legend) | 15 |
| System Context page ≥ 6 shapes | 15 |
| Container Diagram page ≥ 10 shapes | 20 |
| eShopOnContainers system name in diagram | 5 |
| C4 color coding (blue for owned system) | 10 |
| ≥5 labeled relationship edges | 10 |
| PDF exported | 15 |

**Pass threshold**: 60 points
