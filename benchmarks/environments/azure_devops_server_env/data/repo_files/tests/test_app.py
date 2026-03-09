"""
Integration tests for Tailwind Traders Inventory API.
"""
import pytest
from app import create_app, db
from models import Product, Category


@pytest.fixture
def app():
    app = create_app()
    app.config['SQLALCHEMY_DATABASE_URI'] = 'sqlite:///:memory:'
    app.config['TESTING'] = True

    with app.app_context():
        db.create_all()
        seed_test_data()
        yield app
        db.drop_all()


@pytest.fixture
def client(app):
    return app.test_client()


def seed_test_data():
    cat = Category(name='Electronics', description='Electronic components and devices')
    db.session.add(cat)
    db.session.flush()

    products = [
        Product(sku='TT-NET-4821', name='Industrial Ethernet Switch',
                price=99.00, cost=45.00, stock_quantity=200, category_id=cat.id),
        Product(sku='TT-ACC-1092', name='Wireless Mouse',
                price=29.99, cost=12.00, stock_quantity=500, category_id=cat.id),
        Product(sku='TT-MON-3301', name='27-inch 4K Monitor',
                price=449.99, cost=280.00, stock_quantity=75, category_id=cat.id),
    ]
    db.session.add_all(products)
    db.session.commit()


class TestHealthCheck:
    def test_health_endpoint(self, client):
        response = client.get('/health')
        assert response.status_code == 200
        data = response.get_json()
        assert data['status'] == 'healthy'
        assert 'version' in data


class TestProductEndpoints:
    def test_list_products(self, client):
        response = client.get('/api/v1/products')
        assert response.status_code == 200
        data = response.get_json()
        assert data['total'] == 3
        assert len(data['items']) == 3

    def test_get_product(self, client):
        response = client.get('/api/v1/products/1')
        assert response.status_code == 200
        data = response.get_json()
        assert data['sku'] == 'TT-NET-4821'

    def test_get_nonexistent_product(self, client):
        response = client.get('/api/v1/products/999')
        assert response.status_code == 404

    def test_create_product(self, client):
        response = client.post('/api/v1/products', json={
            'sku': 'TT-KBD-5500',
            'name': 'Mechanical Keyboard',
            'price': 149.99,
            'cost': 65.00,
            'stock_quantity': 100
        })
        assert response.status_code == 201
        data = response.get_json()
        assert data['sku'] == 'TT-KBD-5500'

    def test_create_duplicate_sku(self, client):
        response = client.post('/api/v1/products', json={
            'sku': 'TT-NET-4821',
            'name': 'Duplicate Product',
            'price': 10.00,
            'cost': 5.00
        })
        assert response.status_code == 409


class TestInventoryDeduction:
    def test_successful_deduction(self, client):
        response = client.post('/api/v1/inventory/deduct', json={
            'product_id': 1,
            'quantity': 10,
            'reference': 'ORD-2026-001'
        })
        assert response.status_code == 200
        data = response.get_json()
        assert data['remaining_stock'] == 190

    def test_insufficient_stock(self, client):
        response = client.post('/api/v1/inventory/deduct', json={
            'product_id': 1,
            'quantity': 999
        })
        assert response.status_code == 409

    def test_negative_quantity(self, client):
        response = client.post('/api/v1/inventory/deduct', json={
            'product_id': 1,
            'quantity': -5
        })
        assert response.status_code == 400
