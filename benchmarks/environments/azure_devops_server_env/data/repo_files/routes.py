"""
API routes for the Tailwind Traders Inventory Management API.
"""
from flask import Blueprint, request, jsonify, abort
from models import db, Product, Category, StockMovement

api_bp = Blueprint('api', __name__)


@api_bp.route('/products', methods=['GET'])
def list_products():
    page = request.args.get('page', 1, type=int)
    per_page = request.args.get('per_page', 20, type=int)
    category = request.args.get('category')
    active_only = request.args.get('active', 'true').lower() == 'true'

    query = Product.query
    if active_only:
        query = query.filter(Product.is_active == True)
    if category:
        query = query.join(Category).filter(Category.name == category)

    pagination = query.order_by(Product.name).paginate(
        page=page, per_page=min(per_page, 100), error_out=False
    )

    return jsonify({
        'items': [p.to_dict() for p in pagination.items],
        'total': pagination.total,
        'page': pagination.page,
        'pages': pagination.pages,
        'per_page': pagination.per_page
    })


@api_bp.route('/products/<int:product_id>', methods=['GET'])
def get_product(product_id):
    product = Product.query.get_or_404(product_id)
    return jsonify(product.to_dict())


@api_bp.route('/products', methods=['POST'])
def create_product():
    data = request.get_json()
    if not data:
        abort(400, description="Request body must be JSON")

    required_fields = ['sku', 'name', 'price', 'cost']
    for field in required_fields:
        if field not in data:
            abort(400, description=f"Missing required field: {field}")

    if Product.query.filter_by(sku=data['sku']).first():
        abort(409, description=f"Product with SKU '{data['sku']}' already exists")

    product = Product(
        sku=data['sku'],
        name=data['name'],
        description=data.get('description'),
        price=data['price'],
        cost=data['cost'],
        stock_quantity=data.get('stock_quantity', 0),
        reorder_point=data.get('reorder_point', 10),
        reorder_quantity=data.get('reorder_quantity', 50),
        weight_kg=data.get('weight_kg'),
        barcode=data.get('barcode')
    )

    if 'category_id' in data:
        category = Category.query.get(data['category_id'])
        if not category:
            abort(400, description=f"Category {data['category_id']} not found")
        product.category_id = data['category_id']

    db.session.add(product)
    db.session.commit()

    return jsonify(product.to_dict()), 201


@api_bp.route('/products/<int:product_id>', methods=['PUT'])
def update_product(product_id):
    product = Product.query.get_or_404(product_id)
    data = request.get_json()
    if not data:
        abort(400, description="Request body must be JSON")

    updatable_fields = [
        'name', 'description', 'price', 'cost', 'reorder_point',
        'reorder_quantity', 'weight_kg', 'barcode', 'is_active'
    ]
    for field in updatable_fields:
        if field in data:
            setattr(product, field, data[field])

    db.session.commit()
    return jsonify(product.to_dict())


@api_bp.route('/inventory/deduct', methods=['POST'])
def deduct_inventory():
    data = request.get_json()
    if not data:
        abort(400, description="Request body must be JSON")

    product_id = data.get('product_id')
    quantity = data.get('quantity')

    if not product_id or not quantity:
        abort(400, description="product_id and quantity are required")
    if quantity <= 0:
        abort(400, description="quantity must be positive")

    product = Product.query.get_or_404(product_id)

    # BUG: No row-level locking - race condition under concurrent requests
    if product.stock_quantity < quantity:
        abort(409, description=f"Insufficient stock. Available: {product.stock_quantity}")

    product.stock_quantity -= quantity

    movement = StockMovement(
        product_id=product.id,
        movement_type='shipment',
        quantity=-quantity,
        reference=data.get('reference', ''),
        notes=data.get('notes', ''),
        performed_by=data.get('performed_by', 'system')
    )
    db.session.add(movement)
    db.session.commit()

    return jsonify({
        'product_id': product.id,
        'quantity_deducted': quantity,
        'remaining_stock': product.stock_quantity
    })


@api_bp.route('/categories', methods=['GET'])
def list_categories():
    categories = Category.query.order_by(Category.name).all()
    return jsonify([c.to_dict() for c in categories])


@api_bp.route('/categories', methods=['POST'])
def create_category():
    data = request.get_json()
    if not data or 'name' not in data:
        abort(400, description="Category name is required")

    if Category.query.filter_by(name=data['name']).first():
        abort(409, description=f"Category '{data['name']}' already exists")

    category = Category(
        name=data['name'],
        description=data.get('description'),
        parent_id=data.get('parent_id')
    )
    db.session.add(category)
    db.session.commit()

    return jsonify(category.to_dict()), 201


@api_bp.route('/stock-movements', methods=['GET'])
def list_stock_movements():
    page = request.args.get('page', 1, type=int)
    product_id = request.args.get('product_id', type=int)

    query = StockMovement.query
    if product_id:
        query = query.filter(StockMovement.product_id == product_id)

    pagination = query.order_by(StockMovement.created_at.desc()).paginate(
        page=page, per_page=50, error_out=False
    )

    return jsonify({
        'items': [m.to_dict() for m in pagination.items],
        'total': pagination.total,
        'page': pagination.page
    })
