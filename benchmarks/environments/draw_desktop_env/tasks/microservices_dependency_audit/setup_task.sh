#!/bin/bash
# Do NOT use set -e

echo "=== Setting up microservices_dependency_audit task ==="

DRAWIO_BIN=""
if command -v drawio &>/dev/null; then
    DRAWIO_BIN="drawio"
elif [ -f /opt/drawio/drawio ]; then
    DRAWIO_BIN="/opt/drawio/drawio"
elif [ -f /usr/bin/drawio ]; then
    DRAWIO_BIN="/usr/bin/drawio"
fi

if [ -z "$DRAWIO_BIN" ]; then
    echo "ERROR: draw.io binary not found!"
    exit 1
fi

# Ensure Diagrams directory exists
mkdir -p /home/ga/Diagrams
chown ga:ga /home/ga/Diagrams

# Copy the partial (incorrect) starter diagram
if [ -f /workspace/assets/diagrams/microservices_partial.drawio ]; then
    cp /workspace/assets/diagrams/microservices_partial.drawio /home/ga/Diagrams/microservices_partial.drawio
    chown ga:ga /home/ga/Diagrams/microservices_partial.drawio
    echo "Starter diagram copied: /home/ga/Diagrams/microservices_partial.drawio"
else
    echo "WARNING: starter diagram not found in assets"
fi

# Clean up any previous outputs
rm -f /home/ga/Desktop/microservices_architecture.drawio 2>/dev/null || true
rm -f /home/ga/Desktop/microservices_architecture.svg 2>/dev/null || true

# Create the authoritative service catalog.
# Based on Google's Online Boutique open-source demo microservices application
# (https://github.com/GoogleCloudPlatform/microservices-demo — Apache 2.0 license)
# with realistic fintech-adapted service names and dependencies.
cat > /home/ga/Desktop/service_catalog.yaml << 'YAMLEOF'
# Fintech Microservices Platform — Service Catalog
# Organization: Meridian Financial Technology Inc.
# Adapted from: Google Online Boutique open-source reference (Apache 2.0)
# Source: https://github.com/GoogleCloudPlatform/microservices-demo
# Version: 2.3.1

domains:
  - name: Customer Domain
    color: "#d5e8d4"
    services: [api-gateway, customer-service, notification-service]

  - name: Payment Domain
    color: "#ffe6cc"
    services: [payment-service, fraud-detection-service, ledger-service]

  - name: Operations Domain
    color: "#dae8fc"
    services: [checkout-service, order-service, reporting-service]

services:
  - id: api-gateway
    display_name: "API Gateway"
    domain: Customer Domain
    tech_stack: "Node.js/Express"        # CORRECT (partial diagram had this right)
    port: 8080
    protocol_in: REST/HTTPS
    depends_on:
      - service: customer-service
        protocol: REST
        notes: "Fetch customer profile on each authenticated request"
      - service: checkout-service
        protocol: REST
        notes: "Initiate checkout flow"
      - service: order-service
        protocol: REST
        notes: "Query order history"
    description: "Edge gateway — all external traffic enters here. Rate limiting, auth token validation."

  - id: customer-service
    display_name: "Customer Service"
    domain: Customer Domain
    tech_stack: "Python/FastAPI"         # WRONG in partial diagram (said Java/Spring)
    port: 8081
    protocol_in: REST
    depends_on:
      - service: notification-service
        protocol: AMQP
        notes: "Publish CustomerCreated / CustomerUpdated events"
    description: "Manages customer profiles, KYC status, and account settings."

  - id: notification-service
    display_name: "Notification Service"
    domain: Customer Domain
    tech_stack: "Python/Celery"
    port: 8082
    protocol_in: AMQP
    depends_on: []
    description: "Consumes events from RabbitMQ. Sends email/SMS/push via SendGrid and Twilio."
    # MISSING from partial diagram

  - id: payment-service
    display_name: "Payment Service"
    domain: Payment Domain
    tech_stack: "Go/gRPC"               # WRONG in partial diagram (said Ruby/Rails)
    port: 50051
    protocol_in: gRPC
    depends_on:
      - service: fraud-detection-service
        protocol: gRPC
        notes: "Synchronous fraud score check before processing payment"
      - service: ledger-service
        protocol: gRPC
        notes: "Record debit/credit entries after successful payment"
    description: "Processes ACH, card, and wire payments. Integrates with Stripe and Plaid."

  - id: fraud-detection-service
    display_name: "Fraud Detection Service"
    domain: Payment Domain
    tech_stack: "Python/scikit-learn"
    port: 50052
    protocol_in: gRPC
    depends_on: []
    description: "ML-based fraud scoring (XGBoost model). Returns risk score 0-100."
    # MISSING from partial diagram

  - id: ledger-service
    display_name: "Ledger Service"
    domain: Payment Domain
    tech_stack: "Java/Spring Boot"
    port: 50053
    protocol_in: gRPC
    depends_on:
      - service: reporting-service
        protocol: AMQP
        notes: "Publish LedgerEntry events for async reporting"
    description: "Double-entry accounting ledger. Immutable audit log of all financial transactions."
    # MISSING from partial diagram

  - id: checkout-service
    display_name: "Checkout Service"
    domain: Operations Domain
    tech_stack: "Go"
    port: 8083
    protocol_in: REST
    depends_on:
      - service: payment-service
        protocol: gRPC
        notes: "Trigger payment processing during checkout"
      - service: order-service
        protocol: REST
        notes: "Create order record after successful payment"
      - service: customer-service
        protocol: REST
        notes: "Validate customer account and credit limit"
    description: "Orchestrates the checkout flow: cart → payment → order creation."
    # MISSING from partial diagram

  - id: order-service
    display_name: "Order Service"
    domain: Operations Domain
    tech_stack: "Python/FastAPI"
    port: 8084
    protocol_in: REST
    depends_on:
      - service: notification-service
        protocol: AMQP
        notes: "Publish OrderCreated events for customer notification"
      - service: reporting-service
        protocol: AMQP
        notes: "Publish order data for analytics"
    description: "Manages order lifecycle: created → processing → shipped → delivered."
    # MISSING from partial diagram

  - id: reporting-service
    display_name: "Reporting Service"
    domain: Operations Domain
    tech_stack: "Python/Pandas + Spark"
    port: 8085
    protocol_in: AMQP
    depends_on: []
    description: "Consumes financial and operational events. Generates regulatory reports (SOX, PCI-DSS)."
    # MISSING from partial diagram

correct_connections:
  # Format: source -> target (protocol)
  - "api-gateway -> customer-service (REST)"
  - "api-gateway -> checkout-service (REST)"
  - "api-gateway -> order-service (REST)"
  - "customer-service -> notification-service (AMQP)"
  - "checkout-service -> payment-service (gRPC)"
  - "checkout-service -> order-service (REST)"
  - "checkout-service -> customer-service (REST)"
  - "payment-service -> fraud-detection-service (gRPC)"
  - "payment-service -> ledger-service (gRPC)"
  - "ledger-service -> reporting-service (AMQP)"
  - "order-service -> notification-service (AMQP)"
  - "order-service -> reporting-service (AMQP)"

known_errors_in_partial_diagram:
  - "edge-wrong-1: api-gateway -> payment-service (gRPC) — WRONG. Should be api-gateway -> checkout-service (REST)"
  - "edge-wrong-2: customer-service -> api-gateway (REST) — WRONG DIRECTION. Should be api-gateway -> customer-service (REST)"
  - "customer-service tech_stack: listed as Java/Spring — WRONG. Should be Python/FastAPI"
  - "payment-service tech_stack: listed as Ruby/Rails — WRONG. Should be Go/gRPC"
  - "6 services missing: notification-service, fraud-detection-service, ledger-service, checkout-service, order-service, reporting-service"

output_files:
  drawio: "~/Desktop/microservices_architecture.drawio"
  svg: "~/Desktop/microservices_architecture.svg"
YAMLEOF

chown ga:ga /home/ga/Desktop/service_catalog.yaml 2>/dev/null || true
echo "Service catalog created: /home/ga/Desktop/service_catalog.yaml"

# Record initial state of the partial diagram
INITIAL_DRAWIO_COUNT=$(ls /home/ga/Desktop/*.drawio 2>/dev/null | wc -l || echo "0")
echo "$INITIAL_DRAWIO_COUNT" > /tmp/initial_drawio_count

# Record hash of partial file (to detect if agent just copies it without editing)
if [ -f /home/ga/Diagrams/microservices_partial.drawio ]; then
    md5sum /home/ga/Diagrams/microservices_partial.drawio | cut -d' ' -f1 > /tmp/initial_partial_md5
fi

date +%s > /tmp/task_start_timestamp

# Launch draw.io and open the partial diagram file
echo "Launching draw.io with partial diagram..."
su - ga -c "DISPLAY=:1 DRAWIO_DISABLE_UPDATE=true $DRAWIO_BIN --no-sandbox --disable-update /home/ga/Diagrams/microservices_partial.drawio > /tmp/drawio_ms.log 2>&1 &"

echo "Waiting for draw.io window..."
for i in $(seq 1 30); do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "draw.io\|microservices"; then
        echo "draw.io window detected after ${i}s"
        break
    fi
    sleep 1
done

sleep 6
DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -r "draw.io" -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 1

DISPLAY=:1 import -window root /tmp/ms_start.png 2>/dev/null || true

echo "=== Setup complete: partial diagram open in draw.io, service_catalog.yaml on Desktop ==="
