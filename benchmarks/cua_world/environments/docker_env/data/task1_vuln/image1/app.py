"""
Simple Python API service - inventory management microservice.
Part of the AcmeCorp internal platform.
"""
from flask import Flask, jsonify

app = Flask(__name__)

# Sample inventory data
INVENTORY = [
    {"id": 1, "sku": "WIDGET-001", "name": "Basic Widget", "qty": 150, "price": 9.99},
    {"id": 2, "sku": "GADGET-002", "name": "Pro Gadget", "qty": 45, "price": 49.99},
    {"id": 3, "sku": "DOOHICKEY-003", "name": "Premium Doohickey", "qty": 23, "price": 99.99},
]


@app.route("/health")
def health():
    return jsonify({"status": "healthy", "service": "inventory-api"})


@app.route("/inventory")
def list_inventory():
    return jsonify({"items": INVENTORY, "total": len(INVENTORY)})


@app.route("/inventory/<int:item_id>")
def get_item(item_id):
    item = next((i for i in INVENTORY if i["id"] == item_id), None)
    if item:
        return jsonify(item)
    return jsonify({"error": "not found"}), 404


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000, debug=False)
