# Tailwind Traders Inventory API

A Flask-based REST API for managing product inventory, stock levels, and warehouse operations.

## Quick Start

```bash
# Install dependencies
pip install -r requirements.txt

# Set up database
export DATABASE_URL=postgresql://tailwind:tailwind@localhost:5432/inventory
flask db upgrade

# Run development server
python app.py
```

## API Endpoints

| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/api/v1/products` | List products (paginated) |
| GET | `/api/v1/products/<id>` | Get product details |
| POST | `/api/v1/products` | Create a product |
| PUT | `/api/v1/products/<id>` | Update a product |
| POST | `/api/v1/inventory/deduct` | Deduct stock |
| GET | `/api/v1/categories` | List categories |
| POST | `/api/v1/categories` | Create a category |
| GET | `/api/v1/stock-movements` | List stock movements |
| GET | `/health` | Health check |

## Running Tests

```bash
pytest tests/ -v --cov=. --cov-report=term-missing
```

## Architecture

- **Framework**: Flask 3.0
- **Database**: PostgreSQL with SQLAlchemy ORM
- **Migrations**: Alembic via Flask-Migrate
- **Caching**: Redis (planned)
- **Deployment**: Docker + Gunicorn

## Contributing

1. Create a feature branch from `main`
2. Write tests for new functionality
3. Ensure all tests pass and coverage >= 80%
4. Create a pull request with description of changes
