#!/bin/bash
echo "=== Setting up debug_and_complete_spreadsheet_engine task ==="

source /workspace/scripts/task_utils.sh

TASK_NAME="debug_and_complete_spreadsheet_engine"
PROJECT_DIR="/home/ga/PycharmProjects/spreadsheet_engine"

# Clean previous run
rm -rf "$PROJECT_DIR"
rm -f /tmp/${TASK_NAME}_result.json
rm -f /tmp/${TASK_NAME}_start_ts
rm -f /tmp/${TASK_NAME}_end_screenshot.png

# Create directory structure
mkdir -p "$PROJECT_DIR/engine"
mkdir -p "$PROJECT_DIR/tests"
mkdir -p "$PROJECT_DIR/data"

# ============================================================
# engine/__init__.py
# ============================================================
cat > "$PROJECT_DIR/engine/__init__.py" << 'PYEOF'
"""Spreadsheet formula engine."""
from engine.cell import Cell, CellRef, CellRange, FormulaError
from engine.sheet import Sheet
from engine.csv_io import load_csv, save_csv
from engine.formatter import format_value
PYEOF

# ============================================================
# engine/cell.py  (BUG B3)
# ============================================================
cat > "$PROJECT_DIR/engine/cell.py" << 'PYEOF'
"""Cell types and references for the spreadsheet engine."""


class FormulaError(Exception):
    """Raised when a formula cannot be evaluated."""
    pass


class CellRef:
    """Reference to a single cell like A1, B3."""

    def __init__(self, col, row):
        self.col = col  # 0-indexed column (A=0, B=1, ...)
        self.row = row  # 0-indexed row (row 1 => 0, row 2 => 1, ...)

    @staticmethod
    def from_string(s):
        """Parse 'A1' into CellRef(0, 0), 'B3' into CellRef(1, 2), etc."""
        col = 0
        i = 0
        while i < len(s) and s[i].isalpha():
            col = col * 26 + (ord(s[i].upper()) - ord('A'))
            i += 1
        row = int(s[i:]) - 1
        return CellRef(col, row)

    def to_string(self):
        """Convert to 'A1' format."""
        col_str = ''
        c = self.col
        while True:
            col_str = chr(ord('A') + c % 26) + col_str
            c = c // 26 - 1
            if c < 0:
                break
        return f"{col_str}{self.row + 1}"

    def __repr__(self):
        return self.to_string()

    def __eq__(self, other):
        return isinstance(other, CellRef) and self.col == other.col and self.row == other.row

    def __hash__(self):
        return hash((self.col, self.row))


class CellRange:
    """Range of cells like A1:C3."""

    def __init__(self, start, end):
        self.start = start  # CellRef
        self.end = end      # CellRef

    def __repr__(self):
        return f"{self.start}:{self.end}"


class Cell:
    """A single spreadsheet cell."""

    def __init__(self, raw_value=None, formula=None):
        self.raw_value = raw_value
        self.formula = formula
        self.computed_value = None
        self.error = None

    def get_display_value(self):
        """Return the value to display."""
        if self.error:
            return f"#ERROR: {self.error}"
        if self.computed_value is not None:
            return self.computed_value
        return self.raw_value if self.raw_value is not None else ""

    def get_numeric_value(self):
        """Return numeric value of cell, or None if not numeric.

        Returns None for empty cells so aggregate functions can skip them.
        """
        val = self.computed_value if self.computed_value is not None else self.raw_value
        if val is None or val == "":
            return 0  # BUG: should return None for empty/blank cells
        if isinstance(val, (int, float)):
            return float(val)
        if isinstance(val, str):
            try:
                return float(val)
            except (ValueError, TypeError):
                return None
        return None

    def is_empty(self):
        """Check if the cell has no value and no formula."""
        return (self.raw_value is None or self.raw_value == "") and self.formula is None
PYEOF

# ============================================================
# engine/parser.py  (BUG B1)
# ============================================================
cat > "$PROJECT_DIR/engine/parser.py" << 'PYEOF'
"""Formula parser for the spreadsheet engine.

Parses formulas like:
  =2+3*4
  =A1+B1
  =SUM(A1:A5)
  =IF(A1>10, "high", "low")
  =VLOOKUP("Gadget Pro", A1:C3, 2, 0)
"""
from engine.cell import CellRef, FormulaError


# --------------- AST Node Types ---------------

class NumberNode:
    def __init__(self, value):
        self.value = value
    def __repr__(self):
        return f"Num({self.value})"

class StringNode:
    def __init__(self, value):
        self.value = value
    def __repr__(self):
        return f"Str({self.value!r})"

class CellRefNode:
    def __init__(self, ref):
        self.ref = ref
    def __repr__(self):
        return f"Ref({self.ref})"

class RangeNode:
    def __init__(self, start, end):
        self.start = start   # CellRef
        self.end = end       # CellRef
    def __repr__(self):
        return f"Range({self.start}:{self.end})"

class BinaryOpNode:
    def __init__(self, op, left, right):
        self.op = op
        self.left = left
        self.right = right
    def __repr__(self):
        return f"({self.left} {self.op} {self.right})"

class UnaryOpNode:
    def __init__(self, op, operand):
        self.op = op
        self.operand = operand
    def __repr__(self):
        return f"({self.op}{self.operand})"

class FuncCallNode:
    def __init__(self, name, args):
        self.name = name.upper()
        self.args = args
    def __repr__(self):
        return f"{self.name}({', '.join(str(a) for a in self.args)})"

class ComparisonNode:
    def __init__(self, op, left, right):
        self.op = op
        self.left = left
        self.right = right
    def __repr__(self):
        return f"({self.left} {self.op} {self.right})"


# --------------- Tokenizer ---------------

class Token:
    def __init__(self, type_, value):
        self.type = type_
        self.value = value
    def __repr__(self):
        return f"Token({self.type}, {self.value!r})"


def tokenize(formula):
    """Tokenize a formula string into a list of tokens."""
    tokens = []
    i = 0
    while i < len(formula):
        c = formula[i]
        if c.isspace():
            i += 1
        elif c in '+-*/(),:':
            tokens.append(Token('OP', c))
            i += 1
        elif c in '<>=!':
            if i + 1 < len(formula) and formula[i + 1] in '=<>':
                tokens.append(Token('CMP', formula[i:i + 2]))
                i += 2
            else:
                tokens.append(Token('CMP', c))
                i += 1
        elif c == '"':
            j = i + 1
            while j < len(formula) and formula[j] != '"':
                j += 1
            tokens.append(Token('STRING', formula[i + 1:j]))
            i = j + 1
        elif c.isdigit() or (c == '.' and i + 1 < len(formula) and formula[i + 1].isdigit()):
            j = i
            while j < len(formula) and (formula[j].isdigit() or formula[j] == '.'):
                j += 1
            tokens.append(Token('NUMBER', float(formula[i:j])))
            i = j
        elif c.isalpha() or c == '_':
            j = i
            while j < len(formula) and (formula[j].isalnum() or formula[j] == '_'):
                j += 1
            word = formula[i:j]
            # Determine if this is a cell reference (letters then digits) or an identifier
            k = 0
            while k < len(word) and word[k].isalpha():
                k += 1
            if 0 < k < len(word) and word[k:].isdigit():
                tokens.append(Token('CELLREF', word))
            else:
                tokens.append(Token('IDENT', word))
            i = j
        else:
            raise FormulaError(f"Unexpected character: {c}")
    return tokens


# --------------- Recursive-Descent Parser ---------------

class Parser:
    """Recursive descent parser for spreadsheet formulas."""

    def __init__(self, formula):
        if formula.startswith('='):
            formula = formula[1:]
        self.tokens = tokenize(formula)
        self.pos = 0

    def peek(self):
        if self.pos < len(self.tokens):
            return self.tokens[self.pos]
        return None

    def advance(self):
        token = self.tokens[self.pos]
        self.pos += 1
        return token

    def expect(self, type_, value=None):
        token = self.peek()
        if token is None:
            raise FormulaError(f"Unexpected end of formula, expected {type_}")
        if token.type != type_ or (value is not None and token.value != value):
            raise FormulaError(f"Expected {type_} '{value}', got {token}")
        return self.advance()

    def parse(self):
        """Parse the full formula and return an AST."""
        node = self.parse_comparison()
        if self.pos < len(self.tokens):
            raise FormulaError(f"Unexpected token after expression: {self.peek()}")
        return node

    def parse_comparison(self):
        """Parse comparison operators: <, >, <=, >=, <>, =."""
        left = self.parse_expression()
        token = self.peek()
        if token and token.type == 'CMP':
            op = self.advance().value
            right = self.parse_expression()
            return ComparisonNode(op, left, right)
        return left

    def parse_expression(self):
        """Parse arithmetic expressions.

        NOTE: This method handles +, -, *, / all at the same precedence
        level, evaluating strictly left-to-right. For example, 2+3*4
        is parsed as (2+3)*4 = 20 rather than 2+(3*4) = 14.
        """
        left = self.parse_unary()
        while (self.peek() and self.peek().type == 'OP'
               and self.peek().value in '+-*/'):
            op = self.advance().value
            right = self.parse_unary()
            left = BinaryOpNode(op, left, right)
        return left

    def parse_unary(self):
        """Parse unary minus/plus."""
        token = self.peek()
        if token and token.type == 'OP' and token.value == '-':
            self.advance()
            operand = self.parse_primary()
            return UnaryOpNode('-', operand)
        if token and token.type == 'OP' and token.value == '+':
            self.advance()
            return self.parse_primary()
        return self.parse_primary()

    def parse_primary(self):
        """Parse primary expressions: numbers, strings, cell refs, ranges,
        function calls, parenthesized expressions."""
        token = self.peek()
        if token is None:
            raise FormulaError("Unexpected end of formula")

        if token.type == 'NUMBER':
            self.advance()
            return NumberNode(token.value)

        if token.type == 'STRING':
            self.advance()
            return StringNode(token.value)

        if token.type == 'OP' and token.value == '(':
            self.advance()
            node = self.parse_comparison()
            self.expect('OP', ')')
            return node

        if token.type == 'CELLREF':
            self.advance()
            ref = CellRef.from_string(token.value)
            # Check for range operator ':'
            if self.peek() and self.peek().type == 'OP' and self.peek().value == ':':
                self.advance()  # consume ':'
                end_token = self.expect('CELLREF')
                end_ref = CellRef.from_string(end_token.value)
                return RangeNode(ref, end_ref)
            return CellRefNode(ref)

        if token.type == 'IDENT':
            name = self.advance().value
            if self.peek() and self.peek().type == 'OP' and self.peek().value == '(':
                self.advance()  # consume '('
                args = []
                if not (self.peek() and self.peek().type == 'OP' and self.peek().value == ')'):
                    args.append(self.parse_comparison())
                    while self.peek() and self.peek().type == 'OP' and self.peek().value == ',':
                        self.advance()  # consume ','
                        args.append(self.parse_comparison())
                self.expect('OP', ')')
                return FuncCallNode(name, args)
            raise FormulaError(f"Unknown identifier: {name}")

        raise FormulaError(f"Unexpected token: {token}")


def parse_formula(formula):
    """Parse a formula string and return an AST."""
    return Parser(formula).parse()
PYEOF

# ============================================================
# engine/evaluator.py  (STUB S1)
# ============================================================
cat > "$PROJECT_DIR/engine/evaluator.py" << 'PYEOF'
"""Formula evaluator for the spreadsheet engine."""
from engine.cell import CellRef, FormulaError
from engine.parser import (
    NumberNode, StringNode, CellRefNode, RangeNode,
    BinaryOpNode, UnaryOpNode, FuncCallNode, ComparisonNode,
    parse_formula
)
from engine import functions as fn


class Evaluator:
    """Evaluates formula ASTs against a sheet."""

    def __init__(self, sheet):
        self.sheet = sheet

    def evaluate(self, formula_str):
        """Parse and evaluate a formula string."""
        ast = parse_formula(formula_str)
        return self.eval_node(ast)

    def eval_node(self, node):
        """Recursively evaluate an AST node."""
        if isinstance(node, NumberNode):
            return node.value
        if isinstance(node, StringNode):
            return node.value
        if isinstance(node, CellRefNode):
            return self.eval_cell_ref(node.ref)
        if isinstance(node, RangeNode):
            return self.eval_range(node)
        if isinstance(node, BinaryOpNode):
            return self.eval_binary(node)
        if isinstance(node, UnaryOpNode):
            return self.eval_unary(node)
        if isinstance(node, FuncCallNode):
            return self.eval_function(node)
        if isinstance(node, ComparisonNode):
            return self.eval_comparison(node)
        raise FormulaError(f"Unknown node type: {type(node).__name__}")

    def eval_cell_ref(self, ref):
        """Resolve a cell reference to its current value."""
        cell = self.sheet.get_cell(ref)
        if cell is None or cell.is_empty():
            return 0
        val = cell.get_display_value()
        if isinstance(val, str):
            try:
                return float(val)
            except (ValueError, TypeError):
                return val
        return val

    def eval_range(self, node):
        """Evaluate a cell range to a list of values.

        Currently handles single-column and single-row ranges.

        For multi-column, multi-row ranges (2D blocks like A1:C3),
        this needs to be extended to iterate over all rows and columns
        and return values in row-major order.
        """
        start = node.start
        end = node.end

        if start.col == end.col:
            # Single-column range (e.g., A1:A5)
            values = []
            for row in range(start.row, end.row + 1):
                ref = CellRef(start.col, row)
                cell = self.sheet.get_cell(ref)
                if cell is not None:
                    values.append(cell.get_numeric_value())
                else:
                    values.append(None)
            return values
        elif start.row == end.row:
            # Single-row range (e.g., A1:C1)
            values = []
            for col in range(start.col, end.col + 1):
                ref = CellRef(col, start.row)
                cell = self.sheet.get_cell(ref)
                if cell is not None:
                    values.append(cell.get_numeric_value())
                else:
                    values.append(None)
            return values
        else:
            # STUB: 2D range evaluation (e.g., A1:C3)
            # TODO: Iterate over all rows from start.row to end.row (inclusive)
            #       and all columns from start.col to end.col (inclusive).
            #       Return values in row-major order (row by row).
            #       For each cell, use cell.get_numeric_value().
            #       If the cell does not exist, append None.
            raise NotImplementedError(
                "2D range evaluation not yet implemented. "
                "Expand this to iterate over all rows and columns in the block, "
                "returning values in row-major order (left-to-right, top-to-bottom)."
            )

    def eval_binary(self, node):
        """Evaluate a binary arithmetic operation."""
        left = self.eval_node(node.left)
        right = self.eval_node(node.right)
        if isinstance(left, str):
            try:
                left = float(left)
            except (ValueError, TypeError):
                raise FormulaError(f"Cannot use string '{left}' in arithmetic")
        if isinstance(right, str):
            try:
                right = float(right)
            except (ValueError, TypeError):
                raise FormulaError(f"Cannot use string '{right}' in arithmetic")
        if node.op == '+':
            return left + right
        elif node.op == '-':
            return left - right
        elif node.op == '*':
            return left * right
        elif node.op == '/':
            if right == 0:
                raise FormulaError("Division by zero")
            return left / right
        raise FormulaError(f"Unknown operator: {node.op}")

    def eval_unary(self, node):
        """Evaluate a unary operation."""
        operand = self.eval_node(node.operand)
        if node.op == '-':
            if isinstance(operand, str):
                try:
                    return -float(operand)
                except (ValueError, TypeError):
                    raise FormulaError(f"Cannot negate string '{operand}'")
            return -operand
        raise FormulaError(f"Unknown unary operator: {node.op}")

    def eval_comparison(self, node):
        """Evaluate a comparison expression."""
        left = self.eval_node(node.left)
        right = self.eval_node(node.right)
        ops = {
            '<': lambda a, b: a < b,
            '>': lambda a, b: a > b,
            '<=': lambda a, b: a <= b,
            '>=': lambda a, b: a >= b,
            '=': lambda a, b: a == b,
            '==': lambda a, b: a == b,
            '<>': lambda a, b: a != b,
            '!=': lambda a, b: a != b,
        }
        if node.op in ops:
            return ops[node.op](left, right)
        raise FormulaError(f"Unknown comparison operator: {node.op}")

    def eval_function(self, node):
        """Evaluate a function call by delegating to the functions module."""
        name = node.name.upper()

        # Evaluate arguments (ranges stay as lists, scalars stay as scalars)
        evaluated_args = []
        for arg in node.args:
            evaluated_args.append(self.eval_node(arg))

        if name == 'SUM':
            return fn.func_sum(evaluated_args)
        elif name == 'MIN':
            return fn.func_min(evaluated_args)
        elif name == 'MAX':
            return fn.func_max(evaluated_args)
        elif name == 'IF':
            # IF is special: uses lazy evaluation on raw AST args
            return fn.func_if(node.args, self)
        elif name == 'VLOOKUP':
            return fn.func_vlookup(evaluated_args)
        elif name == 'COUNTIF':
            return fn.func_countif(evaluated_args)
        elif name == 'AVERAGE':
            return fn.func_average(evaluated_args)
        elif name == 'ROUND':
            return fn.func_round(evaluated_args)
        elif name == 'ABS':
            return fn.func_abs(evaluated_args)
        else:
            raise FormulaError(f"Unknown function: {name}")
PYEOF

# ============================================================
# engine/functions.py  (STUBS S2 S3 S4)
# ============================================================
cat > "$PROJECT_DIR/engine/functions.py" << 'PYEOF'
"""Built-in spreadsheet functions.

Implemented: SUM, MIN, MAX, IF, ROUND, ABS
Stubs:       VLOOKUP, COUNTIF, AVERAGE
"""
from engine.cell import FormulaError


def _flatten_numeric(args):
    """Flatten nested lists of args and extract numeric values."""
    values = []
    for arg in args:
        if isinstance(arg, list):
            for v in arg:
                if v is not None and isinstance(v, (int, float)):
                    values.append(float(v))
        elif isinstance(arg, (int, float)):
            values.append(float(arg))
    return values


# ---- Implemented functions ----

def func_sum(args):
    """SUM: Return the sum of all numeric values."""
    return sum(_flatten_numeric(args))


def func_min(args):
    """MIN: Return the minimum numeric value."""
    values = _flatten_numeric(args)
    return min(values) if values else 0


def func_max(args):
    """MAX: Return the maximum numeric value."""
    values = _flatten_numeric(args)
    return max(values) if values else 0


def func_if(raw_ast_args, evaluator):
    """IF(condition, value_if_true, value_if_false).

    Uses lazy evaluation: only evaluates the branch that is needed.
    """
    if len(raw_ast_args) < 2:
        raise FormulaError("IF requires at least 2 arguments")
    condition = evaluator.eval_node(raw_ast_args[0])
    if condition:
        return evaluator.eval_node(raw_ast_args[1])
    elif len(raw_ast_args) > 2:
        return evaluator.eval_node(raw_ast_args[2])
    return False


def func_round(args):
    """ROUND(value, [digits])."""
    if not args:
        raise FormulaError("ROUND requires at least 1 argument")
    value = args[0]
    digits = int(args[1]) if len(args) > 1 else 0
    return round(float(value), digits)


def func_abs(args):
    """ABS(value)."""
    if not args:
        raise FormulaError("ABS requires 1 argument")
    return abs(float(args[0]))


# ---- Stub functions (to be implemented) ----

def func_vlookup(args):
    """VLOOKUP(lookup_value, table_range, col_index, [match_type])

    Search for lookup_value in the first column of table_range (a 2D list
    of values in row-major order). Return the value from the column at
    col_index (1-based) in the matching row.

    match_type:
      0 = exact match (scan every row, return first match; raise if none)
      1 = approximate match (data must be sorted ascending in the first
          column; find the largest value that is <= lookup_value)

    The table_range argument arrives as a flat list of values. To interpret
    it as a 2D table, you need to know the number of columns. Since the
    evaluator produces a flat row-major list from a RangeNode, the column
    count can be inferred from col_index: the flat list length divided by
    the number of rows gives the column count. However, the simplest
    approach is to accept the range as-is and also receive col_index.

    For this engine, VLOOKUP receives these evaluated arguments:
      args[0] = lookup_value (scalar)
      args[1] = table data (flat list from eval_range, row-major order)
      args[2] = col_index (1-based integer)
      args[3] = match_type (0 or 1, default 1)

    You will need to reshape the flat list into rows. The number of columns
    equals col_index at minimum, but may be larger. A practical approach:
    determine num_cols from the context. Since the caller provides col_index,
    you can iterate the flat list in steps of num_cols.

    Hint: Store the number of columns on the range. Or, since this engine
    passes the flat list, you may need to also pass metadata. A simpler
    approach for this engine: have the evaluator pass (flat_list, num_cols)
    as args[1]. Check evaluator.py to see how args are built.

    ALTERNATIVE SIMPLER APPROACH: Modify eval_function in evaluator.py
    to pass the RangeNode metadata (start/end refs) so you know the
    table dimensions. Or compute num_cols = end.col - start.col + 1.
    """
    raise NotImplementedError(
        "VLOOKUP is not yet implemented. See the docstring above for "
        "the specification. You need to search the first column of "
        "the table for lookup_value and return the value at col_index."
    )


def func_countif(args):
    """COUNTIF(range, criteria)

    Count the number of cells in range that match the criteria.

    args[0] = range values (flat list from eval_range)
    args[1] = criteria (string or number)

    Criteria formats:
      - A plain number (e.g., 42): count cells equal to 42
      - A plain string (e.g., "Engineering"): count cells equal to it
        (case-insensitive string match)
      - A comparison string (e.g., ">100", "<=50", "<>0"):
        parse the operator and numeric threshold, then count cells
        where the numeric comparison holds

    Skip None values (empty cells).
    """
    raise NotImplementedError(
        "COUNTIF is not yet implemented. See the docstring above for "
        "the specification. Parse the criteria string to determine "
        "the comparison operator and threshold, then count matching cells."
    )


def func_average(args):
    """AVERAGE(range_values...)

    Compute the arithmetic mean of all numeric values, skipping
    None and non-numeric entries.

    Divide by the count of numeric values only, NOT by the total
    number of cells in the range.

    args: one or more arguments, each may be a scalar or a list
    """
    raise NotImplementedError(
        "AVERAGE is not yet implemented. Collect all numeric values "
        "from the arguments (skipping None and strings), compute "
        "their sum, and divide by the count of numeric values."
    )
PYEOF

# ============================================================
# engine/dependency.py  (BUG B4)
# ============================================================
cat > "$PROJECT_DIR/engine/dependency.py" << 'PYEOF'
"""Dependency tracking and topological sort for spreadsheet recalculation."""
from engine.cell import CellRef, FormulaError
from engine.parser import (
    parse_formula, CellRefNode, RangeNode,
    BinaryOpNode, UnaryOpNode, FuncCallNode, ComparisonNode
)


def extract_dependencies(formula_str):
    """Extract all cell references that a formula depends on."""
    ast = parse_formula(formula_str)
    refs = set()
    _collect_refs(ast, refs)
    return refs


def _collect_refs(node, refs):
    """Recursively collect CellRef instances from an AST."""
    if isinstance(node, CellRefNode):
        refs.add(node.ref)
    elif isinstance(node, RangeNode):
        for row in range(node.start.row, node.end.row + 1):
            for col in range(node.start.col, node.end.col + 1):
                refs.add(CellRef(col, row))
    elif isinstance(node, BinaryOpNode):
        _collect_refs(node.left, refs)
        _collect_refs(node.right, refs)
    elif isinstance(node, UnaryOpNode):
        _collect_refs(node.operand, refs)
    elif isinstance(node, FuncCallNode):
        for arg in node.args:
            _collect_refs(arg, refs)
    elif isinstance(node, ComparisonNode):
        _collect_refs(node.left, refs)
        _collect_refs(node.right, refs)


def get_evaluation_order(formula_cells):
    """Return formula cells in topological order for evaluation.

    formula_cells: dict mapping CellRef -> Cell (only cells that have formulas)
    Returns: list of CellRef in evaluation order (dependencies first)

    Raises FormulaError if a circular reference is detected.
    """
    # Build adjacency: for each formula cell, which other formula cells
    # does it depend on?
    deps = {}
    formula_refs = set(formula_cells.keys())
    for ref, cell in formula_cells.items():
        try:
            cell_deps = extract_dependencies(cell.formula)
            deps[ref] = cell_deps & formula_refs
        except Exception:
            deps[ref] = set()

    order = []
    visited = set()

    def visit(ref):
        if ref in visited:
            # BUG: This treats ANY revisit as a circular reference.
            # A cell that is depended on by two different formulas will
            # be visited twice and incorrectly flagged as circular.
            # The fix is to use separate "permanent" and "temporary"
            # visited sets (standard DFS topological sort).
            raise FormulaError(f"Circular reference detected involving {ref}")
        visited.add(ref)
        for dep in deps.get(ref, set()):
            if dep in formula_refs:
                visit(dep)
        order.append(ref)

    for ref in formula_cells:
        if ref not in visited:
            visit(ref)

    return order
PYEOF

# ============================================================
# engine/formatter.py
# ============================================================
cat > "$PROJECT_DIR/engine/formatter.py" << 'PYEOF'
"""Number and value formatting for the spreadsheet engine."""


def format_value(value, fmt=None):
    """Format a cell value for display.

    Supported formats:
      None / 'general' - default Python str()
      'number:N'       - N decimal places (e.g., 'number:2' -> '1234.56')
      'percent'        - multiply by 100 and append '%'
      'currency'       - prepend '$' with 2 decimal places
    """
    if value is None:
        return ""

    if fmt is None or fmt == 'general':
        if isinstance(value, float) and value == int(value):
            return str(int(value))
        return str(value)

    if fmt.startswith('number:'):
        decimals = int(fmt.split(':')[1])
        return f"{float(value):.{decimals}f}"

    if fmt == 'percent':
        return f"{float(value) * 100:.1f}%"

    if fmt == 'currency':
        return f"${float(value):,.2f}"

    return str(value)
PYEOF

# ============================================================
# engine/csv_io.py  (BUG B2)
# ============================================================
cat > "$PROJECT_DIR/engine/csv_io.py" << 'PYEOF'
"""CSV import/export for the spreadsheet engine."""
import csv
from engine.cell import Cell, CellRef


def _infer_type(value):
    """Infer the Python type of a string value from CSV.

    Returns int, float, or keeps as string.
    """
    if value is None:
        return None
    if isinstance(value, str) and value == "":
        return None
    # Try integer conversion
    if isinstance(value, str) and value.isdigit():
        return int(value)
    # BUG: Only attempts float conversion when value contains a decimal point.
    # This means whitespace-padded integers like " 85" stay as strings
    # because isdigit() fails (due to the space) and there is no '.' to
    # trigger the float path. The fix is to strip whitespace first, or
    # attempt float() unconditionally.
    if isinstance(value, str) and '.' in value:
        try:
            return float(value)
        except (ValueError, TypeError):
            pass
    return value


def load_csv(sheet, filepath, start_ref=None):
    """Load a CSV file into a sheet starting at the given cell.

    By default loads at A1 (col=0, row=0).
    First row is treated as data (no special header handling).

    Returns the number of rows loaded.
    """
    if start_ref is None:
        start_ref = CellRef(0, 0)

    row_count = 0
    with open(filepath, 'r', newline='') as f:
        reader = csv.reader(f)
        for r, row_data in enumerate(reader):
            for c, val in enumerate(row_data):
                typed_val = _infer_type(val)
                ref = CellRef(start_ref.col + c, start_ref.row + r)
                sheet.set_value(ref, typed_val)
            row_count += 1
    return row_count


def save_csv(sheet, filepath, start_ref, end_ref):
    """Save a rectangular region of the sheet to a CSV file."""
    with open(filepath, 'w', newline='') as f:
        writer = csv.writer(f)
        for row in range(start_ref.row, end_ref.row + 1):
            row_data = []
            for col in range(start_ref.col, end_ref.col + 1):
                cell = sheet.get_cell(CellRef(col, row))
                if cell is not None:
                    val = cell.get_display_value()
                    row_data.append("" if val is None else val)
                else:
                    row_data.append("")
            writer.writerow(row_data)
PYEOF

# ============================================================
# engine/sheet.py
# ============================================================
cat > "$PROJECT_DIR/engine/sheet.py" << 'PYEOF'
"""Sheet: the central spreadsheet data structure."""
from engine.cell import Cell, CellRef, FormulaError


class Sheet:
    """A single worksheet containing cells with values and formulas."""

    def __init__(self):
        self.cells = {}  # (col, row) -> Cell

    def get_cell(self, ref):
        """Get the Cell object at a reference, or None if empty."""
        return self.cells.get((ref.col, ref.row))

    def set_value(self, ref, value):
        """Set a cell to a plain value (no formula)."""
        self.cells[(ref.col, ref.row)] = Cell(raw_value=value)

    def set_formula(self, ref, formula):
        """Set a cell to a formula (string starting with '=')."""
        self.cells[(ref.col, ref.row)] = Cell(formula=formula)

    def get_value(self, ref):
        """Get the display value of a cell."""
        cell = self.get_cell(ref)
        if cell is None:
            return None
        return cell.get_display_value()

    def recalculate(self):
        """Recalculate all formula cells in dependency order."""
        from engine.evaluator import Evaluator
        from engine.dependency import get_evaluation_order

        evaluator = Evaluator(self)

        # Collect formula cells
        formula_cells = {}
        for (col, row), cell in self.cells.items():
            if cell.formula:
                formula_cells[CellRef(col, row)] = cell

        if not formula_cells:
            return

        # Get topological order
        try:
            order = get_evaluation_order(formula_cells)
        except FormulaError as e:
            # Mark all formula cells as having errors
            for cell in formula_cells.values():
                cell.error = str(e)
                cell.computed_value = None
            return

        # Evaluate in dependency order
        for ref in order:
            cell = self.cells.get((ref.col, ref.row))
            if cell and cell.formula:
                try:
                    result = evaluator.evaluate(cell.formula)
                    cell.computed_value = result
                    cell.error = None
                except NotImplementedError as e:
                    cell.error = f"Not implemented: {e}"
                    cell.computed_value = None
                except Exception as e:
                    cell.error = str(e)
                    cell.computed_value = None
PYEOF

# ============================================================
# Data files
# ============================================================
cat > "$PROJECT_DIR/data/sales_data.csv" << 'CSVEOF'
Date,Product,Region,Quantity,UnitPrice,Discount
2024-01-05,Widget A,North,150,24.99,0.05
2024-01-12,Gadget Pro,South, 85,42.50,0.10
2024-01-19,Sensor X,East,200,15.75,0.00
2024-02-02,Widget A,West,90,24.99,0.08
2024-02-14,Module Z,North,45,89.99,0.15
2024-02-28,Gadget Pro,South,120,42.50,0.05
2024-03-10,Widget B,East,175,31.00,0.00
2024-03-22,Sensor X,North,60,15.75,0.12
2024-04-05,Widget A,South,110,24.99,0.05
2024-04-18,Module Z,West,30,89.99,0.10
2024-05-01,Gadget Pro,East, 95,42.50,0.00
2024-05-15,Widget B,North,140,31.00,0.08
2024-06-01,Sensor X,South,180,15.75,0.05
2024-06-15,Widget A,East,100,24.99,0.00
2024-07-01,Module Z,North,55,89.99,0.10
2024-07-15,Widget B,West,165,31.00,0.05
2024-08-01,Gadget Pro,South,75,42.50,0.15
2024-08-15,Sensor X,East,210,15.75,0.00
2024-09-01,Widget A,North,130,24.99,0.08
2024-09-15,Module Z,South,,89.99,0.05
CSVEOF

cat > "$PROJECT_DIR/data/employees.csv" << 'CSVEOF'
Name,Department,Salary,HireDate,Rating
Alice Chen,Engineering,95000,2019-03-15,4.2
Bob Martinez,Marketing,72000,2020-07-01,3.8
Carol White,Engineering,105000,2018-11-20,4.5
David Kim,Sales,68000,2021-01-10,3.5
Eva Patel,Engineering,,2022-05-15,4.0
Frank Zhou,Marketing,75000,2019-09-01,3.9
Grace Lee,Sales,71000,2020-03-20,4.1
Henry Brown,Engineering,112000,2017-06-01,4.7
Iris Davis,Marketing,69000,2021-08-15,3.6
Jack Wilson,Sales,82000,2019-12-01,4.3
Kate Adams,Engineering,98000,2020-01-15,4.4
Leo Turner,Sales,73000,2022-02-01,3.7
CSVEOF

# ============================================================
# Test infrastructure
# ============================================================
touch "$PROJECT_DIR/tests/__init__.py"

cat > "$PROJECT_DIR/tests/conftest.py" << 'PYEOF'
"""Shared fixtures for spreadsheet engine tests."""
import pytest
from engine.sheet import Sheet
from engine.cell import CellRef


@pytest.fixture
def empty_sheet():
    """Return a fresh, empty Sheet."""
    return Sheet()


@pytest.fixture
def simple_sheet():
    """Return a Sheet with some values pre-loaded in column A."""
    sheet = Sheet()
    for i, v in enumerate([10, 20, 30, 40, 50]):
        sheet.set_value(CellRef(0, i), v)
    return sheet
PYEOF

# ============================================================
# Test files
# ============================================================
cat > "$PROJECT_DIR/tests/test_cell.py" << 'PYEOF'
"""Tests for engine/cell.py"""
from engine.cell import Cell, CellRef


def test_cell_creation():
    """Basic cell creation with a value."""
    cell = Cell(raw_value=42)
    assert cell.raw_value == 42
    assert cell.formula is None
    assert cell.get_display_value() == 42


def test_cell_formula_storage():
    """Cell can store a formula string."""
    cell = Cell(formula="=A1+B1")
    assert cell.formula == "=A1+B1"
    assert cell.raw_value is None


def test_cell_type_coercion():
    """get_numeric_value handles various types."""
    assert Cell(raw_value=42).get_numeric_value() == 42.0
    assert Cell(raw_value=3.14).get_numeric_value() == 3.14
    assert Cell(raw_value="100").get_numeric_value() == 100.0
    assert Cell(raw_value="hello").get_numeric_value() is None


def test_empty_cell_returns_none():
    """Empty cells should return None from get_numeric_value,
    not 0, so that aggregate functions like AVERAGE can skip them."""
    empty = Cell()
    assert empty.is_empty() is True
    assert empty.get_numeric_value() is None  # BUG B3 causes this to return 0

    blank = Cell(raw_value="")
    assert blank.is_empty() is True
    assert blank.get_numeric_value() is None  # BUG B3 causes this to return 0
PYEOF

cat > "$PROJECT_DIR/tests/test_parser.py" << 'PYEOF'
"""Tests for engine/parser.py"""
from engine.parser import parse_formula, NumberNode, CellRefNode, RangeNode, BinaryOpNode, FuncCallNode


def test_parse_number():
    """Parse a simple number."""
    ast = parse_formula("=42")
    assert isinstance(ast, NumberNode)
    assert ast.value == 42.0


def test_parse_cell_reference():
    """Parse a cell reference like A1."""
    ast = parse_formula("=A1")
    assert isinstance(ast, CellRefNode)
    assert ast.ref.col == 0
    assert ast.ref.row == 0


def test_parse_function_call():
    """Parse a function call like SUM(A1:A5)."""
    ast = parse_formula("=SUM(A1:A5)")
    assert isinstance(ast, FuncCallNode)
    assert ast.name == "SUM"
    assert len(ast.args) == 1
    assert isinstance(ast.args[0], RangeNode)


def test_operator_precedence():
    """Multiplication should bind tighter than addition.

    2+3*4 should parse as 2+(3*4) giving an AST where * is nested
    inside +, NOT (2+3)*4.
    """
    ast = parse_formula("=2+3*4")
    # The top-level node should be addition
    assert isinstance(ast, BinaryOpNode)
    assert ast.op == '+'
    # The right child should be multiplication
    assert isinstance(ast.right, BinaryOpNode)
    assert ast.right.op == '*'
PYEOF

cat > "$PROJECT_DIR/tests/test_evaluator.py" << 'PYEOF'
"""Tests for engine/evaluator.py"""
from engine.sheet import Sheet
from engine.cell import CellRef
from engine.evaluator import Evaluator


def test_eval_arithmetic():
    """Evaluate simple arithmetic: 2+3 = 5."""
    sheet = Sheet()
    ev = Evaluator(sheet)
    assert ev.evaluate("=2+3") == 5.0


def test_eval_cell_reference():
    """Evaluate a cell reference."""
    sheet = Sheet()
    sheet.set_value(CellRef(0, 0), 42)
    ev = Evaluator(sheet)
    assert ev.evaluate("=A1") == 42


def test_eval_precedence():
    """2+3*4 should evaluate to 14, not 20."""
    sheet = Sheet()
    ev = Evaluator(sheet)
    result = ev.evaluate("=2+3*4")
    assert result == 14.0, f"Expected 14.0 but got {result} (precedence bug)"


def test_eval_2d_range():
    """Evaluating a 2D range like A1:B2 should return all values."""
    sheet = Sheet()
    sheet.set_value(CellRef(0, 0), 1)   # A1
    sheet.set_value(CellRef(1, 0), 2)   # B1
    sheet.set_value(CellRef(0, 1), 3)   # A2
    sheet.set_value(CellRef(1, 1), 4)   # B2
    ev = Evaluator(sheet)
    values = ev.evaluate("=A1:B2")
    # Row-major order: A1, B1, A2, B2
    assert values == [1.0, 2.0, 3.0, 4.0], f"Got {values}"
PYEOF

cat > "$PROJECT_DIR/tests/test_functions.py" << 'PYEOF'
"""Tests for engine/functions.py (via evaluator)."""
from engine.sheet import Sheet
from engine.cell import CellRef
from engine.evaluator import Evaluator


def _make_column_sheet(values):
    """Helper: create a sheet with values in column A."""
    sheet = Sheet()
    for i, v in enumerate(values):
        if v is not None:
            sheet.set_value(CellRef(0, i), v)
    return sheet


def test_sum_1d():
    """SUM of a single-column range."""
    sheet = _make_column_sheet([10, 20, 30, 40, 50])
    ev = Evaluator(sheet)
    assert ev.evaluate("=SUM(A1:A5)") == 150.0


def test_min_max():
    """MIN and MAX of a single-column range."""
    sheet = _make_column_sheet([30, 10, 50, 20, 40])
    ev = Evaluator(sheet)
    assert ev.evaluate("=MIN(A1:A5)") == 10.0
    assert ev.evaluate("=MAX(A1:A5)") == 50.0


def test_if_function():
    """IF with true and false branches."""
    sheet = Sheet()
    sheet.set_value(CellRef(0, 0), 15)
    ev = Evaluator(sheet)
    assert ev.evaluate('=IF(A1>10, "high", "low")') == "high"
    sheet.set_value(CellRef(0, 0), 5)
    assert ev.evaluate('=IF(A1>10, "high", "low")') == "low"


def test_vlookup_exact():
    """VLOOKUP with exact match on a product table."""
    sheet = Sheet()
    # Table A1:C3 (product, price, stock)
    sheet.set_value(CellRef(0, 0), "Widget A")
    sheet.set_value(CellRef(1, 0), 24.99)
    sheet.set_value(CellRef(2, 0), 100)
    sheet.set_value(CellRef(0, 1), "Gadget Pro")
    sheet.set_value(CellRef(1, 1), 42.50)
    sheet.set_value(CellRef(2, 1), 50)
    sheet.set_value(CellRef(0, 2), "Sensor X")
    sheet.set_value(CellRef(1, 2), 15.75)
    sheet.set_value(CellRef(2, 2), 200)
    ev = Evaluator(sheet)
    result = ev.evaluate('=VLOOKUP("Gadget Pro", A1:C3, 2, 0)')
    assert result == 42.50


def test_countif_numeric():
    """COUNTIF with a numeric comparison criterion."""
    sheet = _make_column_sheet([10, 25, 30, 5, 50, 15])
    ev = Evaluator(sheet)
    result = ev.evaluate('=COUNTIF(A1:A6, ">20")')
    assert result == 3  # 25, 30, 50


def test_average_with_blanks():
    """AVERAGE should skip empty cells in the denominator."""
    sheet = Sheet()
    sheet.set_value(CellRef(0, 0), 10)
    # A2 is empty (not set)
    sheet.set_value(CellRef(0, 2), 30)
    sheet.set_value(CellRef(0, 3), 40)
    ev = Evaluator(sheet)
    # Average of [10, 30, 40] = 80/3 ≈ 26.667, NOT 80/4 = 20
    result = ev.evaluate("=AVERAGE(A1:A4)")
    assert abs(result - 26.667) < 0.01, f"Expected ~26.667, got {result}"


def test_sum_2d():
    """SUM over a 2D range A1:B2."""
    sheet = Sheet()
    sheet.set_value(CellRef(0, 0), 1)   # A1
    sheet.set_value(CellRef(1, 0), 2)   # B1
    sheet.set_value(CellRef(0, 1), 3)   # A2
    sheet.set_value(CellRef(1, 1), 4)   # B2
    ev = Evaluator(sheet)
    result = ev.evaluate("=SUM(A1:B2)")
    assert result == 10.0
PYEOF

cat > "$PROJECT_DIR/tests/test_dependency.py" << 'PYEOF'
"""Tests for engine/dependency.py"""
import pytest
from engine.cell import Cell, CellRef, FormulaError
from engine.dependency import get_evaluation_order


def test_basic_dependency():
    """Simple chain: A1 depends on B1."""
    cells = {
        CellRef(0, 0): Cell(formula="=B1+1"),
        CellRef(1, 0): Cell(formula="=10"),
    }
    order = get_evaluation_order(cells)
    a1_idx = order.index(CellRef(0, 0))
    b1_idx = order.index(CellRef(1, 0))
    assert b1_idx < a1_idx, "B1 should be evaluated before A1"


def test_circular_detection():
    """Genuinely circular references should raise FormulaError."""
    cells = {
        CellRef(0, 0): Cell(formula="=B1+1"),
        CellRef(1, 0): Cell(formula="=A1+1"),
    }
    with pytest.raises(FormulaError, match="[Cc]ircular"):
        get_evaluation_order(cells)


def test_no_false_circular():
    """Two formulas depending on the same cell must NOT be flagged as circular.

    A1=C1*2, B1=C1+10, C1=10: C1 is depended on by both A1 and B1.
    This should NOT raise a circular reference error.
    """
    cells = {
        CellRef(0, 0): Cell(formula="=C1*2"),
        CellRef(1, 0): Cell(formula="=C1+10"),
        CellRef(2, 0): Cell(formula="=10"),
    }
    # Should not raise
    order = get_evaluation_order(cells)
    c1_idx = order.index(CellRef(2, 0))
    a1_idx = order.index(CellRef(0, 0))
    b1_idx = order.index(CellRef(1, 0))
    assert c1_idx < a1_idx, "C1 should come before A1"
    assert c1_idx < b1_idx, "C1 should come before B1"
PYEOF

cat > "$PROJECT_DIR/tests/test_formatter.py" << 'PYEOF'
"""Tests for engine/formatter.py"""
from engine.formatter import format_value


def test_number_format():
    """Format with decimal places."""
    assert format_value(3.14159, 'number:2') == '3.14'
    assert format_value(1000, 'number:0') == '1000'
    assert format_value(42, 'general') == '42'


def test_percentage_format():
    """Format as percentage."""
    assert format_value(0.75, 'percent') == '75.0%'
    assert format_value(1.0, 'percent') == '100.0%'


def test_currency_format():
    """Format as currency."""
    assert format_value(1234.5, 'currency') == '$1,234.50'
    assert format_value(99, 'currency') == '$99.00'
PYEOF

cat > "$PROJECT_DIR/tests/test_csv_io.py" << 'PYEOF'
"""Tests for engine/csv_io.py"""
import os
import tempfile
from engine.sheet import Sheet
from engine.cell import CellRef
from engine.csv_io import load_csv, save_csv


def test_load_csv_basic():
    """Load a simple CSV and check cell values."""
    csv_content = "Name,Age\nAlice,30\nBob,25\n"
    with tempfile.NamedTemporaryFile(mode='w', suffix='.csv', delete=False) as f:
        f.write(csv_content)
        f.flush()
        sheet = Sheet()
        load_csv(sheet, f.name)
    os.unlink(f.name)
    assert sheet.get_value(CellRef(0, 0)) == "Name"
    assert sheet.get_value(CellRef(1, 0)) == "Age"
    assert sheet.get_value(CellRef(0, 1)) == "Alice"
    assert sheet.get_value(CellRef(1, 1)) == 30


def test_type_inference_whitespace():
    """Values with leading/trailing whitespace should be parsed as numbers."""
    csv_content = "A,B\n 85, 95\n42,100\n"
    with tempfile.NamedTemporaryFile(mode='w', suffix='.csv', delete=False) as f:
        f.write(csv_content)
        f.flush()
        sheet = Sheet()
        load_csv(sheet, f.name)
    os.unlink(f.name)
    # " 85" should become int 85, not stay as string " 85"
    val = sheet.get_value(CellRef(0, 1))
    assert isinstance(val, (int, float)), f"Expected numeric, got {type(val)}: {val!r}"
    assert val == 85


def test_save_csv():
    """Save a sheet region to CSV and verify content."""
    sheet = Sheet()
    sheet.set_value(CellRef(0, 0), "X")
    sheet.set_value(CellRef(1, 0), "Y")
    sheet.set_value(CellRef(0, 1), 10)
    sheet.set_value(CellRef(1, 1), 20)
    with tempfile.NamedTemporaryFile(mode='r', suffix='.csv', delete=False) as f:
        save_csv(sheet, f.name, CellRef(0, 0), CellRef(1, 1))
        content = open(f.name).read()
    os.unlink(f.name)
    lines = content.strip().split('\n')
    assert len(lines) == 2
    assert 'X' in lines[0] and 'Y' in lines[0]
    assert '10' in lines[1] and '20' in lines[1]
PYEOF

cat > "$PROJECT_DIR/tests/test_integration.py" << 'PYEOF'
"""Integration tests for the spreadsheet engine.

These test complete workflows: create sheet, set values and formulas,
recalculate, and verify results.
"""
from engine.sheet import Sheet
from engine.cell import CellRef


def test_simple_addition():
    """Simple formula using cell references with addition only."""
    sheet = Sheet()
    sheet.set_value(CellRef(0, 0), 10)   # A1 = 10
    sheet.set_value(CellRef(1, 0), 20)   # B1 = 20
    sheet.set_formula(CellRef(2, 0), "=A1+B1")  # C1 = A1+B1
    sheet.recalculate()
    assert sheet.get_value(CellRef(2, 0)) == 30


def test_precedence_formula():
    """Formula with mixed addition and multiplication."""
    sheet = Sheet()
    sheet.set_value(CellRef(0, 0), 2)    # A1 = 2
    sheet.set_value(CellRef(1, 0), 3)    # B1 = 3
    sheet.set_value(CellRef(2, 0), 4)    # C1 = 4
    sheet.set_formula(CellRef(3, 0), "=A1+B1*C1")  # D1 = A1+B1*C1
    sheet.recalculate()
    val = sheet.get_value(CellRef(3, 0))
    assert val == 14, f"Expected 2+3*4=14, got {val}"


def test_sum_across_columns():
    """SUM over a 2D range spanning multiple columns."""
    sheet = Sheet()
    sheet.set_value(CellRef(0, 0), 1)   # A1
    sheet.set_value(CellRef(1, 0), 2)   # B1
    sheet.set_value(CellRef(2, 0), 3)   # C1
    sheet.set_value(CellRef(0, 1), 4)   # A2
    sheet.set_value(CellRef(1, 1), 5)   # B2
    sheet.set_value(CellRef(2, 1), 6)   # C2
    sheet.set_formula(CellRef(0, 3), "=SUM(A1:C2)")  # A4
    sheet.recalculate()
    val = sheet.get_value(CellRef(0, 3))
    assert val == 21, f"Expected SUM(1..6)=21, got {val}"


def test_vlookup_product_price():
    """VLOOKUP to find a product's price from a lookup table."""
    sheet = Sheet()
    sheet.set_value(CellRef(0, 0), "Widget A")
    sheet.set_value(CellRef(1, 0), 24.99)
    sheet.set_value(CellRef(2, 0), 100)
    sheet.set_value(CellRef(0, 1), "Gadget Pro")
    sheet.set_value(CellRef(1, 1), 42.50)
    sheet.set_value(CellRef(2, 1), 50)
    sheet.set_value(CellRef(0, 2), "Sensor X")
    sheet.set_value(CellRef(1, 2), 15.75)
    sheet.set_value(CellRef(2, 2), 200)
    sheet.set_formula(CellRef(4, 0), '=VLOOKUP("Sensor X", A1:C3, 2, 0)')
    sheet.recalculate()
    val = sheet.get_value(CellRef(4, 0))
    assert val == 15.75, f"Expected 15.75, got {val}"


def test_countif_threshold():
    """COUNTIF to count values above a threshold."""
    sheet = Sheet()
    for i, v in enumerate([10, 25, 30, 5, 50, 15]):
        sheet.set_value(CellRef(0, i), v)
    sheet.set_formula(CellRef(1, 0), '=COUNTIF(A1:A6, ">20")')
    sheet.recalculate()
    val = sheet.get_value(CellRef(1, 0))
    assert val == 3, f"Expected 3 values > 20, got {val}"


def test_average_salary():
    """AVERAGE of a column with some blank cells."""
    sheet = Sheet()
    salaries = [95000, 72000, 105000, 68000, None, 75000]
    for i, v in enumerate(salaries):
        if v is not None:
            sheet.set_value(CellRef(0, i), v)
    sheet.set_formula(CellRef(1, 0), "=AVERAGE(A1:A6)")
    sheet.recalculate()
    val = sheet.get_value(CellRef(1, 0))
    expected = (95000 + 72000 + 105000 + 68000 + 75000) / 5  # 83000.0
    assert abs(val - expected) < 0.01, f"Expected {expected}, got {val}"


def test_full_report():
    """A mini dashboard combining SUM, AVERAGE, COUNTIF, and precedence."""
    sheet = Sheet()
    # Sales data in A1:B5
    products = ["Widget A", "Gadget Pro", "Sensor X", "Widget B", "Module Z"]
    revenues = [2499, 4250, 1575, 3100, 8999]
    for i, (p, r) in enumerate(zip(products, revenues)):
        sheet.set_value(CellRef(0, i), p)
        sheet.set_value(CellRef(1, i), r)

    sheet.set_formula(CellRef(3, 0), "=SUM(B1:B5)")            # Total revenue
    sheet.set_formula(CellRef(3, 1), "=AVERAGE(B1:B5)")         # Average revenue
    sheet.set_formula(CellRef(3, 2), '=COUNTIF(B1:B5, ">3000")')  # High-value count
    sheet.set_formula(CellRef(3, 3), "=SUM(B1:B5)*1.1")         # Revenue + 10% (precedence)
    sheet.recalculate()

    assert sheet.get_value(CellRef(3, 0)) == 20423
    avg = sheet.get_value(CellRef(3, 1))
    assert abs(avg - 4084.6) < 0.1
    assert sheet.get_value(CellRef(3, 2)) == 3  # 4250, 3100, 8999
    projected = sheet.get_value(CellRef(3, 3))
    assert abs(projected - 22465.3) < 0.1
PYEOF

# ============================================================
# requirements.txt
# ============================================================
cat > "$PROJECT_DIR/requirements.txt" << 'REQEOF'
pytest>=7.0
REQEOF

# Set ownership
chown -R ga:ga "$PROJECT_DIR"

# Install dependencies
echo "Installing Python dependencies..."
su - ga -c "pip3 install --quiet pytest 2>&1 | tail -3" || true

# PyCharm .idea project files
mkdir -p "$PROJECT_DIR/.idea"

cat > "$PROJECT_DIR/.idea/.gitignore" << 'GIEOF'
# Default ignored files
/shelf/
/workspace.xml
GIEOF

cat > "$PROJECT_DIR/.idea/misc.xml" << 'XML'
<?xml version="1.0" encoding="UTF-8"?>
<project version="4">
  <component name="Black">
    <option name="sdkName" value="Python 3.11" />
  </component>
  <component name="ProjectRootManager" version="2" project-jdk-name="Python 3.11" project-jdk-type="Python SDK" />
</project>
XML

cat > "$PROJECT_DIR/.idea/modules.xml" << 'XML'
<?xml version="1.0" encoding="UTF-8"?>
<project version="4">
  <component name="ProjectModuleManager">
    <modules>
      <module fileurl="file://$PROJECT_DIR$/spreadsheet_engine.iml" filepath="$PROJECT_DIR$/spreadsheet_engine.iml" />
    </modules>
  </component>
</project>
XML

cat > "$PROJECT_DIR/.idea/spreadsheet_engine.iml" << 'XML'
<?xml version="1.0" encoding="UTF-8"?>
<module type="PYTHON_MODULE" version="4">
  <component name="NewModuleRootManager">
    <content url="file://$MODULE_DIR$" />
    <orderEntry type="inheritedJdk" />
    <orderEntry type="sourceFolder" forTests="false" />
  </component>
</module>
XML

chown -R ga:ga "$PROJECT_DIR/.idea"

# Record start timestamp
date +%s > /tmp/${TASK_NAME}_start_ts

# Open in PyCharm
echo "Opening project in PyCharm..."
if type setup_pycharm_project &>/dev/null; then
    setup_pycharm_project "$PROJECT_DIR"
else
    su - ga -c "DISPLAY=:1 /opt/pycharm/bin/pycharm.sh '$PROJECT_DIR' >> /home/ga/pycharm.log 2>&1 &"
    sleep 15
fi

sleep 2
DISPLAY=:1 import -window root /tmp/${TASK_NAME}_start_screenshot.png 2>/dev/null || \
    DISPLAY=:1 scrot /tmp/${TASK_NAME}_start_screenshot.png 2>/dev/null || true

echo "=== Setup complete ==="
echo "Project at: $PROJECT_DIR"
echo "Tests: 35 total, 19 expected to pass initially"
