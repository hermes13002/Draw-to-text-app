import 'package:flutter/material.dart';
import 'dart:math';

class DrawingScreen extends StatefulWidget {
  const DrawingScreen({super.key});

  @override
  State<DrawingScreen> createState() => _DrawingScreenState();
}

class _DrawingScreenState extends State<DrawingScreen> {
  List<Offset> currentPath = [];
  List<List<Offset>> paths = [];
  List<TextFieldData> textFields = [];
  final bool _isDrawingBox = false;
  Offset? _boxStartPoint;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Draw to Text')),
      body: Stack(
        children: [
          // Drawing canvas
          GestureDetector(
            onPanStart: (details) {
              setState(() {
                _boxStartPoint = details.localPosition;
                currentPath = [details.localPosition];
              });
            },
            onPanUpdate: (details) {
              setState(() {
                currentPath.add(details.localPosition);
              });
            },
            onPanEnd: (details) {
              setState(() {
                if (currentPath.isNotEmpty) {
                  paths.add(List.from(currentPath));
                  currentPath = [];
                }
              });
            },
            child: CustomPaint(
              painter: DrawingPainter(
                paths: paths,
                currentPath: currentPath,
                textFields: textFields,
              ),
              child: SizedBox(
                width: MediaQuery.of(context).size.width,
                height: MediaQuery.of(context).size.height,
              ),
            ),
          ),
          
          // Text fields layer
          ...textFields.map((field) => Positioned(
            left: field.position.dx,
            top: field.position.dy,
            child: GestureDetector(
              onTap: () => FocusScope.of(context).requestFocus(FocusNode()),
              child: Container(
                width: field.size.width,
                height: field.size.height,
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey),
                  color: Colors.white.withOpacity(0.8),
                ),
                child: TextField(
                  controller: field.controller,
                  decoration: InputDecoration(
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.all(8),
                    hintText: 'Type here...',
                    enabledBorder: OutlineInputBorder(
                      borderSide: BorderSide(color: Colors.grey),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderSide: BorderSide(color: Colors.blue),
                    ),
                  ),
                  maxLines: null,
                  expands: true,
                ),
              ),
            ),
          )).toList(),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        tooltip: 'Convert boxes to text fields',
        onPressed: _convertBoxesToTextFields,
        child: Icon(Icons.text_fields),
      ),
    );
  }

  void _convertBoxesToTextFields() {
    List<TextFieldData> newTextFields = [];
    
    for (var path in paths) {
      if (path.length < 4) continue;
      
      // Calculate bounding box
      double minX = path[0].dx;
      double maxX = path[0].dx;
      double minY = path[0].dy;
      double maxY = path[0].dy;
      
      for (var point in path) {
        minX = min(minX, point.dx);
        maxX = max(maxX, point.dx);
        minY = min(minY, point.dy);
        maxY = max(maxY, point.dy);
      }
      
      double width = maxX - minX;
      double height = maxY - minY;
      
      // Only consider shapes with reasonable size
      if (width > 50 && height > 30) {
        // Check if this overlaps with existing text fields
        bool overlaps = false;
        Rect newRect = Rect.fromLTWH(minX, minY, width, height);
        
        for (var field in textFields) {
          Rect existingRect = Rect.fromLTWH(
            field.position.dx, 
            field.position.dy, 
            field.size.width, 
            field.size.height
          );
          
          if (newRect.overlaps(existingRect)) {
            overlaps = true;
            break;
          }
        }
        
        if (!overlaps) {
          newTextFields.add(TextFieldData(
            position: Offset(minX, minY),
            size: Size(width, height),
            controller: TextEditingController(),
          ));
        }
      }
    }
    
    setState(() {
      textFields.addAll(newTextFields);
      // Remove paths that were converted to text fields
      paths.removeWhere((path) {
        if (path.length < 4) return false;
        
        double minX = path[0].dx;
        double maxX = path[0].dx;
        double minY = path[0].dy;
        double maxY = path[0].dy;
        
        for (var point in path) {
          minX = min(minX, point.dx);
          maxX = max(maxX, point.dx);
          minY = min(minY, point.dy);
          maxY = max(maxY, point.dy);
        }
        
        double width = maxX - minX;
        double height = maxY - minY;
        
        return width > 50 && height > 30;
      });
    });
  }
}

class DrawingPainter extends CustomPainter {
  final List<List<Offset>> paths;
  final List<Offset> currentPath;
  final List<TextFieldData> textFields;

  DrawingPainter({
    required this.paths,
    required this.currentPath,
    required this.textFields,
  });

  @override
  void paint(Canvas canvas, Size size) {
    Paint paint = Paint()
      ..color = Colors.blue
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 3.0
      ..style = PaintingStyle.stroke;

    // Draw all completed paths
    for (var path in paths) {
      if (path.length > 1) {
        for (int i = 0; i < path.length - 1; i++) {
          canvas.drawLine(path[i], path[i + 1], paint);
        }
      }
    }

    // Draw current path
    if (currentPath.length > 1) {
      for (int i = 0; i < currentPath.length - 1; i++) {
        canvas.drawLine(currentPath[i], currentPath[i + 1], paint);
      }
    }

    // Draw placeholder for text fields (optional)
    Paint textFieldPaint = Paint()
      ..color = Colors.grey.withOpacity(0.3)
      ..style = PaintingStyle.fill;

    for (var field in textFields) {
      canvas.drawRect(
        Rect.fromLTWH(
          field.position.dx,
          field.position.dy,
          field.size.width,
          field.size.height,
        ),
        textFieldPaint,
      );
    }
  }

  @override
  bool shouldRepaint(DrawingPainter oldDelegate) {
    return oldDelegate.paths != paths ||
        oldDelegate.currentPath != currentPath ||
        oldDelegate.textFields != textFields;
  }
}

class TextFieldData {
  final Offset position;
  final Size size;
  final TextEditingController controller;

  TextFieldData({
    required this.position,
    required this.size,
    required this.controller,
  });
}