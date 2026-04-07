#!/bin/bash
set -e
echo "=== Setting up fix_feature_flag_engine task ==="

source /workspace/scripts/task_utils.sh

PROJECT_DIR="/home/ga/PycharmProjects/feature_flags"
rm -rf "$PROJECT_DIR"
mkdir -p "$PROJECT_DIR/flags"
mkdir -p "$PROJECT_DIR/tests"

# Record start time
date +%s > /tmp/task_start_time.txt

# --- Generate Project Files ---

# 1. flags/__init__.py
touch "$PROJECT_DIR/flags/__init__.py"

# 2. flags/tokens.py (Enum definitions)
cat > "$PROJECT_DIR/flags/tokens.py" << 'EOF'
from enum import Enum, auto

class TokenType(Enum):
    INTEGER = auto()
    FLOAT = auto()
    STRING = auto()
    IDENTIFIER = auto()
    
    PLUS = auto()
    MINUS = auto()
    
    EQ = auto()      # ==
    NEQ = auto()     # !=
    GT = auto()      # >
    LT = auto()      # <
    GTE = auto()     # >=
    LTE = auto()     # <=
    
    AND = auto()
    OR = auto()
    NOT = auto()
    
    LPAREN = auto()
    RPAREN = auto()
    DOT = auto()
    EOF = auto()

class Token:
    def __init__(self, type, value=None):
        self.type = type
        self.value = value
    
    def __repr__(self):
        return f"Token({self.type}, {self.value})"
EOF

# 3. flags/lexer.py (CONTAINS BUG 1: No float support)
cat > "$PROJECT_DIR/flags/lexer.py" << 'EOF'
from flags.tokens import Token, TokenType

class Lexer:
    def __init__(self, text):
        self.text = text
        self.pos = 0
        self.current_char = self.text[0] if self.text else None

    def advance(self):
        self.pos += 1
        self.current_char = self.text[self.pos] if self.pos < len(self.text) else None

    def skip_whitespace(self):
        while self.current_char is not None and self.current_char.isspace():
            self.advance()

    def integer(self):
        result = ""
        while self.current_char is not None and self.current_char.isdigit():
            result += self.current_char
            self.advance()
        
        # BUG: This method only handles integers. It stops at a dot ('.').
        # The main loop will then pick up '.' as a DOT token, breaking numbers like 0.5
        # into INT(0), DOT, INT(5).
        
        return int(result)

    def string(self):
        quote = self.current_char
        self.advance()
        result = ""
        while self.current_char is not None and self.current_char != quote:
            result += self.current_char
            self.advance()
        if self.current_char == quote:
            self.advance()
        return result

    def identifier(self):
        result = ""
        while self.current_char is not None and (self.current_char.isalnum() or self.current_char == '_'):
            result += self.current_char
            self.advance()
        
        keywords = {
            'AND': TokenType.AND,
            'OR': TokenType.OR,
            'NOT': TokenType.NOT
        }
        return Token(keywords.get(result, TokenType.IDENTIFIER), result)

    def get_next_token(self):
        while self.current_char is not None:
            if self.current_char.isspace():
                self.skip_whitespace()
                continue
                
            if self.current_char.isdigit():
                # BUG: Should check for potential float here or inside integer()
                return Token(TokenType.INTEGER, self.integer())
            
            if self.current_char in ['"', "'"]:
                return Token(TokenType.STRING, self.string())
                
            if self.current_char.isalpha():
                return self.identifier()
                
            if self.current_char == '=':
                self.advance()
                if self.current_char == '=':
                    self.advance()
                    return Token(TokenType.EQ)
                # Assignment not supported in this DSL
                raise Exception("Unexpected character '='")
                
            if self.current_char == '!':
                self.advance()
                if self.current_char == '=':
                    self.advance()
                    return Token(TokenType.NEQ)
                raise Exception("Expected '!='")
                
            if self.current_char == '>':
                self.advance()
                if self.current_char == '=':
                    self.advance()
                    return Token(TokenType.GTE)
                return Token(TokenType.GT)
                
            if self.current_char == '<':
                self.advance()
                if self.current_char == '=':
                    self.advance()
                    return Token(TokenType.LTE)
                return Token(TokenType.LT)
                
            if self.current_char == '(':
                self.advance()
                return Token(TokenType.LPAREN)
                
            if self.current_char == ')':
                self.advance()
                return Token(TokenType.RPAREN)
                
            if self.current_char == '.':
                self.advance()
                return Token(TokenType.DOT)
                
            raise Exception(f"Unknown character: {self.current_char}")
            
        return Token(TokenType.EOF)
EOF

# 4. flags/parser.py (CONTAINS BUG 2: Precedence inversion)
cat > "$PROJECT_DIR/flags/parser.py" << 'EOF'
from flags.tokens import TokenType

class ASTNode:
    pass

class BinOp(ASTNode):
    def __init__(self, left, op, right):
        self.left = left
        self.op = op
        self.right = right

class UnaryOp(ASTNode):
    def __init__(self, op, expr):
        self.op = op
        self.expr = expr

class Literal(ASTNode):
    def __init__(self, token):
        self.token = token
        self.value = token.value

class Variable(ASTNode):
    def __init__(self, token):
        self.name = token.value

class PropertyAccess(ASTNode):
    def __init__(self, object_node, property_name):
        self.object = object_node
        self.property = property_name

class Parser:
    def __init__(self, lexer):
        self.lexer = lexer
        self.current_token = self.lexer.get_next_token()

    def error(self):
        raise Exception("Invalid syntax")

    def eat(self, token_type):
        if self.current_token.type == token_type:
            self.current_token = self.lexer.get_next_token()
        else:
            self.error()

    # Pratt Parser binding powers
    # BUG: AND should have higher precedence than OR
    def get_binding_power(self, token_type):
        powers = {
            TokenType.OR: 20,
            TokenType.AND: 10,  # BUG: This should be higher than OR (e.g. 30)
            
            TokenType.EQ: 40,
            TokenType.NEQ: 40,
            TokenType.GT: 40,
            TokenType.LT: 40,
            TokenType.GTE: 40,
            TokenType.LTE: 40,
            
            TokenType.DOT: 60
        }
        return powers.get(token_type, 0)

    def atom(self):
        token = self.current_token
        if token.type in (TokenType.INTEGER, TokenType.FLOAT, TokenType.STRING):
            self.eat(token.type)
            return Literal(token)
        elif token.type == TokenType.IDENTIFIER:
            self.eat(TokenType.IDENTIFIER)
            return Variable(token)
        elif token.type == TokenType.LPAREN:
            self.eat(TokenType.LPAREN)
            node = self.expr()
            self.eat(TokenType.RPAREN)
            return node
        elif token.type == TokenType.NOT:
            self.eat(TokenType.NOT)
            return UnaryOp(token, self.atom())
        else:
            self.error()

    def expr(self, min_bp=0):
        left = self.atom()

        while self.current_token.type != TokenType.EOF:
            op = self.current_token
            bp = self.get_binding_power(op.type)
            
            if bp < min_bp:
                break
                
            if op.type == TokenType.DOT:
                self.eat(TokenType.DOT)
                prop = self.current_token
                self.eat(TokenType.IDENTIFIER)
                left = PropertyAccess(left, prop.value)
                continue
            
            self.eat(op.type)
            right = self.expr(bp) # Right associative? Or +1 for left? 
            # Simple implementation for this task
            left = BinOp(left, op, right)
            
        return left

    def parse(self):
        return self.expr()
EOF

# 5. flags/evaluator.py (CONTAINS BUG 3: No Short-circuiting)
cat > "$PROJECT_DIR/flags/evaluator.py" << 'EOF'
from flags.tokens import TokenType
from flags.parser import BinOp, UnaryOp, Literal, Variable, PropertyAccess

class Evaluator:
    def __init__(self, context):
        self.context = context

    def evaluate(self, node):
        if isinstance(node, Literal):
            return node.value
            
        if isinstance(node, Variable):
            return self.context.get(node.name)
            
        if isinstance(node, PropertyAccess):
            obj = self.evaluate(node.object)
            if obj is None:
                raise Exception(f"Cannot access property '{node.property}' of None")
            if isinstance(obj, dict):
                return obj.get(node.property)
            return getattr(obj, node.property, None)
            
        if isinstance(node, UnaryOp):
            if node.op.type == TokenType.NOT:
                return not self.evaluate(node.expr)
                
        if isinstance(node, BinOp):
            # BUG: Short-circuiting is missing for logic operators.
            # Python's 'and'/'or' evaluate lazily, but here we call evaluate() 
            # on both sides eagerly before combining them.
            
            if node.op.type == TokenType.AND:
                left_val = self.evaluate(node.left)
                right_val = self.evaluate(node.right) # BUG: Evaluated even if left_val is False
                return bool(left_val and right_val)
                
            if node.op.type == TokenType.OR:
                left_val = self.evaluate(node.left)
                right_val = self.evaluate(node.right) # BUG: Evaluated even if left_val is True
                return bool(left_val or right_val)
            
            # Comparison operators (eager evaluation is fine here)
            left_val = self.evaluate(node.left)
            right_val = self.evaluate(node.right)
            
            if node.op.type == TokenType.EQ: return left_val == right_val
            if node.op.type == TokenType.NEQ: return left_val != right_val
            if node.op.type == TokenType.GT: return left_val > right_val
            if node.op.type == TokenType.LT: return left_val < right_val
            if node.op.type == TokenType.GTE: return left_val >= right_val
            if node.op.type == TokenType.LTE: return left_val <= right_val
            
        raise Exception("Unknown node type")
EOF

# 6. tests/test_engine.py
cat > "$PROJECT_DIR/tests/test_engine.py" << 'EOF'
import pytest
from flags.lexer import Lexer
from flags.parser import Parser
from flags.evaluator import Evaluator

def eval_rule(rule, context):
    lexer = Lexer(rule)
    parser = Parser(lexer)
    ast = parser.parse()
    evaluator = Evaluator(context)
    return evaluator.evaluate(ast)

# --- Basic Tests (Should Pass) ---

def test_basic_equality():
    assert eval_rule("user == 'alice'", {"user": "alice"}) is True
    assert eval_rule("user == 'bob'", {"user": "alice"}) is False

def test_integers():
    assert eval_rule("age > 18", {"age": 20}) is True
    assert eval_rule("age < 18", {"age": 20}) is False

def test_property_access():
    ctx = {"user": {"name": "alice", "age": 25}}
    assert eval_rule("user.name == 'alice'", ctx) is True
    assert eval_rule("user.age == 25", ctx) is True

# --- BUG 1: Float Parsing ---

def test_tokenize_floats():
    # This fails if the lexer stops at '.', creating INTEGER(0) then DOT then INTEGER(5)
    # The parser will choke or produce wrong AST
    assert eval_rule("score > 0.5", {"score": 0.8}) is True
    assert eval_rule("score < 0.99", {"score": 0.8}) is True

def test_float_comparison():
    assert eval_rule("1.5 == 1.5", {}) is True
    assert eval_rule("2.0 > 1", {}) is True

# --- BUG 2: Precedence (AND vs OR) ---

def test_precedence_mixed():
    # A OR B AND C
    # Expected: A OR (B AND C)
    # If Precedence(AND) < Precedence(OR), parses as (A OR B) AND C
    
    # Case 1: True OR False AND False
    # Correct: True OR (False) -> True
    # Buggy: (True OR False) AND False -> True AND False -> False
    assert eval_rule("1==1 OR 1==0 AND 1==0", {}) is True

def test_precedence_complex():
    # False AND False OR True
    # Correct: (False) OR True -> True
    # Buggy (if inverted): False AND (False OR True) -> False AND True -> False
    # Actually if AND < OR, then False AND False OR True -> (False AND False) OR True?
    # Wait, Pratt parser behavior depends on binding power.
    # If OR=20, AND=10:
    # "A OR B AND C":
    # expr(0) calls atom() -> A
    # loops, sees OR (bp 20). 20 >= 0. calls expr(20).
    #   expr(20) calls atom() -> B
    #   loops, sees AND (bp 10). 10 < 20. breaks.
    #   returns B.
    # Back in expr(0), we have BinOp(A, OR, B).
    # loops, sees AND (bp 10). 10 >= 0. calls expr(10).
    #   expr(10) calls atom() -> C.
    #   returns C.
    # Back in expr(0), makes BinOp(BinOp(A, OR, B), AND, C).
    # Result: (A OR B) AND C. This is WRONG.
    
    # Test case: True OR True AND False
    # Correct: True OR (True AND False) -> True OR False -> True
    # Buggy: (True OR True) AND False -> True AND False -> False
    assert eval_rule("1==1 OR 1==1 AND 1==0", {}) is True

# --- BUG 3: Short-Circuit Evaluation ---

class Boom:
    def __bool__(self):
        raise Exception("Explosion! Should not have evaluated this.")
    
    def __eq__(self, other):
        raise Exception("Explosion! Should not have evaluated this.")

def test_short_circuit_and():
    # False AND Boom
    # Should return False without touching Boom
    # If it evaluates Boom, it crashes
    ctx = {"danger": Boom()}
    # We pass a context where 'danger' raises exception if accessed/compared
    # But wait, our evaluator accesses variables eagerly? 
    # In evaluate(Variable), we get the value.
    # But we want to test that the *expression* on the right isn't evaluated.
    
    # "exists AND exists.value"
    # If exists is None, exists.value raises Exception in property access.
    
    ctx = {"user": None}
    # This should return False, not crash with "Cannot access property 'name' of None"
    assert eval_rule("user != 'null' AND user.name == 'alice'", {"user": None}) is False

def test_short_circuit_or():
    # True OR Boom
    # Should return True without evaluating right side
    # "user != 'null' OR user.name == 'alice'"
    # If user is None:
    # Left: True. Right: Crash.
    # Wait, that example doesn't work for OR.
    
    # Example: "1==1 OR user.name == 'alice'" with user=None
    assert eval_rule("1==1 OR user.name == 'alice'", {"user": None}) is True

# --- Regression Tests ---

def test_grouping():
    assert eval_rule("(1==1 OR 1==0) AND 1==1", {}) is True
    assert eval_rule("(1==0 OR 1==0) AND 1==1", {}) is False

def test_not_op():
    assert eval_rule("NOT 1==0", {}) is True
    assert eval_rule("NOT (1==1 AND 1==1)", {}) is False
EOF

# 7. requirements.txt
echo "pytest" > "$PROJECT_DIR/requirements.txt"

# Set permissions
chown -R ga:ga "$PROJECT_DIR"

# Launch PyCharm
setup_pycharm_project "$PROJECT_DIR" "feature_flags" 180

echo "=== Task setup complete ==="