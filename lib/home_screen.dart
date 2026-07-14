import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

import 'crop_screen.dart';
import 'ocr_service.dart';
import 'solver.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _picker = ImagePicker();

  /// Current board, 0 = empty.
  var _grid = List.generate(9, (_) => List.filled(9, 0));

  /// True for clues (scanned or typed), false for solver-filled cells.
  var _given = List.generate(9, (_) => List.filled(9, false));

  int? _selectedRow;
  int? _selectedCol;
  var _busy = false;
  var _solved = false;

  // ---------------------------------------------------------------- actions

  Future<void> _scan(ImageSource source) async {
    final XFile? shot;
    try {
      shot = await _picker.pickImage(source: source, maxWidth: 2400);
    } catch (e) {
      _toast('Could not open ${source == ImageSource.camera ? "camera" : "gallery"}: $e');
      return;
    }
    if (shot == null || !mounted) return;

    final bytes = await shot.readAsBytes();
    if (!mounted) return;
    final cropped = await Navigator.of(context).push<Uint8List>(
      MaterialPageRoute(builder: (_) => CropScreen(imageBytes: bytes)),
    );
    if (cropped == null || !mounted) return;

    setState(() => _busy = true);
    try {
      final dir = await getTemporaryDirectory();
      final file = File(
          '${dir.path}/sudoku_${DateTime.now().millisecondsSinceEpoch}.png');
      await file.writeAsBytes(cropped);

      final grid = await OcrService.readGrid(file);
      await file.delete();

      setState(() {
        _grid = grid;
        _given = [
          for (final row in grid) [for (final v in row) v != 0],
        ];
        _solved = false;
        _selectedRow = null;
        _selectedCol = null;
      });
      final count =
          grid.expand((r) => r).where((v) => v != 0).length;
      _toast('Read $count digits — check the grid, then tap Solve.');
    } catch (e) {
      _toast(e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _solve() {
    final clues = _grid.expand((r) => r).where((v) => v != 0).length;
    if (clues < 8) {
      _toast('Enter at least a few clues first (found $clues).');
      return;
    }
    if (!SudokuSolver.isValid(_grid)) {
      _toast('The grid has conflicts (shown in red) — fix them first.');
      return;
    }
    final solution = SudokuSolver.solve(_grid);
    if (solution == null) {
      _toast('This puzzle has no solution — a digit is probably misread.');
      return;
    }
    setState(() {
      _grid = solution;
      _solved = true;
      _selectedRow = null;
      _selectedCol = null;
    });
  }

  void _clear() {
    setState(() {
      _grid = List.generate(9, (_) => List.filled(9, 0));
      _given = List.generate(9, (_) => List.filled(9, false));
      _solved = false;
      _selectedRow = null;
      _selectedCol = null;
    });
  }

  void _enterDigit(int digit) {
    final r = _selectedRow, c = _selectedCol;
    if (r == null || c == null) {
      _toast('Tap a cell first.');
      return;
    }
    setState(() {
      if (_solved) {
        // Editing after a solve: keep only the clues, restart from them.
        for (var i = 0; i < 9; i++) {
          for (var j = 0; j < 9; j++) {
            if (!_given[i][j]) _grid[i][j] = 0;
          }
        }
        _solved = false;
      }
      _grid[r][c] = digit;
      _given[r][c] = digit != 0;
    });
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  // ------------------------------------------------------------------- UI

  @override
  Widget build(BuildContext context) {
    final conflicted = <int>{};
    for (var r = 0; r < 9; r++) {
      for (var c = 0; c < 9; c++) {
        if (_grid[r][c] != 0 &&
            SudokuSolver.conflicts(_grid, r, c).isNotEmpty) {
          conflicted.add(r * 9 + c);
        }
      }
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Sudoku Solver'),
        centerTitle: true,
        actions: [
          IconButton(
            tooltip: 'Clear board',
            onPressed: _busy ? null : _clear,
            icon: const Icon(Icons.delete_outline),
          ),
        ],
      ),
      body: SafeArea(
        child: Stack(
          children: [
            Column(
              children: [
                Expanded(
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: AspectRatio(
                        aspectRatio: 1,
                        child: _buildGrid(conflicted),
                      ),
                    ),
                  ),
                ),
                _buildNumberPad(),
                _buildActionBar(),
              ],
            ),
            if (_busy)
              Positioned.fill(
                child: ColoredBox(
                  color: Colors.black45,
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: const [
                        CircularProgressIndicator(),
                        SizedBox(height: 12),
                        Text('Reading the puzzle…',
                            style: TextStyle(color: Colors.white)),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildGrid(Set<int> conflicted) {
    final scheme = Theme.of(context).colorScheme;
    final thick = BorderSide(color: scheme.onSurface, width: 2);
    final thin = BorderSide(color: scheme.outlineVariant, width: 0.6);

    return Container(
      decoration: BoxDecoration(border: Border.fromBorderSide(thick)),
      child: Column(
        children: [
          for (var r = 0; r < 9; r++)
            Expanded(
              child: Row(
                children: [
                  for (var c = 0; c < 9; c++)
                    Expanded(child: _buildCell(r, c, conflicted, thick, thin)),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildCell(
      int r, int c, Set<int> conflicted, BorderSide thick, BorderSide thin) {
    final scheme = Theme.of(context).colorScheme;
    final value = _grid[r][c];
    final selected = r == _selectedRow && c == _selectedCol;
    final inConflict = conflicted.contains(r * 9 + c);

    Color? background;
    if (selected) {
      background = scheme.primaryContainer;
    } else if (_selectedRow == r || _selectedCol == c) {
      background = scheme.surfaceContainerHighest.withValues(alpha: 0.5);
    }

    return GestureDetector(
      onTap: _busy
          ? null
          : () => setState(() {
                _selectedRow = r;
                _selectedCol = c;
              }),
      child: Container(
        decoration: BoxDecoration(
          color: background,
          border: Border(
            right: c == 8 ? BorderSide.none : (c % 3 == 2 ? thick : thin),
            bottom: r == 8 ? BorderSide.none : (r % 3 == 2 ? thick : thin),
          ),
        ),
        alignment: Alignment.center,
        child: value == 0
            ? null
            : FittedBox(
                child: Padding(
                  padding: const EdgeInsets.all(6),
                  child: Text(
                    '$value',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight:
                          _given[r][c] ? FontWeight.w700 : FontWeight.w400,
                      color: inConflict
                          ? scheme.error
                          : _given[r][c]
                              ? scheme.onSurface
                              : scheme.primary,
                    ),
                  ),
                ),
              ),
      ),
    );
  }

  Widget _buildNumberPad() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          for (var d = 1; d <= 9; d++)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(2),
                child: OutlinedButton(
                  onPressed: _busy ? null : () => _enterDigit(d),
                  style: OutlinedButton.styleFrom(
                    padding: EdgeInsets.zero,
                    minimumSize: const Size(0, 44),
                  ),
                  child: Text('$d', style: const TextStyle(fontSize: 18)),
                ),
              ),
            ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(2),
              child: OutlinedButton(
                onPressed: _busy ? null : () => _enterDigit(0),
                style: OutlinedButton.styleFrom(
                  padding: EdgeInsets.zero,
                  minimumSize: const Size(0, 44),
                ),
                child: const Icon(Icons.backspace_outlined, size: 18),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      child: Row(
        children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: _busy ? null : () => _scan(ImageSource.camera),
              icon: const Icon(Icons.photo_camera_outlined),
              label: const Text('Camera'),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(0, 48),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: OutlinedButton.icon(
              onPressed: _busy ? null : () => _scan(ImageSource.gallery),
              icon: const Icon(Icons.photo_library_outlined),
              label: const Text('Upload'),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(0, 48),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: FilledButton.icon(
              onPressed: _busy || _solved ? null : _solve,
              icon: const Icon(Icons.auto_awesome),
              label: Text(_solved ? 'Solved' : 'Solve'),
              style: FilledButton.styleFrom(
                minimumSize: const Size(0, 48),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
