#!/bin/bash
set -e

echo "=== Setting up Microservices Sock Shop Architecture Task ==="

# 1. Create Directories
mkdir -p /home/ga/Diagrams/exports
mkdir -p /home/ga/Desktop

# 2. Create the Service Manifest JSON
cat > /home/ga/Desktop/service_manifest.json << 'JSONEOF'
{
  "architecture_name": "Sock Shop - Microservices Reference Architecture",
  "description": "Cloud-native e-commerce reference application.",
  "services": [
    {"name": "edge-router", "type": "infrastructure", "tech": "Traefik", "port": 80, "description": "API gateway"},
    {"name": "front-end", "type": "application", "tech": "Node.js", "port": 8079, "description": "Web UI"},
    {"name": "catalogue", "type": "application", "tech": "Go", "port": 80, "description": "Product catalogue"},
    {"name": "carts", "type": "application", "tech": "Java", "port": 80, "description": "Shopping cart"},
    {"name": "orders", "type": "application", "tech": "Java", "port": 80, "description": "Order processing"},
    {"name": "payment", "type": "application", "tech": "Go", "port": 80, "description": "Payment processing"},
    {"name": "user", "type": "application", "tech": "Go", "port": 80, "description": "User account"},
    {"name": "shipping", "type": "application", "tech": "Java", "port": 80, "description": "Shipping"},
    {"name": "queue-master", "type": "application", "tech": "Java", "port": 80, "description": "Queue processor"}
  ],
  "data_stores": [
    {"name": "catalogue-db", "type": "database", "engine": "MySQL", "port": 3306},
    {"name": "carts-db", "type": "database", "engine": "MongoDB", "port": 27017},
    {"name": "orders-db", "type": "database", "engine": "MongoDB", "port": 27017},
    {"name": "user-db", "type": "database", "engine": "MongoDB", "port": 27017}
  ],
  "message_queues": [
    {"name": "rabbitmq", "type": "message_queue", "engine": "RabbitMQ", "port": 5672}
  ],
  "dependencies": [
    {"from": "edge-router", "to": "front-end", "protocol": "HTTP"},
    {"from": "front-end", "to": "catalogue", "protocol": "HTTP"},
    {"from": "front-end", "to": "carts", "protocol": "HTTP"},
    {"from": "front-end", "to": "orders", "protocol": "HTTP"},
    {"from": "front-end", "to": "user", "protocol": "HTTP"},
    {"from": "orders", "to": "payment", "protocol": "HTTP"},
    {"from": "orders", "to": "shipping", "protocol": "HTTP"},
    {"from": "orders", "to": "carts", "protocol": "HTTP"},
    {"from": "orders", "to": "user", "protocol": "HTTP"},
    {"from": "catalogue", "to": "catalogue-db", "protocol": "TCP"},
    {"from": "carts", "to": "carts-db", "protocol": "TCP"},
    {"from": "orders", "to": "orders-db", "protocol": "TCP"},
    {"from": "user", "to": "user-db", "protocol": "TCP"},
    {"from": "shipping", "to": "rabbitmq", "protocol": "AMQP"},
    {"from": "queue-master", "to": "rabbitmq", "protocol": "AMQP"}
  ],
  "color_scheme": {
    "Go": "#00BCD4",
    "Java": "#FF9800",
    "Node.js": "#4CAF50",
    "Infrastructure": "#9E9E9E",
    "MySQL": "#00758F",
    "MongoDB": "#4DB33D",
    "RabbitMQ": "#FF6600"
  }
}
JSONEOF

# 3. Create the Starting Diagram (Uncompressed XML)
# Contains only edge-router and front-end
cat > /home/ga/Diagrams/sock_shop_architecture.drawio << 'XML_EOF'
<?xml version="1.0" encoding="UTF-8"?>
<mxfile host="Electron" modified="2024-01-01T00:00:00.000Z" agent="5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) draw.io/22.0.0 Chrome/114.0.5735.289 Electron/25.8.0 Safari/537.36" version="22.0.0" type="device">
  <diagram id="sock-shop-id" name="Page-1">
    <mxGraphModel dx="1000" dy="1000" grid="1" gridSize="10" guides="1" tooltips="1" connect="1" arrows="1" fold="1" page="1" pageScale="1" pageWidth="850" pageHeight="1100" math="0" shadow="0">
      <root>
        <mxCell id="0" />
        <mxCell id="1" parent="0" />
        <mxCell id="edge-router" value="edge-router" style="rounded=1;whiteSpace=wrap;html=1;fillColor=#9E9E9E;strokeColor=#666666;fontColor=#FFFFFF;fontStyle=1" vertex="1" parent="1">
          <mxGeometry x="360" y="40" width="120" height="60" as="geometry" />
        </mxCell>
        <mxCell id="front-end" value="front-end" style="rounded=1;whiteSpace=wrap;html=1;fillColor=#4CAF50;strokeColor=#2D7600;fontColor=#FFFFFF;fontStyle=1" vertex="1" parent="1">
          <mxGeometry x="360" y="160" width="120" height="60" as="geometry" />
        </mxCell>
        <mxCell id="link1" value="HTTP" style="edgeStyle=orthogonalEdgeStyle;rounded=0;orthogonalLoop=1;jettySize=auto;html=1;exitX=0.5;exitY=1;exitDx=0;exitDy=0;entryX=0.5;entryY=0;entryDx=0;entryDy=0;" edge="1" parent="1" source="edge-router" target="front-end">
          <mxGeometry relative="1" as="geometry" />
        </mxCell>
      </root>
    </mxGraphModel>
  </diagram>
</mxfile>
XML_EOF

# Set permissions
chown -R ga:ga /home/ga/Diagrams
chown -R ga:ga /home/ga/Desktop
chmod 644 /home/ga/Desktop/service_manifest.json
chmod 644 /home/ga/Diagrams/sock_shop_architecture.drawio

# 4. Launch draw.io
echo "Launching draw.io..."
pkill -f drawio || true
su - ga -c "DISPLAY=:1 /opt/drawio/drawio.AppImage --no-sandbox /home/ga/Diagrams/sock_shop_architecture.drawio > /tmp/drawio.log 2>&1 &"

# 5. Handle Update Dialog
echo "Waiting for window..."
sleep 5
for i in {1..10}; do
    if DISPLAY=:1 wmctrl -l | grep -qi "draw.io"; then
        echo "Window found."
        break
    fi
    sleep 1
done

echo "Attempting to dismiss potential update dialogs..."
# Press Escape multiple times to clear "Update Available" or "Open File" dialogs
for i in {1..5}; do
    DISPLAY=:1 xdotool key Escape 2>/dev/null || true
    sleep 0.5
done

# Focus the main window
DISPLAY=:1 wmctrl -a "draw.io" 2>/dev/null || true
DISPLAY=:1 wmctrl -r "draw.io" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# 6. Record Initial State
date +%s > /tmp/task_start_time.txt
stat -c %Y /home/ga/Diagrams/sock_shop_architecture.drawio > /tmp/initial_file_mtime.txt

# 7. Initial Screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup Complete ==="