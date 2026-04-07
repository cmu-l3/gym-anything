#!/bin/bash
set -e
echo "=== Setting up Docker Legacy Containerization Task ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Wait for Docker
if ! type wait_for_docker &>/dev/null; then
    wait_for_docker() {
        for i in {1..60}; do
            if docker info > /dev/null 2>&1; then return 0; fi
            sleep 2
        done
        return 1
    }
fi
wait_for_docker

# Record start time
date +%s > /tmp/task_start_time.txt

# Create Project Directory
PROJECT_DIR="/home/ga/projects/bookstore-legacy"
rm -rf "$PROJECT_DIR"
mkdir -p "$PROJECT_DIR/app"
mkdir -p "$PROJECT_DIR/static"
mkdir -p "$PROJECT_DIR/db"

# 1. Application Code
cat > "$PROJECT_DIR/app/__init__.py" << 'EOF'
from flask import Flask
from .config import Config
from .models import db

def create_app():
    app = Flask(__name__)
    app.config.from_object(Config)
    
    db.init_app(app)
    
    from .routes import main
    app.register_blueprint(main)
    
    return app
EOF

cat > "$PROJECT_DIR/app/config.py" << 'EOF'
import os

class Config:
    SQLALCHEMY_TRACK_MODIFICATIONS = False
    # Default to localhost for legacy/bare-metal run, but expects env var for Docker
    SQLALCHEMY_DATABASE_URI = os.environ.get('DATABASE_URL') or \
        'postgresql://bookstore:bookstore@localhost:5432/bookstore'
EOF

cat > "$PROJECT_DIR/app/models.py" << 'EOF'
from flask_sqlalchemy import SQLAlchemy
from dataclasses import dataclass

db = SQLAlchemy()

@dataclass
class Book(db.Model):
    id: int
    title: str
    author: str
    year: int
    isbn: str

    id = db.Column(db.Integer, primary_key=True)
    title = db.Column(db.String(200), nullable=False)
    author = db.Column(db.String(100), nullable=False)
    year = db.Column(db.Integer)
    isbn = db.Column(db.String(20))
EOF

cat > "$PROJECT_DIR/app/routes.py" << 'EOF'
from flask import Blueprint, jsonify
from .models import Book

main = Blueprint('main', __name__)

@main.route('/api/books', methods=['GET'])
def get_books():
    try:
        books = Book.query.all()
        return jsonify(books)
    except Exception as e:
        return jsonify({"error": str(e)}), 500

@main.route('/health')
def health():
    return jsonify({"status": "healthy"})
EOF

cat > "$PROJECT_DIR/run.py" << 'EOF'
from app import create_app

app = create_app()

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000)
EOF

cat > "$PROJECT_DIR/requirements.txt" << 'EOF'
Flask==2.3.3
Flask-SQLAlchemy==3.1.1
psycopg2-binary==2.9.7
gunicorn==21.2.0
EOF

# 2. Static Files
cat > "$PROJECT_DIR/static/index.html" << 'EOF'
<!DOCTYPE html>
<html>
<head>
    <title>Legacy Bookstore</title>
    <link rel="stylesheet" href="style.css">
</head>
<body>
    <h1>Classic Bookstore</h1>
    <div id="books">Loading...</div>
    <script>
        fetch('/api/books')
            .then(r => r.json())
            .then(data => {
                const div = document.getElementById('books');
                if(data.error) {
                    div.innerHTML = 'Error loading books: ' + data.error;
                } else {
                    div.innerHTML = data.map(b => 
                        `<div class="book"><h3>${b.title}</h3><p>${b.author} (${b.year})</p></div>`
                    ).join('');
                }
            })
            .catch(e => document.getElementById('books').innerHTML = 'Network error');
    </script>
</body>
</html>
EOF

cat > "$PROJECT_DIR/static/style.css" << 'EOF'
body { font-family: sans-serif; max-width: 800px; margin: 0 auto; padding: 20px; }
.book { border-bottom: 1px solid #ccc; padding: 10px 0; }
EOF

# 3. Database Files
cat > "$PROJECT_DIR/db/schema.sql" << 'EOF'
CREATE TABLE IF NOT EXISTS book (
    id SERIAL PRIMARY KEY,
    title VARCHAR(200) NOT NULL,
    author VARCHAR(100) NOT NULL,
    year INTEGER,
    isbn VARCHAR(20)
);
EOF

# Generate 50 real books for seed data
cat > "$PROJECT_DIR/db/seed.sql" << 'EOF'
INSERT INTO book (title, author, year, isbn) VALUES
('Pride and Prejudice', 'Jane Austen', 1813, '978-0141439518'),
('Moby-Dick', 'Herman Melville', 1851, '978-0142437247'),
('The Great Gatsby', 'F. Scott Fitzgerald', 1925, '978-0743273565'),
('Ulysses', 'James Joyce', 1922, '978-0679722762'),
('The Odyssey', 'Homer', -800, '978-0140268867'),
('War and Peace', 'Leo Tolstoy', 1869, '978-0199232765'),
('Crime and Punishment', 'Fyodor Dostoevsky', 1866, '978-0140449136'),
('The Brothers Karamazov', 'Fyodor Dostoevsky', 1880, '978-0374528379'),
('Don Quixote', 'Miguel de Cervantes', 1605, '978-0060934347'),
('Brave New World', 'Aldous Huxley', 1932, '978-0060850524'),
('One Hundred Years of Solitude', 'Gabriel Garcia Marquez', 1967, '978-0060883287'),
('The Catcher in the Rye', 'J.D. Salinger', 1951, '978-0316769480'),
('The Divine Comedy', 'Dante Alighieri', 1320, '978-0142437223'),
('The Iliad', 'Homer', -750, '978-0140275360'),
('Great Expectations', 'Charles Dickens', 1861, '978-0141439563'),
('Jane Eyre', 'Charlotte Bronte', 1847, '978-0141441146'),
('Wuthering Heights', 'Emily Bronte', 1847, '978-0141439556'),
('Frankenstein', 'Mary Shelley', 1818, '978-0141439471'),
('The Grapes of Wrath', 'John Steinbeck', 1939, '978-0143039433'),
('To Kill a Mockingbird', 'Harper Lee', 1960, '978-0061120084'),
('1984', 'George Orwell', 1949, '978-0451524935'),
('Animal Farm', 'George Orwell', 1945, '978-0451526342'),
('The Stranger', 'Albert Camus', 1942, '978-0679720201'),
('Heart of Darkness', 'Joseph Conrad', 1899, '978-0140281637'),
('Les Miserables', 'Victor Hugo', 1862, '978-0451419439'),
('Anna Karenina', 'Leo Tolstoy', 1877, '978-0143035008'),
('Madame Bovary', 'Gustave Flaubert', 1856, '978-0140449129'),
('The Sound and the Fury', 'William Faulkner', 1929, '978-0679732242'),
('Catch-22', 'Joseph Heller', 1961, '978-1451626650'),
('Lolita', 'Vladimir Nabokov', 1955, '978-0679723165'),
('Alice in Wonderland', 'Lewis Carroll', 1865, '978-0141439761'),
('The Adventures of Huckleberry Finn', 'Mark Twain', 1884, '978-0143107323'),
('A Tale of Two Cities', 'Charles Dickens', 1859, '978-0141439600'),
('Dracula', 'Bram Stoker', 1897, '978-0141439846'),
('The Picture of Dorian Gray', 'Oscar Wilde', 1890, '978-0141439570'),
('The Count of Monte Cristo', 'Alexandre Dumas', 1844, '978-0140449266'),
('Emma', 'Jane Austen', 1815, '978-0141439587'),
('Sense and Sensibility', 'Jane Austen', 1811, '978-0141439662'),
('Persuasion', 'Jane Austen', 1817, '978-0141439686'),
('David Copperfield', 'Charles Dickens', 1850, '978-0140439441'),
('Bleak House', 'Charles Dickens', 1853, '978-0141439723'),
('Middlemarch', 'George Eliot', 1871, '978-0141439549'),
('Vanity Fair', 'William Makepeace Thackeray', 1848, '978-0141439839'),
('The Portrait of a Lady', 'Henry James', 1881, '978-0141439631'),
('The Sun Also Rises', 'Ernest Hemingway', 1926, '978-0743297332'),
('A Farewell to Arms', 'Ernest Hemingway', 1929, '978-0684801469'),
('Of Mice and Men', 'John Steinbeck', 1937, '978-0140177398'),
('Fahrenheit 451', 'Ray Bradbury', 1953, '978-1451673319'),
('Slaughterhouse-Five', 'Kurt Vonnegut', 1969, '978-0385333849'),
('In Search of Lost Time', 'Marcel Proust', 1913, '978-0812969641');
EOF

# 4. Instructions
cat > "$PROJECT_DIR/README.md" << 'EOF'
# Legacy Bookstore Application

This is a Flask application that serves a book API and a static frontend.

## Architecture
- **App**: Python 3.11 + Flask + Gunicorn
- **Database**: PostgreSQL 15
- **Web Server**: Nginx (serves static files, proxies /api/ to App)

## Legacy Deployment (Bare Metal)
Previously, we ran this by:
1. Installing Postgres locally and creating a `bookstore` user/db.
2. Running `python3 run.py`.
3. Configuring system Nginx to point to port 5000.

## Task: Containerization
We need to move this to Docker.
1. Create a `Dockerfile` for the app.
2. Create an `nginx` directory with config.
3. Create a `docker-compose.yml` to run App, DB, and Nginx.
4. Ensure the DB is initialized with `db/schema.sql` and `db/seed.sql`.

## Configuration
The app expects the database connection string in the `DATABASE_URL` environment variable.
Example: `postgresql://user:pass@host:5432/dbname`
EOF

# Set permissions
chown -R ga:ga "$PROJECT_DIR"

# Launch terminal for agent
su - ga -c "DISPLAY=:1 gnome-terminal --maximize -- bash -c 'cd ~/projects/bookstore-legacy; echo \"Legacy Bookstore Containerization Task\"; ls -F; exec bash'" > /tmp/terminal_launch.log 2>&1 &

# Initial screenshot
sleep 2
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup Complete ==="