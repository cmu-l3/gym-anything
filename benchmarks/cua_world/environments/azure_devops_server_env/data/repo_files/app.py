"""
Tailwind Traders Inventory Management API
A Flask-based REST API for managing product inventory, stock levels,
and warehouse operations.
"""
import os
from flask import Flask, jsonify, request
from flask_sqlalchemy import SQLAlchemy
from flask_migrate import Migrate
from datetime import datetime

db = SQLAlchemy()
migrate = Migrate()


def create_app(config_name=None):
    app = Flask(__name__)

    database_url = os.environ.get(
        'DATABASE_URL',
        'postgresql://tailwind:tailwind@localhost:5432/inventory'
    )
    app.config['SQLALCHEMY_DATABASE_URI'] = database_url
    app.config['SQLALCHEMY_TRACK_MODIFICATIONS'] = False
    app.config['JSON_SORT_KEYS'] = False

    db.init_app(app)
    migrate.init_app(app, db)

    from models import Product, Category, StockMovement
    from routes import api_bp
    app.register_blueprint(api_bp, url_prefix='/api/v1')

    @app.route('/health')
    def health_check():
        return jsonify({
            'status': 'healthy',
            'version': '1.4.2',
            'timestamp': datetime.utcnow().isoformat()
        })

    return app


if __name__ == '__main__':
    app = create_app()
    app.run(host='0.0.0.0', port=5000, debug=True)
