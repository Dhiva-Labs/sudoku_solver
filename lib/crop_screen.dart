import 'dart:typed_data';

import 'package:crop_your_image/crop_your_image.dart';
import 'package:flutter/material.dart';

/// Lets the user crop the photo down to just the Sudoku grid.
/// Pops with the cropped image bytes, or null when cancelled.
class CropScreen extends StatefulWidget {
  const CropScreen({super.key, required this.imageBytes});

  final Uint8List imageBytes;

  @override
  State<CropScreen> createState() => _CropScreenState();
}

class _CropScreenState extends State<CropScreen> {
  final _controller = CropController();
  var _cropping = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('Crop to the grid'),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          const Padding(
            padding: EdgeInsets.all(12),
            child: Text(
              'Drag the corners so the frame covers exactly the 9×9 grid.',
              style: TextStyle(color: Colors.white70),
              textAlign: TextAlign.center,
            ),
          ),
          Expanded(
            child: Crop(
              controller: _controller,
              image: widget.imageBytes,
              onCropped: (result) {
                if (!mounted) return;
                switch (result) {
                  case CropSuccess(:final croppedImage):
                    Navigator.of(context).pop(croppedImage);
                  case CropFailure(:final cause):
                    setState(() => _cropping = false);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Crop failed: $cause')),
                    );
                }
              },
              baseColor: Colors.black,
              maskColor: Colors.black54,
              cornerDotBuilder: (size, alignment) =>
                  const DotControl(color: Colors.tealAccent),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: FilledButton.icon(
                onPressed: _cropping
                    ? null
                    : () {
                        setState(() => _cropping = true);
                        _controller.crop();
                      },
                icon: _cropping
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.check),
                label: Text(_cropping ? 'Cropping…' : 'Use this crop'),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
