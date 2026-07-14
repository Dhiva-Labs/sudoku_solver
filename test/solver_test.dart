import 'package:flutter_test/flutter_test.dart';
import 'package:sudoku_solver/solver.dart';

List<List<int>> parse(String puzzle) {
  final digits = puzzle.replaceAll(RegExp(r'\s'), '');
  return List.generate(
      9, (r) => List.generate(9, (c) => int.parse(digits[r * 9 + c])));
}

void main() {
  test('solves a standard puzzle', () {
    final grid = parse('''
      530070000
      600195000
      098000060
      800060003
      400803001
      700020006
      060000280
      000419005
      000080079
    ''');
    final solution = SudokuSolver.solve(grid)!;
    expect(SudokuSolver.isValid(solution), isTrue);
    expect(solution.expand((r) => r).contains(0), isFalse);
    // Given clues must be preserved.
    for (var r = 0; r < 9; r++) {
      for (var c = 0; c < 9; c++) {
        if (grid[r][c] != 0) expect(solution[r][c], grid[r][c]);
      }
    }
    expect(solution[0], [5, 3, 4, 6, 7, 8, 9, 1, 2]);
  });

  test('solves a minimal-clue puzzle quickly', () {
    final grid = parse('''
      000000010
      400000000
      020000000
      000050407
      008000300
      001090000
      300400200
      050100000
      000806000
    ''');
    final watch = Stopwatch()..start();
    final solution = SudokuSolver.solve(grid);
    watch.stop();
    expect(solution, isNotNull);
    expect(SudokuSolver.isValid(solution!), isTrue);
    expect(watch.elapsedMilliseconds, lessThan(2000));
  });

  test('rejects a grid with conflicts', () {
    final grid = List.generate(9, (_) => List.filled(9, 0));
    grid[0][0] = 5;
    grid[0][8] = 5; // same row conflict
    expect(SudokuSolver.isValid(grid), isFalse);
    expect(SudokuSolver.solve(grid), isNull);
    expect(SudokuSolver.conflicts(grid, 0, 0), contains(8));
  });

  test('detects an unsolvable puzzle', () {
    // Row 0 is missing only 9, but column 8 already contains a 9.
    final grid = parse('''
      123456780
      000000000
      000000000
      000000009
      000000000
      000000000
      000000000
      000000000
      000000000
    ''');
    expect(SudokuSolver.isValid(grid), isTrue);
    expect(SudokuSolver.solve(grid), isNull);
  });
}
