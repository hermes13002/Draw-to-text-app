import 'package:flutter/material.dart';
import 'dart:math';
import 'dart:ui' as ui;

void main() {
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Line to Text',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primarySwatch: Colors.blue,
        visualDensity: VisualDensity.adaptivePlatformDensity,
      ),
      home: DrawingScreen(),
    );
  }
}

class DrawingScreen extends StatefulWidget {
  @override
  _DrawingScreenState createState() => _DrawingScreenState();
}

class _DrawingScreenState extends State<DrawingScreen> {
  List<Offset> currentPath = [];
  List<List<Offset>> paths = [];
  List<TextFieldData> textFields = [];
  
  // Selection mode variables
  bool _selectionMode = false;
  TextFieldData? _selectedField;
  Offset? _dragStartOffset;
  bool _isResizing = false;
  Corner _resizingCorner = Corner.none;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Line to Text'),
        actions: [
          IconButton(
            icon: Icon(_selectionMode ? Icons.done : Icons.select_all),
            tooltip: _selectionMode ? 'Exit Selection Mode' : 'Enter Selection Mode',
            onPressed: _toggleSelectionMode,
          ),
        ],
      ),
      body: Stack(
        children: [
          // Drawing canvas
          GestureDetector(
            onPanStart: (details) {
              if (_selectionMode) return;
              
              setState(() {
                currentPath = [details.localPosition];
              });
            },
            onPanUpdate: (details) {
              if (_selectionMode) return;
              
              setState(() {
                currentPath.add(details.localPosition);
              });
            },
            onPanEnd: (details) {
              if (_selectionMode) return;
              
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
                selectionMode: _selectionMode,
                selectedField: _selectedField,
              ),
              child: Container(
                width: MediaQuery.of(context).size.width,
                height: MediaQuery.of(context).size.height,
              ),
            ),
          ),
          
          // Text fields layer
          ...textFields.map((field) {
            bool isSelected = _selectionMode && _selectedField == field;
            return Positioned(
              left: field.position.dx,
              top: field.position.dy,
              child: GestureDetector(
                onTap: () {
                  if (_selectionMode) {
                    setState(() {
                      _selectedField = field;
                    });
                  }
                },
                onPanStart: (details) {
                  if (isSelected) {
                    setState(() {
                      _dragStartOffset = details.localPosition;
                    });
                  }
                },
                onPanUpdate: (details) {
                  if (isSelected && _dragStartOffset != null) {
                    setState(() {
                      field.position += details.localPosition - _dragStartOffset!;
                      _dragStartOffset = details.localPosition;
                    });
                  }
                },
                child: Stack(
                  children: [
                    Container(
                      width: field.size.width,
                      height: field.size.height,
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: isSelected ? Colors.blue : Colors.transparent,
                          width: 2.0,
                        ),
                        color: Colors.white.withOpacity(0.9),
                      ),
                      child: IgnorePointer(
                        ignoring: _selectionMode,
                        child: TextField(
                          controller: field.controller,
                          decoration: InputDecoration(
                            border: InputBorder.none,
                            contentPadding: EdgeInsets.all(8),
                            hintText: 'Type here...',
                          ),
                          maxLines: null,
                          expands: true,
                        ),
                      ),
                    ),
                    
                    // Resize handles (only visible when selected)
                    if (isSelected) ...[
                      // Left edge handle
                      Positioned(
                        left: 0,
                        top: field.size.height / 2 - 8,
                        child: GestureDetector(
                          onPanStart: (details) {
                            setState(() {
                              _isResizing = true;
                              _resizingCorner = Corner.left;
                              _dragStartOffset = details.localPosition;
                            });
                          },
                          onPanUpdate: (details) {
                            if (_isResizing && _dragStartOffset != null) {
                              setState(() {
                                final delta = details.localPosition - _dragStartOffset!;
                                field.position += Offset(delta.dx, 0);
                                field.size = Size(field.size.width - delta.dx, field.size.height);
                                _dragStartOffset = details.localPosition;
                                
                                // Ensure minimum width
                                if (field.size.width < 100) {
                                  field.size = Size(100, field.size.height);
                                }
                              });
                            }
                          },
                          onPanEnd: (details) {
                            setState(() {
                              _isResizing = false;
                              _resizingCorner = Corner.none;
                            });
                          },
                          child: Container(
                            width: 16,
                            height: 16,
                            decoration: BoxDecoration(
                              color: Colors.blue,
                              shape: BoxShape.circle,
                            ),
                          ),
                        ),
                      ),
                      
                      // Right edge handle
                      Positioned(
                        right: 0,
                        top: field.size.height / 2 - 8,
                        child: GestureDetector(
                          onPanStart: (details) {
                            setState(() {
                              _isResizing = true;
                              _resizingCorner = Corner.right;
                              _dragStartOffset = details.localPosition;
                            });
                          },
                          onPanUpdate: (details) {
                            if (_isResizing && _dragStartOffset != null) {
                              setState(() {
                                final delta = details.localPosition - _dragStartOffset!;
                                field.size = Size(field.size.width + delta.dx, field.size.height);
                                _dragStartOffset = details.localPosition;
                                
                                // Ensure minimum width
                                if (field.size.width < 100) {
                                  field.size = Size(100, field.size.height);
                                }
                              });
                            }
                          },
                          onPanEnd: (details) {
                            setState(() {
                              _isResizing = false;
                              _resizingCorner = Corner.none;
                            });
                          },
                          child: Container(
                            width: 16,
                            height: 16,
                            decoration: BoxDecoration(
                              color: Colors.blue,
                              shape: BoxShape.circle,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            );
          }).toList(),
        ],
      ),
      floatingActionButton: _selectionMode ? null : FloatingActionButton(
        child: Icon(Icons.text_fields),
        tooltip: 'Convert lines to text fields',
        onPressed: _convertLinesToTextFields,
      ),
    );
  }

  void _toggleSelectionMode() {
    setState(() {
      _selectionMode = !_selectionMode;
      if (!_selectionMode) {
        _selectedField = null;
      }
    });
  }

  void _convertLinesToTextFields() {
    List<TextFieldData> newTextFields = [];
    
    for (var path in paths) {
      if (path.length < 2) continue;
      
      // Calculate line properties
      double minX = path[0].dx;
      double maxX = path[0].dx;
      double avgY = path[0].dy;
      
      for (var point in path) {
        minX = min(minX, point.dx);
        maxX = max(maxX, point.dx);
        avgY = (avgY + point.dy) / 2;
      }
      
      double width = maxX - minX;
      
      // Only consider lines with reasonable length
      if (width > 100) {
        // Check if this overlaps with existing text fields
        bool overlaps = false;
        Rect newRect = Rect.fromLTWH(minX, avgY - 20, width, 40);
        
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
            position: Offset(minX, avgY - 20), // Center the field vertically
            size: Size(width, 40), // Standard height
            controller: TextEditingController(),
          ));
        }
      }
    }
    
    setState(() {
      textFields.addAll(newTextFields);
      // Remove paths that were converted to text fields
      paths.removeWhere((path) {
        if (path.length < 2) return false;
        
        double minX = path[0].dx;
        double maxX = path[0].dx;
        
        for (var point in path) {
          minX = min(minX, point.dx);
          maxX = max(maxX, point.dx);
        }
        
        double width = maxX - minX;
        return width > 100;
      });
    });
  }
}

class DrawingPainter extends CustomPainter {
  final List<List<Offset>> paths;
  final List<Offset> currentPath;
  final List<TextFieldData> textFields;
  final bool selectionMode;
  final TextFieldData? selectedField;

  DrawingPainter({
    required this.paths,
    required this.currentPath,
    required this.textFields,
    required this.selectionMode,
    this.selectedField,
  });

  @override
  void paint(Canvas canvas, Size size) {
    Paint paint = Paint()
      ..color = Colors.blue
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke
      ..strokeWidth = selectionMode ? 1.0 : 3.0; // Thinner lines in selection mode
      

    // Draw all completed paths
    for (var path in paths) {
      if (path.length > 1) {
        canvas.drawPoints(ui.PointMode.polygon, path, paint);
      }
    }

    // Draw current path
    if (currentPath.length > 1) {
      canvas.drawPoints(ui.PointMode.polygon, currentPath, paint);
    }

    // Draw hint text in selection mode
    if (selectionMode && textFields.isNotEmpty) {
      final textPainter = TextPainter(
        text: TextSpan(
          text: 'Select a text field to move or resize',
          style: TextStyle(color: Colors.grey, fontSize: 16),
        ),
        textDirection: TextDirection.ltr,
      );
      textPainter.layout();
      textPainter.paint(
        canvas,
        Offset(size.width / 2 - textPainter.width / 2, 20),
      );
    }
  }

  @override
  bool shouldRepaint(DrawingPainter oldDelegate) {
    return oldDelegate.paths != paths ||
        oldDelegate.currentPath != currentPath ||
        oldDelegate.textFields != textFields ||
        oldDelegate.selectionMode != selectionMode ||
        oldDelegate.selectedField != selectedField;
  }
}

class TextFieldData {
  Offset position;
  Size size;
  TextEditingController controller;

  TextFieldData({
    required this.position,
    required this.size,
    required this.controller,
  });
}

enum Corner {
  none,
  left,
  right,
}