/// Classic 9x9 Sudoku solving and validation logic.
class SudokuSolver {
  /// Returns a solved copy of [grid] (0 = empty), or null when unsolvable.
  static List<List<int>>? solve(List<List<int>> grid) {
    if (!isValid(grid)) return null;
    final board = [
      for (final row in grid) [...row],
    ];
    return _backtrack(board) ? board : null;
  }

  static bool _backtrack(List<List<int>> board) {
    int bestRow = -1, bestCol = -1, bestCount = 10;
    List<int>? bestCandidates;

    // Pick the empty cell with the fewest candidates.
    for (var r = 0; r < 9; r++) {
      for (var c = 0; c < 9; c++) {
        if (board[r][c] != 0) continue;
        final candidates = <int>[
          for (var v = 1; v <= 9; v++)
            if (_canPlace(board, r, c, v)) v,
        ];
        if (candidates.isEmpty) return false;
        if (candidates.length < bestCount) {
          bestRow = r;
          bestCol = c;
          bestCount = candidates.length;
          bestCandidates = candidates;
        }
      }
    }
    if (bestRow == -1) return true; // no empty cells left

    for (final v in bestCandidates!) {
      board[bestRow][bestCol] = v;
      if (_backtrack(board)) return true;
      board[bestRow][bestCol] = 0;
    }
    return false;
  }

  static bool _canPlace(List<List<int>> board, int row, int col, int value) {
    for (var i = 0; i < 9; i++) {
      if (board[row][i] == value || board[i][col] == value) return false;
    }
    final br = row - row % 3, bc = col - col % 3;
    for (var r = br; r < br + 3; r++) {
      for (var c = bc; c < bc + 3; c++) {
        if (board[r][c] == value) return false;
      }
    }
    return true;
  }

  /// True when no filled cell conflicts with another.
  static bool isValid(List<List<int>> grid) {
    for (var r = 0; r < 9; r++) {
      for (var c = 0; c < 9; c++) {
        if (grid[r][c] != 0 && conflicts(grid, r, c).isNotEmpty) return false;
      }
    }
    return true;
  }

  /// Cells (as row*9+col) that clash with the value at [row],[col].
  static Set<int> conflicts(List<List<int>> grid, int row, int col) {
    final value = grid[row][col];
    final result = <int>{};
    if (value == 0) return result;
    for (var i = 0; i < 9; i++) {
      if (i != col && grid[row][i] == value) result.add(row * 9 + i);
      if (i != row && grid[i][col] == value) result.add(i * 9 + col);
    }
    final br = row - row % 3, bc = col - col % 3;
    for (var r = br; r < br + 3; r++) {
      for (var c = bc; c < bc + 3; c++) {
        if ((r != row || c != col) && grid[r][c] == value) {
          result.add(r * 9 + c);
        }
      }
    }
    return result;
  }
}
