#!/bin/bash
set -e

source /workspace/scripts/task_utils.sh

echo "=== Setting up Migrate Express API to TypeScript Task ==="

WORKSPACE_DIR="/home/ga/workspace/bookshelf-api"
sudo -u ga mkdir -p "$WORKSPACE_DIR/src/routes"
sudo -u ga mkdir -p "$WORKSPACE_DIR/src/models"
sudo -u ga mkdir -p "$WORKSPACE_DIR/src/middleware"
sudo -u ga mkdir -p "$WORKSPACE_DIR/src/utils"

cd "$WORKSPACE_DIR"

# ─────────────────────────────────────────────────────────────
# Create initial JavaScript codebase
# ─────────────────────────────────────────────────────────────

cat > "$WORKSPACE_DIR/src/server.js" << 'EOF'
const app = require('./app');
const logger = require('./utils/logger');

const PORT = process.env.PORT || 3000;

app.listen(PORT, () => {
  logger.info(`Server is running on port ${PORT}`);
});
EOF

cat > "$WORKSPACE_DIR/src/app.js" << 'EOF'
const express = require('express');
const bookRoutes = require('./routes/books');
const authRoutes = require('./routes/auth');
const errorHandler = require('./middleware/errorHandler');

const app = express();

app.use(express.json());

app.use('/api/auth', authRoutes);
app.use('/api/books', bookRoutes);

// Centralized error handling
app.use(errorHandler);

module.exports = app;
EOF

cat > "$WORKSPACE_DIR/src/routes/books.js" << 'EOF'
const express = require('express');
const BookModel = require('../models/book');
const authenticate = require('../middleware/authenticate');
const { validateBook } = require('../middleware/validate');
const { successResponse, errorResponse } = require('../utils/responses');

const router = express.Router();

router.get('/', (req, res, next) => {
  try {
    const genre = req.query.genre;
    const books = BookModel.findAll(genre);
    res.json(successResponse(books));
  } catch (err) {
    next(err);
  }
});

router.get('/:id', (req, res, next) => {
  try {
    const book = BookModel.findById(req.params.id);
    if (!book) return res.status(404).json(errorResponse('Book not found'));
    res.json(successResponse(book));
  } catch (err) {
    next(err);
  }
});

router.post('/', authenticate, validateBook, (req, res, next) => {
  try {
    const newBook = BookModel.create(req.body);
    res.status(201).json(successResponse(newBook));
  } catch (err) {
    next(err);
  }
});

router.put('/:id', authenticate, validateBook, (req, res, next) => {
  try {
    const updatedBook = BookModel.update(req.params.id, req.body);
    if (!updatedBook) return res.status(404).json(errorResponse('Book not found'));
    res.json(successResponse(updatedBook));
  } catch (err) {
    next(err);
  }
});

router.delete('/:id', authenticate, (req, res, next) => {
  try {
    const success = BookModel.remove(req.params.id);
    if (!success) return res.status(404).json(errorResponse('Book not found'));
    res.status(204).send();
  } catch (err) {
    next(err);
  }
});

module.exports = router;
EOF

cat > "$WORKSPACE_DIR/src/routes/auth.js" << 'EOF'
const express = require('express');
const jwt = require('jsonwebtoken');
const UserModel = require('../models/user');
const { successResponse, errorResponse } = require('../utils/responses');

const router = express.Router();
const JWT_SECRET = process.env.JWT_SECRET || 'supersecretkey';

router.post('/register', async (req, res, next) => {
  try {
    const { username, email, password } = req.body;
    if (!username || !email || !password) {
      return res.status(400).json(errorResponse('Missing required fields'));
    }
    const user = await UserModel.create({ username, email, password });
    res.status(201).json(successResponse({ id: user.id, username: user.username }));
  } catch (err) {
    next(err);
  }
});

router.post('/login', async (req, res, next) => {
  try {
    const { email, password } = req.body;
    const user = await UserModel.authenticate(email, password);
    if (!user) {
      return res.status(401).json(errorResponse('Invalid credentials'));
    }
    const token = jwt.sign({ userId: user.id, email: user.email }, JWT_SECRET, { expiresIn: '1h' });
    res.json(successResponse({ token }));
  } catch (err) {
    next(err);
  }
});

module.exports = router;
EOF

cat > "$WORKSPACE_DIR/src/models/book.js" << 'EOF'
const { v4: uuidv4 } = require('uuid');

const books = [];

class BookModel {
  static findAll(genre) {
    if (genre) return books.filter(b => b.genre.toLowerCase() === genre.toLowerCase());
    return books;
  }

  static findById(id) {
    return books.find(b => b.id === id);
  }

  static create(data) {
    const newBook = {
      id: uuidv4(),
      title: data.title,
      author: data.author,
      isbn: data.isbn,
      publishedYear: data.publishedYear,
      genre: data.genre,
      createdAt: new Date(),
      updatedAt: new Date()
    };
    books.push(newBook);
    return newBook;
  }

  static update(id, data) {
    const index = books.findIndex(b => b.id === id);
    if (index === -1) return null;
    
    books[index] = {
      ...books[index],
      ...data,
      id, // prevent overwriting ID
      updatedAt: new Date()
    };
    return books[index];
  }

  static remove(id) {
    const index = books.findIndex(b => b.id === id);
    if (index === -1) return false;
    books.splice(index, 1);
    return true;
  }
}

module.exports = BookModel;
EOF

cat > "$WORKSPACE_DIR/src/models/user.js" << 'EOF'
const { v4: uuidv4 } = require('uuid');
const bcrypt = require('bcryptjs');

const users = [];

class UserModel {
  static async create(data) {
    const existingUser = users.find(u => u.email === data.email);
    if (existingUser) throw new Error('User already exists');

    const salt = await bcrypt.genSalt(10);
    const passwordHash = await bcrypt.hash(data.password, salt);

    const newUser = {
      id: uuidv4(),
      username: data.username,
      email: data.email,
      passwordHash,
      createdAt: new Date()
    };
    users.push(newUser);
    return newUser;
  }

  static async authenticate(email, password) {
    const user = users.find(u => u.email === email);
    if (!user) return null;

    const isMatch = await bcrypt.compare(password, user.passwordHash);
    return isMatch ? user : null;
  }

  static findById(id) {
    return users.find(u => u.id === id);
  }
}

module.exports = UserModel;
EOF

cat > "$WORKSPACE_DIR/src/middleware/authenticate.js" << 'EOF'
const jwt = require('jsonwebtoken');
const { errorResponse } = require('../utils/responses');

const JWT_SECRET = process.env.JWT_SECRET || 'supersecretkey';

function authenticate(req, res, next) {
  const authHeader = req.headers.authorization;
  if (!authHeader || !authHeader.startsWith('Bearer ')) {
    return res.status(401).json(errorResponse('Missing or invalid token'));
  }

  const token = authHeader.split(' ')[1];
  try {
    const decoded = jwt.verify(token, JWT_SECRET);
    req.user = decoded;
    next();
  } catch (err) {
    return res.status(401).json(errorResponse('Invalid or expired token'));
  }
}

module.exports = authenticate;
EOF

cat > "$WORKSPACE_DIR/src/middleware/errorHandler.js" << 'EOF'
const logger = require('../utils/logger');
const { errorResponse } = require('../utils/responses');

function errorHandler(err, req, res, next) {
  logger.error(err.message || 'Internal Server Error', { stack: err.stack });
  
  const status = err.status || 500;
  const message = status === 500 ? 'Internal Server Error' : err.message;
  
  res.status(status).json(errorResponse(message));
}

module.exports = errorHandler;
EOF

cat > "$WORKSPACE_DIR/src/middleware/validate.js" << 'EOF'
const { errorResponse } = require('../utils/responses');

function validateBook(req, res, next) {
  const { title, author, isbn } = req.body;
  const errors = [];

  if (!title || typeof title !== 'string') errors.push('Title is required and must be a string');
  if (!author || typeof author !== 'string') errors.push('Author is required and must be a string');
  if (!isbn || typeof isbn !== 'string') errors.push('ISBN is required and must be a string');

  if (errors.length > 0) {
    return res.status(400).json(errorResponse('Validation failed', errors));
  }

  next();
}

module.exports = { validateBook };
EOF

cat > "$WORKSPACE_DIR/src/utils/logger.js" << 'EOF'
const logger = {
  info: (message, meta = {}) => {
    console.log(`[INFO] ${new Date().toISOString()} - ${message}`, meta);
  },
  error: (message, meta = {}) => {
    console.error(`[ERROR] ${new Date().toISOString()} - ${message}`, meta);
  },
  warn: (message, meta = {}) => {
    console.warn(`[WARN] ${new Date().toISOString()} - ${message}`, meta);
  }
};

module.exports = logger;
EOF

cat > "$WORKSPACE_DIR/src/utils/responses.js" << 'EOF'
function successResponse(data, message = 'Success') {
  return {
    success: true,
    message,
    data
  };
}

function errorResponse(message, details = null) {
  const response = {
    success: false,
    message
  };
  if (details) {
    response.details = details;
  }
  return response;
}

module.exports = {
  successResponse,
  errorResponse
};
EOF

# ─────────────────────────────────────────────────────────────
# Setup NPM Project
# ─────────────────────────────────────────────────────────────
echo "Initializing NPM project..."
cat > "$WORKSPACE_DIR/package.json" << 'EOF'
{
  "name": "bookshelf-api",
  "version": "1.0.0",
  "description": "A simple API for managing books",
  "main": "src/server.js",
  "scripts": {
    "start": "node src/server.js"
  },
  "dependencies": {
    "bcryptjs": "^2.4.3",
    "express": "^4.18.2",
    "jsonwebtoken": "^9.0.2",
    "uuid": "^9.0.1"
  }
}
EOF

# Pre-install dependencies to save agent time
echo "Installing dependencies..."
sudo -u ga bash -c "cd $WORKSPACE_DIR && npm install"

# Fix permissions
chown -R ga:ga "$WORKSPACE_DIR"

# ─────────────────────────────────────────────────────────────
# Environment Initialization
# ─────────────────────────────────────────────────────────────
# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt
echo "Initial JS file count: $(find "$WORKSPACE_DIR/src" -name "*.js" | wc -l)" > /tmp/initial_js_count.txt

# Start VSCode
if ! pgrep -f "code" > /dev/null; then
    echo "Starting VSCode..."
    sudo -u ga bash -c "DISPLAY=:1 code $WORKSPACE_DIR &"
    sleep 5
fi

# Maximize and focus VSCode window
focus_vscode_window 2>/dev/null || true
DISPLAY=:1 wmctrl -r "Visual Studio Code" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Take screenshot of initial state
take_screenshot /tmp/task_initial_state.png ga

echo "=== Task setup complete ==="