# Sudoku Solver

Snap a Sudoku and solve it. An Android app that reads the puzzle from a photo
with on-device OCR, lets you check the digits it found, and solves the grid
instantly. Built with Flutter by Dhiva Labs.

## How it works

1. **Scan.** Take a photo with the **Camera** or pick one with **Upload**.
2. **Crop.** Drag the corners so the frame covers the 9×9 grid.
3. **Check.** The recognised digits fill the board. Tap any cell and use the
   keypad to fix a misread digit or add a missing clue. Conflicting cells
   are shown in red.
4. **Solve.** Tap **Solve** and the empty cells fill in. Editing after a
   solve keeps your clues and clears the answers, so you can solve again.

You can also skip the photo and type a puzzle in by hand.

## Features

- **On-device OCR** with Google ML Kit text recognition. The photo never
  leaves the phone.
- **Grid detection.** The real grid is found from its strong lines, so the
  crop doesn't have to be pixel-perfect.
- **Three recognition passes**: the whole image, then each row as a strip,
  then single cells that clearly hold ink but still have no digit. Common
  misreads of printed digits are corrected.
- **Fast solver.** Backtracking that always fills the cell with the fewest
  candidates first, so even minimal-clue puzzles solve quickly.
- **Validation.** Conflicting clues and unsolvable puzzles are reported
  instead of producing a wrong answer.
- Material 3 with light and dark themes.

## Project layout

| File | What it does |
| --- | --- |
| [`lib/home_screen.dart`](lib/home_screen.dart) | Board, keypad, scan and solve actions |
| [`lib/crop_screen.dart`](lib/crop_screen.dart) | Crop the photo to the grid |
| [`lib/ocr_service.dart`](lib/ocr_service.dart) | Grid detection and the three ML Kit passes; image work runs in a background isolate |
| [`lib/solver.dart`](lib/solver.dart) | Validation, conflict detection and the backtracking solver |
| [`test/solver_test.dart`](test/solver_test.dart) | Solver tests: standard, minimal-clue, conflicting and unsolvable puzzles |

## Build and run

Requires the Flutter SDK (Dart 3.12 or newer) and an Android device or
emulator. The project currently targets Android only.

```bash
flutter pub get
flutter test
flutter run            # on a connected device
flutter build apk      # release APK in build/app/outputs/flutter-apk/
```

## Sponsors

Dhiva Labs is an independent, self-funded lab. [Sponsorships](https://github.com/sponsors/Dhiva-Labs) help bring this project and the rest of Dhiva Labs to every platform, iPhone and Mac included.

[![Sponsor Dhiva Labs](https://img.shields.io/badge/Sponsor-Dhiva%20Labs-ea4aaa?logo=githubsponsors&logoColor=white)](https://github.com/sponsors/Dhiva-Labs)

Monthly sponsors at $10 and up are listed here:

<!-- sponsors -->
*Be the first: [sponsor Dhiva Labs](https://github.com/sponsors/Dhiva-Labs).*
<!-- sponsors -->
