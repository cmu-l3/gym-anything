"""
Database models for Tailwind Traders Inventory API.
Uses SQLAlchemy ORM with PostgreSQL backend.
"""
from datetime import datetime
from app import db


class Category(db.Model):
    __tablename__ = 'categories'

    id = db.Column(db.Integer, primary_key=True)
    name = db.Column(db.String(100), nullable=False, unique=True)
    description = db.Column(db.Text)
    parent_id = db.Column(db.Integer, db.ForeignKey('categories.id'), nullable=True)
    created_at = db.Column(db.DateTime, default=datetime.utcnow)

    products = db.relationship('Product', backref='category', lazy='dynamic')
    children = db.relationship('Category', backref=db.backref('parent', remote_side=[id]))

    def to_dict(self):
        return {
            'id': self.id,
            'name': self.name,
            'description': self.description,
            'parent_id': self.parent_id,
            'product_count': self.products.count(),
            'created_at': self.created_at.isoformat()
        }


class Product(db.Model):
    __tablename__ = 'products'

    id = db.Column(db.Integer, primary_key=True)
    sku = db.Column(db.String(50), nullable=False, unique=True, index=True)
    name = db.Column(db.String(200), nullable=False)
    description = db.Column(db.Text)
    category_id = db.Column(db.Integer, db.ForeignKey('categories.id'), nullable=True)
    price = db.Column(db.Numeric(10, 2), nullable=False)
    cost = db.Column(db.Numeric(10, 2), nullable=False)
    stock_quantity = db.Column(db.Integer, default=0, nullable=False)
    reorder_point = db.Column(db.Integer, default=10)
    reorder_quantity = db.Column(db.Integer, default=50)
    weight_kg = db.Column(db.Numeric(8, 3))
    barcode = db.Column(db.String(50), unique=True, nullable=True)
    is_active = db.Column(db.Boolean, default=True)
    created_at = db.Column(db.DateTime, default=datetime.utcnow)
    updated_at = db.Column(db.DateTime, default=datetime.utcnow, onupdate=datetime.utcnow)

    stock_movements = db.relationship('StockMovement', backref='product', lazy='dynamic')

    __table_args__ = (
        db.Index('idx_category_price', 'category_id', 'price'),
        db.Index('idx_name_search', 'name'),
    )

    def to_dict(self):
        return {
            'id': self.id,
            'sku': self.sku,
            'name': self.name,
            'description': self.description,
            'category': self.category.name if self.category else None,
            'price': float(self.price),
            'cost': float(self.cost),
            'stock_quantity': self.stock_quantity,
            'reorder_point': self.reorder_point,
            'is_active': self.is_active,
            'created_at': self.created_at.isoformat(),
            'updated_at': self.updated_at.isoformat()
        }


class StockMovement(db.Model):
    __tablename__ = 'stock_movements'

    id = db.Column(db.Integer, primary_key=True)
    product_id = db.Column(db.Integer, db.ForeignKey('products.id'), nullable=False)
    movement_type = db.Column(db.String(20), nullable=False)  # 'receipt', 'shipment', 'adjustment', 'transfer'
    quantity = db.Column(db.Integer, nullable=False)
    reference = db.Column(db.String(100))
    notes = db.Column(db.Text)
    performed_by = db.Column(db.String(100))
    created_at = db.Column(db.DateTime, default=datetime.utcnow)

    def to_dict(self):
        return {
            'id': self.id,
            'product_id': self.product_id,
            'product_sku': self.product.sku,
            'movement_type': self.movement_type,
            'quantity': self.quantity,
            'reference': self.reference,
            'notes': self.notes,
            'performed_by': self.performed_by,
            'created_at': self.created_at.isoformat()
        }


class BulkPricingTier(db.Model):
    __tablename__ = 'bulk_pricing_tiers'

    id = db.Column(db.Integer, primary_key=True)
    product_id = db.Column(db.Integer, db.ForeignKey('products.id'), nullable=False)
    min_quantity = db.Column(db.Integer, nullable=False)
    discount_percent = db.Column(db.Numeric(5, 2), nullable=False)

    product = db.relationship('Product', backref='pricing_tiers')

    __table_args__ = (
        db.UniqueConstraint('product_id', 'min_quantity', name='uq_product_tier'),
    )
