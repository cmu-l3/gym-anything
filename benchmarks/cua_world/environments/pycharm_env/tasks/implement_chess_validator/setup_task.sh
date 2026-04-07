#!/bin/bash
set -e
echo "=== Setting up implement_chess_validator task ==="

source /workspace/scripts/task_utils.sh

PROJECT_DIR="/home/ga/PycharmProjects/chess_validator"

# Clean previous run
rm -rf "$PROJECT_DIR"
rm -f /tmp/chess_validator_result.json /tmp/chess_validator_start_ts

# Create directory structure
mkdir -p "$PROJECT_DIR/chess"
mkdir -p "$PROJECT_DIR/tests"
mkdir -p "$PROJECT_DIR/data"

# --- requirements.txt ---
cat > "$PROJECT_DIR/requirements.txt" << 'EOF'
pytest>=7.0
EOF

# --- chess/__init__.py ---
touch "$PROJECT_DIR/chess/__init__.py"

# --- chess/pieces.py (Complete) ---
cat > "$PROJECT_DIR/chess/pieces.py" << 'EOF'
from dataclasses import dataclass
from enum import Enum
from typing import Optional

class Color(Enum):
    WHITE = "w"
    BLACK = "b"

    @property
    def opponent(self):
        return Color.BLACK if self == Color.WHITE else Color.WHITE

class PieceType(Enum):
    PAWN = "p"
    KNIGHT = "n"
    BISHOP = "b"
    ROOK = "r"
    QUEEN = "q"
    KING = "k"

@dataclass(frozen=True)
class Square:
    file: int  # 0-7 (a-h)
    rank: int  # 0-7 (1-8)

    def __repr__(self):
        return f"{chr(ord('a') + self.file)}{self.rank + 1}"

    def __eq__(self, other):
        return isinstance(other, Square) and self.file == other.file and self.rank == other.rank

@dataclass(frozen=True)
class Move:
    from_sq: Square
    to_sq: Square
    promotion: Optional[PieceType] = None

    def __repr__(self):
        prom = f"={self.promotion.value}" if self.promotion else ""
        return f"{self.from_sq}{self.to_sq}{prom}"

@dataclass
class Piece:
    piece_type: PieceType
    color: Color
EOF

# --- chess/board.py (Complete) ---
cat > "$PROJECT_DIR/chess/board.py" << 'EOF'
from typing import Dict, List, Optional, Tuple
from chess.pieces import Piece, PieceType, Color, Square, Move

class Board:
    def __init__(self, fen: str = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"):
        self.squares: Dict[Tuple[int, int], Piece] = {}
        self.turn = Color.WHITE
        self.castling_rights = "KQkq"
        self.en_passant_target: Optional[Square] = None
        self.halfmove_clock = 0
        self.fullmove_number = 1
        self._parse_fen(fen)

    def _parse_fen(self, fen: str):
        parts = fen.split()
        rows = parts[0].split('/')
        for r, row in enumerate(rows):
            rank = 7 - r
            file = 0
            for char in row:
                if char.isdigit():
                    file += int(char)
                else:
                    color = Color.WHITE if char.isupper() else Color.BLACK
                    ptype = PieceType(char.lower())
                    self.squares[(file, rank)] = Piece(ptype, color)
                    file += 1
        
        self.turn = Color.WHITE if parts[1] == 'w' else Color.BLACK
        self.castling_rights = parts[2]
        if parts[3] != '-':
            f = ord(parts[3][0]) - ord('a')
            r = int(parts[3][1]) - 1
            self.en_passant_target = Square(f, r)
        else:
            self.en_passant_target = None

    def get_piece(self, square: Square) -> Optional[Piece]:
        return self.squares.get((square.file, square.rank))

    def set_piece(self, square: Square, piece: Optional[Piece]):
        if piece is None:
            self.squares.pop((square.file, square.rank), None)
        else:
            self.squares[(square.file, square.rank)] = piece

    def find_king(self, color: Color) -> Square:
        for (f, r), piece in self.squares.items():
            if piece.piece_type == PieceType.KING and piece.color == color:
                return Square(f, r)
        raise ValueError(f"No king found for {color}")

    def get_pieces(self, color: Color) -> List[Tuple[Square, Piece]]:
        res = []
        for (f, r), piece in self.squares.items():
            if piece.color == color:
                res.append((Square(f, r), piece))
        return res

    def copy(self) -> 'Board':
        # Simple deep copy for validation
        new_b = Board("8/8/8/8/8/8/8/8 w - - 0 1")
        new_b.squares = {k: v for k, v in self.squares.items()}
        new_b.turn = self.turn
        new_b.castling_rights = self.castling_rights
        new_b.en_passant_target = self.en_passant_target
        return new_b

    def make_move(self, move: Move) -> 'Board':
        """Returns a new board with the move applied. Does NOT validate legality."""
        new_board = self.copy()
        piece = new_board.get_piece(move.from_sq)
        if not piece:
            return new_board
        
        # Move piece
        new_board.set_piece(move.to_sq, piece)
        new_board.set_piece(move.from_sq, None)

        # Handle Promotion
        if move.promotion:
            new_board.set_piece(move.to_sq, Piece(move.promotion, piece.color))

        # Handle En Passant Capture
        if piece.piece_type == PieceType.PAWN:
            if move.to_sq == self.en_passant_target:
                # Captured pawn is behind the target square
                capture_rank = move.to_sq.rank - 1 if piece.color == Color.WHITE else move.to_sq.rank + 1
                new_board.set_piece(Square(move.to_sq.file, capture_rank), None)

        # Handle Castling
        if piece.piece_type == PieceType.KING:
            # Kingside
            if move.to_sq.file - move.from_sq.file == 2:
                rook_from = Square(7, move.from_sq.rank)
                rook_to = Square(5, move.from_sq.rank)
                rook = new_board.get_piece(rook_from)
                new_board.set_piece(rook_to, rook)
                new_board.set_piece(rook_from, None)
            # Queenside
            elif move.from_sq.file - move.to_sq.file == 2:
                rook_from = Square(0, move.from_sq.rank)
                rook_to = Square(3, move.from_sq.rank)
                rook = new_board.get_piece(rook_from)
                new_board.set_piece(rook_to, rook)
                new_board.set_piece(rook_from, None)

        # Update turn
        new_board.turn = self.turn.opponent
        
        # Update EP Target (only for double pawn push)
        new_board.en_passant_target = None
        if piece.piece_type == PieceType.PAWN and abs(move.to_sq.rank - move.from_sq.rank) == 2:
             mid_rank = (move.from_sq.rank + move.to_sq.rank) // 2
             new_board.en_passant_target = Square(move.from_sq.file, mid_rank)

        # Update castling rights (simple logic)
        rights = new_board.castling_rights
        if piece.piece_type == PieceType.KING:
            if piece.color == Color.WHITE: rights = rights.replace("K", "").replace("Q", "")
            else: rights = rights.replace("k", "").replace("q", "")
        # Remove rights if rooks move or are captured (omitted for brevity in stub)
        new_board.castling_rights = rights if rights else "-"

        return new_board
EOF

# --- chess/moves.py (STUBS) ---
cat > "$PROJECT_DIR/chess/moves.py" << 'EOF'
from typing import List
from chess.pieces import PieceType, Color, Square, Move
from chess.board import Board

def get_pawn_moves(board: Board, square: Square) -> List[Move]:
    """Return all pseudo-legal moves for a pawn at the given square."""
    raise NotImplementedError("TODO: Implement get_pawn_moves")

def get_knight_moves(board: Board, square: Square) -> List[Move]:
    """Return all pseudo-legal moves for a knight at the given square."""
    raise NotImplementedError("TODO: Implement get_knight_moves")

def get_bishop_moves(board: Board, square: Square) -> List[Move]:
    """Return all pseudo-legal moves for a bishop at the given square."""
    raise NotImplementedError("TODO: Implement get_bishop_moves")

def get_rook_moves(board: Board, square: Square) -> List[Move]:
    """Return all pseudo-legal moves for a rook at the given square."""
    raise NotImplementedError("TODO: Implement get_rook_moves")

def get_queen_moves(board: Board, square: Square) -> List[Move]:
    """Return all pseudo-legal moves for a queen at the given square."""
    raise NotImplementedError("TODO: Implement get_queen_moves")

def get_king_moves(board: Board, square: Square) -> List[Move]:
    """Return all pseudo-legal moves for a king at the given square."""
    raise NotImplementedError("TODO: Implement get_king_moves")
EOF

# --- chess/validation.py (STUBS) ---
cat > "$PROJECT_DIR/chess/validation.py" << 'EOF'
from typing import List
from chess.pieces import Color, Square, Move
from chess.board import Board

def is_square_attacked(board: Board, square: Square, by_color: Color) -> bool:
    """Return True if the square is attacked by any piece of the given color."""
    raise NotImplementedError("TODO: Implement is_square_attacked")

def is_in_check(board: Board, color: Color) -> bool:
    """Return True if the king of the given color is currently in check."""
    raise NotImplementedError("TODO: Implement is_in_check")

def get_legal_moves(board: Board) -> List[Move]:
    """Return all legal moves for the side to move."""
    # Hint: Generate pseudo-legal moves for all pieces, then filter those that leave King in check.
    raise NotImplementedError("TODO: Implement get_legal_moves")

def is_checkmate(board: Board) -> bool:
    """Return True if the side to move is in checkmate."""
    raise NotImplementedError("TODO: Implement is_checkmate")

def is_stalemate(board: Board) -> bool:
    """Return True if the side to move is in stalemate."""
    raise NotImplementedError("TODO: Implement is_stalemate")
EOF

# --- tests/conftest.py ---
cat > "$PROJECT_DIR/tests/conftest.py" << 'EOF'
import pytest
from chess.board import Board

@pytest.fixture
def empty_board():
    return Board("8/8/8/8/8/8/8/8 w - - 0 1")

@pytest.fixture
def start_board():
    return Board()
EOF

# --- tests/test_piece_moves.py ---
cat > "$PROJECT_DIR/tests/test_piece_moves.py" << 'EOF'
import pytest
from chess.board import Board
from chess.pieces import Square, Move, PieceType
from chess.moves import get_knight_moves, get_rook_moves

def test_knight_moves_center():
    b = Board("8/8/8/3N4/8/8/8/8 w - - 0 1")
    moves = get_knight_moves(b, Square(3, 4)) # d5
    targets = {m.to_sq for m in moves}
    expected = {
        Square(1, 3), Square(1, 5), Square(2, 2), Square(2, 6),
        Square(4, 2), Square(4, 6), Square(5, 3), Square(5, 5)
    }
    assert targets == expected

def test_rook_moves_blocked():
    # Rook at d4, blocked by own pawn at d6, enemy pawn at d2
    b = Board("8/8/3P4/8/3R4/8/3p4/8 w - - 0 1")
    moves = get_rook_moves(b, Square(3, 3)) # d4
    targets = {m.to_sq for m in moves}
    # d5 (blocked by d6), d3, d2 (capture), plus horizontal
    # Horizontal: a4, b4, c4, e4, f4, g4, h4
    expected = {
        Square(3, 4), Square(3, 2), Square(3, 1), # vertical
        Square(0, 3), Square(1, 3), Square(2, 3), Square(4, 3), Square(5, 3), Square(6, 3), Square(7, 3) # horizontal
    }
    assert targets == expected
EOF

# --- tests/test_pawn_moves.py ---
cat > "$PROJECT_DIR/tests/test_pawn_moves.py" << 'EOF'
import pytest
from chess.board import Board
from chess.pieces import Square, PieceType
from chess.moves import get_pawn_moves

def test_white_pawn_initial():
    b = Board("8/8/8/8/8/8/4P3/8 w - - 0 1")
    moves = get_pawn_moves(b, Square(4, 1)) # e2
    targets = {m.to_sq for m in moves}
    assert Square(4, 2) in targets
    assert Square(4, 3) in targets # Double push

def test_pawn_capture():
    b = Board("8/8/8/8/3p4/2P5/8/8 w - - 0 1")
    moves = get_pawn_moves(b, Square(2, 2)) # c3
    targets = {m.to_sq for m in moves}
    assert Square(3, 3) in targets # Capture d4
    assert Square(2, 3) in targets # Push c4

def test_en_passant():
    # White pawn e5, black pawn d5 (moved d7-d5 previous turn)
    b = Board("rnbqkbnr/ppp1pppp/8/3pP3/8/8/PPPP1PPP/RNBQKBNR w KQkq d6 0 3")
    moves = get_pawn_moves(b, Square(4, 4)) # e5
    targets = {m.to_sq for m in moves}
    assert Square(3, 5) in targets # d6 (en passant)
EOF

# --- tests/test_check.py ---
cat > "$PROJECT_DIR/tests/test_check.py" << 'EOF'
import pytest
from chess.board import Board
from chess.pieces import Color, Square
from chess.validation import is_in_check, get_legal_moves

def test_is_in_check():
    # Black rook at e8 checks White king at e1
    b = Board("4r3/8/8/8/8/8/8/4K3 w - - 0 1")
    assert is_in_check(b, Color.WHITE) == True
    assert is_in_check(b, Color.BLACK) == False

def test_absolute_pin():
    # White King e1, White Rook e2, Black Rook e8. Rook e2 is pinned.
    b = Board("4r3/8/8/8/8/8/4R3/4K3 w - - 0 1")
    legal = get_legal_moves(b)
    # Filter moves for the rook at e2
    rook_moves = [m for m in legal if m.from_sq == Square(4, 1)]
    # Rook can capture e8 or move along file e, but cannot move horizontally
    for m in rook_moves:
        assert m.to_sq.file == 4 
EOF

# --- tests/test_games.py (Integration) ---
cat > "$PROJECT_DIR/tests/test_games.py" << 'EOF'
import pytest
from chess.board import Board
from chess.validation import get_legal_moves, is_checkmate

def test_fools_mate():
    # 1. f3 e5 2. g4 Qh4#
    b = Board()
    moves_str = ["f2f3", "e7e5", "g2g4", "d8h4"]
    
    for m_str in moves_str:
        legal = get_legal_moves(b)
        found = None
        for move in legal:
             # Simple algebraic matching for test
             if str(move) == m_str:
                 found = move
                 break
        assert found is not None, f"Move {m_str} not legal"
        b = b.make_move(found)

    assert is_checkmate(b) == True
EOF

# Record start time
date +%s > /tmp/chess_validator_start_ts

# Wait for PyCharm
wait_for_pycharm 60

# Maximize
focus_pycharm_window

# Initial screenshot
take_screenshot /tmp/task_start.png

echo "=== Setup complete ==="