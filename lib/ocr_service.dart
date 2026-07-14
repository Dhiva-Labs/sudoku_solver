import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' show Rect;

import 'package:flutter/foundation.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image/image.dart' as img;

/// Reads a cropped photo of a Sudoku grid and returns a 9x9 matrix
/// (0 = empty cell).
///
/// The grid's true bounding box is detected from the strong grid lines
/// (the user's crop is never pixel-perfect), and every recognised digit
/// is assigned to a cell by its position inside that box.
///
/// ML Kit is tuned for lines of text and tends to skip isolated digits,
/// so recognition runs in three passes:
///  1. the whole image at once,
///  2. one pass per row strip (a row reads like a text line),
///  3. per-cell passes for cells that visibly contain ink but still have
///     no digit — the cell is tiled three times so the lone digit looks
///     like a short line of text.
///
/// All CPU-heavy image work is prepared up front in a background isolate;
/// only the ML Kit calls run on the main isolate.
class OcrService {
  static Future<List<List<int>>> readGrid(File croppedImage) async {
    final prep = await compute(_prepareArtifacts, croppedImage.path);
    final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
    final grid = List.generate(9, (_) => List.filled(9, 0));
    try {
      // Pass 1: whole image, digits mapped through the detected grid rect.
      final whole = await recognizer
          .processImage(InputImage.fromFilePath(croppedImage.path));
      _placeAll(whole, grid, prep.gridRect, null);

      // Pass 2: row strips (already cropped to the grid rect) for rows
      // with unread inked cells.
      for (var r = 0; r < 9; r++) {
        if (!_rowHasMissing(prep, grid, r)) continue;
        final path = prep.stripPaths[r];
        if (path == null) continue;
        final result =
            await recognizer.processImage(InputImage.fromFilePath(path));
        _placeAll(result, grid, prep.stripRect(r), r);
      }

      // Pass 3: single inked cells that still have no digit.
      for (final entry in prep.tilePaths.entries) {
        final r = entry.key ~/ 9, c = entry.key % 9;
        if (grid[r][c] != 0) continue;
        final result = await recognizer
            .processImage(InputImage.fromFilePath(entry.value));
        final digit = _majorityDigit(result);
        debugPrint('sudoku-ocr cell($r,$c): '
            '${result.text.replaceAll('\n', ' ')} -> $digit');
        if (digit != null) grid[r][c] = digit;
      }

      final found = grid.expand((row) => row).where((v) => v != 0).length;
      if (found < 10) {
        throw Exception(
            'Only $found digits recognised — try a sharper photo and crop '
            'tightly around the grid.');
      }
      return grid;
    } finally {
      recognizer.close();
      for (final p in [...prep.stripPaths.values, ...prep.tilePaths.values]) {
        File(p).delete().ignore();
      }
    }
  }

  static bool _rowHasMissing(_Artifacts prep, List<List<int>> grid, int r) {
    for (var c = 0; c < 9; c++) {
      if (prep.inked[r][c] && grid[r][c] == 0) return true;
    }
    return false;
  }

  static void _placeAll(RecognizedText result, List<List<int>> grid,
      Rect gridRect, int? rowOverride) {
    for (final block in result.blocks) {
      for (final line in block.lines) {
        for (final element in line.elements) {
          _placeElement(element, grid, gridRect, rowOverride);
        }
      }
    }
  }

  /// Splits an OCR element into characters (adjacent cells are sometimes
  /// merged into one element like "53") and drops each digit into the cell
  /// under its estimated centre.
  static void _placeElement(
    TextElement element,
    List<List<int>> grid,
    Rect gridRect,
    int? rowOverride,
  ) {
    final text = element.text.trim();
    if (text.isEmpty) return;

    final box = element.boundingBox;
    final charWidth = box.width / text.length;

    for (var i = 0; i < text.length; i++) {
      final digit = _asDigit(text[i]);
      if (digit == null) continue;

      final cx = box.left + charWidth * (i + 0.5);
      final cy = box.top + box.height / 2;
      final fx = (cx - gridRect.left) / gridRect.width;
      final fy = (cy - gridRect.top) / gridRect.height;
      // Ignore text outside the grid.
      if (fx < -0.02 || fx > 1.02) continue;
      if (rowOverride == null && (fy < -0.02 || fy > 1.02)) continue;

      final col = (fx * 9).floor().clamp(0, 8);
      final row = rowOverride ?? (fy * 9).floor().clamp(0, 8);
      if (grid[row][col] == 0) grid[row][col] = digit;
    }
  }

  static int? _majorityDigit(RecognizedText result) {
    final votes = <int, int>{};
    for (final ch in result.text.split('')) {
      final d = _asDigit(ch);
      if (d != null) votes[d] = (votes[d] ?? 0) + 1;
    }
    if (votes.isEmpty) return null;
    return (votes.entries.toList()..sort((a, b) => b.value - a.value))
        .first
        .key;
  }

  static int? _asDigit(String ch) {
    // Common OCR confusions for printed sudoku digits.
    const fixes = {'l': 1, 'I': 1, '|': 1, 'S': 5, 's': 5, 'g': 9, 'q': 9};
    final code = ch.codeUnitAt(0);
    if (code >= 0x31 && code <= 0x39) return code - 0x30; // '1'-'9'
    return fixes[ch];
  }
}

class _Artifacts {
  _Artifacts({
    required this.gridRect,
    required this.inked,
    required this.stripPaths,
    required this.stripScale,
    required this.inkedRows,
  });

  /// Grid bounding box in original image coordinates.
  final Rect gridRect;
  final List<List<bool>> inked;
  final Map<int, String> stripPaths; // row -> file
  final double stripScale;
  final List<int> inkedRows;

  final tilePaths = <int, String>{};

  /// Rect used to map strip OCR coordinates back to columns: the strip is
  /// the full grid width, upscaled.
  Rect stripRect(int r) => Rect.fromLTWH(
      0, 0, gridRect.width * stripScale, gridRect.height / 9 * stripScale);
}

/// Runs in a background isolate: decodes the crop, finds the grid bounds,
/// computes the ink map, and writes upscaled row strips plus tiled
/// single-cell images.
Future<_Artifacts> _prepareArtifacts(String path) async {
  final decoded = await img.decodeImageFile(path);
  if (decoded == null) {
    throw Exception('Could not decode the image');
  }

  final gray = img.grayscale(decoded.clone());
  final w = gray.width, h = gray.height;

  // Paper-white reference and dark threshold.
  var sum = 0.0, samples = 0;
  for (var y = 0; y < h; y += 4) {
    for (var x = 0; x < w; x += 4) {
      sum += gray.getPixel(x, y).r.toDouble();
      samples++;
    }
  }
  final darkCutoff = (sum / samples) * 0.6;

  // Grid bounding box from dark-pixel projection profiles: grid lines
  // produce rows/columns where a large share of pixels is dark.
  final rowDark = List.filled(h, 0), colDark = List.filled(w, 0);
  for (var y = 0; y < h; y += 2) {
    for (var x = 0; x < w; x += 2) {
      if (gray.getPixel(x, y).r < darkCutoff) {
        rowDark[y]++;
        colDark[x]++;
      }
    }
  }
  int firstAbove(List<int> profile, int limit, bool fromEnd) {
    final indices = fromEnd
        ? List.generate(profile.length, (i) => profile.length - 1 - i)
        : List.generate(profile.length, (i) => i);
    for (final i in indices) {
      if (profile[i] > limit) return i;
    }
    return fromEnd ? profile.length - 1 : 0;
  }

  final rowLimit = (w / 2 * 0.35).round(), colLimit = (h / 2 * 0.35).round();
  var top = firstAbove(rowDark, rowLimit, false).toDouble();
  var bottom = firstAbove(rowDark, rowLimit, true).toDouble();
  var left = firstAbove(colDark, colLimit, false).toDouble();
  var right = firstAbove(colDark, colLimit, true).toDouble();
  // Sanity: grid must cover a reasonable share of the crop.
  if (bottom - top < h * 0.5 || right - left < w * 0.5) {
    top = 0;
    bottom = h - 1;
    left = 0;
    right = w - 1;
  }
  final grid = Rect.fromLTRB(left, top, right + 1, bottom + 1);
  final cw = grid.width / 9, ch = grid.height / 9;

  // Ink map over the central 55% of each cell, so grid lines don't count.
  final inked = List.generate(9, (r) {
    return List.generate(9, (c) {
      final x0 = (grid.left + c * cw + cw * 0.225).round();
      final x1 = (grid.left + c * cw + cw * 0.775).round();
      final y0 = (grid.top + r * ch + ch * 0.225).round();
      final y1 = (grid.top + r * ch + ch * 0.775).round();
      var dark = 0, total = 0;
      for (var y = y0; y < y1; y += 2) {
        for (var x = x0; x < x1; x += 2) {
          if (gray.getPixel(math.min(x, w - 1), math.min(y, h - 1)).r <
              darkCutoff) {
            dark++;
          }
          total++;
        }
      }
      return total > 0 && dark / total > 0.02;
    });
  });

  const stripScale = 2.0;
  final stripPaths = <int, String>{};
  final pad = ch * 0.06;
  final inkedRows = <int>[];
  for (var r = 0; r < 9; r++) {
    if (!inked[r].contains(true)) continue;
    inkedRows.add(r);
    final topY = (grid.top + r * ch - pad).round().clamp(0, h - 2);
    final bottomY = (grid.top + (r + 1) * ch + pad).round().clamp(0, h - 1);
    var strip = img.copyCrop(decoded,
        x: grid.left.round(),
        y: topY,
        width: grid.width.round(),
        height: bottomY - topY);
    strip = img.copyResize(strip, width: (strip.width * stripScale).round());
    final file = File('$path.row$r.jpg');
    await file.writeAsBytes(img.encodeJpg(strip, quality: 92));
    stripPaths[r] = file.path;
  }

  final artifacts = _Artifacts(
    gridRect: grid,
    inked: inked,
    stripPaths: stripPaths,
    stripScale: stripScale,
    inkedRows: inkedRows,
  );

  for (var r = 0; r < 9; r++) {
    for (var c = 0; c < 9; c++) {
      if (!inked[r][c]) continue;
      var cell = img.copyCrop(
        decoded,
        x: (grid.left + c * cw + cw * 0.08).round(),
        y: (grid.top + r * ch + ch * 0.08).round(),
        width: (cw * 0.84).round(),
        height: (ch * 0.84).round(),
      );
      cell = img.copyResize(cell, height: 160);

      final gap = (cell.width * 0.35).round();
      const margin = 32;
      final tiled = img.Image(
        width: cell.width * 3 + gap * 2 + margin * 2,
        height: cell.height + margin * 2,
      );
      img.fill(tiled, color: img.ColorRgb8(255, 255, 255));
      for (var i = 0; i < 3; i++) {
        img.compositeImage(tiled, cell,
            dstX: margin + i * (cell.width + gap), dstY: margin);
      }
      final file = File('$path.cell${r}_$c.jpg');
      await file.writeAsBytes(img.encodeJpg(tiled, quality: 92));
      artifacts.tilePaths[r * 9 + c] = file.path;
    }
  }

  return artifacts;
}
