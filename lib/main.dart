import 'package:flutter/material.dart';
import 'dart:math';
import 'dart:ui' as ui;

void main() {
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Line to Text',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        visualDensity: VisualDensity.adaptivePlatformDensity,
      ),
      home: DrawingScreen(),
    );
  }
}

class DrawingScreen extends StatefulWidget {
  const DrawingScreen({super.key});

  @override
  State<DrawingScreen> createState() => _DrawingScreenState();
}

class _DrawingScreenState extends State<DrawingScreen> {
  List<Offset> currentPath = [];
  List<List<Offset>> paths = [];
  List<TextElement> textElements = [];
  
  bool _editMode = false;
  bool _contentEditMode = false;
  bool _positionEditMode = false;
  TextElement? _selectedElement;
  Offset? _dragStartOffset;
  bool _isResizing = false;
  Corner _resizingCorner = Corner.none;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Line to Text'),
        actions: [
          if (_editMode) ...[
            IconButton(
              icon: Icon(Icons.edit_note, color: _contentEditMode ? Colors.blue : null),
              onPressed: () {
                setState(() {
                  _contentEditMode = true;
                  _positionEditMode = false;
                });
              },
            ),
            IconButton(
              icon: Icon(Icons.open_with, color: _positionEditMode ? Colors.blue : null),
              onPressed: () {
                setState(() {
                  _contentEditMode = false;
                  _positionEditMode = true;
                });
              },
            ),
            IconButton(
              icon: Icon(Icons.done),
              onPressed: _toggleEditMode,
            ),
          ] else ...[
            IconButton(
              icon: Icon(Icons.edit),
              onPressed: _toggleEditMode,
            ),
          ]
        ],
      ),
      body: Stack(
        children: [
          GestureDetector(
            onPanStart: (details) {
              if (_editMode) return;
              setState(() => currentPath = [details.localPosition]);
            },
            onPanUpdate: (details) {
              if (_editMode) return;
              setState(() => currentPath.add(details.localPosition));
            },
            onPanEnd: (details) {
              if (_editMode) return;
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
                textElements: textElements,
                editMode: _editMode,
                selectedElement: _selectedElement,
              ),
              child: Container(
                width: MediaQuery.of(context).size.width,
                height: MediaQuery.of(context).size.height,
              ),
            ),
          ),
          
          ...textElements.map((element) {
            bool isSelected = _editMode && _selectedElement == element;
            return Positioned(
              left: element.position.dx,
              top: element.position.dy,
              child: GestureDetector(
                onTap: () {
                  if (_editMode && _positionEditMode) {
                    setState(() => _selectedElement = element);
                  }
                },
                onPanStart: (details) {
                  if (isSelected && _positionEditMode) {
                    setState(() => _dragStartOffset = details.localPosition);
                  }
                },
                onPanUpdate: (details) {
                  if (isSelected && _positionEditMode && _dragStartOffset != null) {
                    setState(() {
                      element.position += details.localPosition - _dragStartOffset!;
                      _dragStartOffset = details.localPosition;
                    });
                  }
                },
                child: _buildTextElement(element, isSelected),
              ),
            );
          }).toList(),
        ],
      ),
      floatingActionButton: _editMode ? null : FloatingActionButton(
        child: Icon(Icons.text_fields),
        onPressed: _processLines,
      ),
    );
  }

  Widget _buildTextElement(TextElement element, bool isSelected) {
    // Calculate required height for the text
    final textPainter = TextPainter(
      text: TextSpan(
        text: element.controller.text,
        style: TextStyle(fontSize: 16),
      ),
      maxLines: null,
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: element.size.width - 16); // Account for padding

    final calculatedHeight = textPainter.size.height + 16; // Add padding
    
    return StatefulBuilder(
      builder: (context, setState) {
        // Update element height when text changes
        if (_contentEditMode && element == _selectedElement) {
          element.size = Size(element.size.width, calculatedHeight);
        }
        
        return Stack(
          children: [
            Container(
              width: element.size.width,
              height: _contentEditMode && element == _selectedElement 
                  ? null // Auto-expand in edit mode
                  : max(calculatedHeight, 40), // Minimum height of 40
              decoration: BoxDecoration(
                border: Border.all(
                  color: isSelected ? Colors.blue : Colors.transparent,
                  width: 2.0,
                ),
                color: _contentEditMode ? Colors.white.withOpacity(0.9) : Colors.transparent,
              ),
              child: _contentEditMode && element == _selectedElement
                  ? TextField(
                      controller: element.controller,
                      decoration: InputDecoration(
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.all(8),
                      ),
                      maxLines: null,
                      keyboardType: TextInputType.multiline,
                      onChanged: (text) => setState(() {}), // Trigger rebuild
                    )
                  : Padding(
                      padding: EdgeInsets.all(8),
                      child: Text(
                        element.controller.text,
                        style: TextStyle(fontSize: 16),
                        maxLines: null,
                        softWrap: true,
                      ),
                    ),
            ),
            
            if (isSelected && _positionEditMode) ...[
              _buildResizeHandle(element, Corner.left),
              _buildResizeHandle(element, Corner.right),
            ],
          ],
        );
      },
    );
  }

  Widget _buildResizeHandle(TextElement element, Corner corner) {
    return Positioned(
      left: corner == Corner.left ? 0 : null,
      right: corner == Corner.right ? 0 : null,
      top: element.size.height / 2 - 8,
      child: GestureDetector(
        onPanStart: (details) {
          setState(() {
            _isResizing = true;
            _resizingCorner = corner;
            _dragStartOffset = details.localPosition;
          });
        },
        onPanUpdate: (details) {
          if (_isResizing && _dragStartOffset != null) {
            setState(() {
              final delta = details.localPosition - _dragStartOffset!;
              if (corner == Corner.left) {
                element.position += Offset(delta.dx, 0);
                element.size = Size(element.size.width - delta.dx, element.size.height);
              } else {
                element.size = Size(element.size.width + delta.dx, element.size.height);
              }
              _dragStartOffset = details.localPosition;
              if (element.size.width < 50) element.size = Size(50, element.size.height);
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
    );
  }

  void _toggleEditMode() {
    setState(() {
      _editMode = !_editMode;
      _contentEditMode = false;
      _positionEditMode = false;
      if (!_editMode) _selectedElement = null;
    });
  }

  Future<void> _processLines() async {
    List<List<Offset>> linesToRemove = [];
    List<List<Offset>> linesToKeep = [];
    
    for (var path in paths) {
      if (path.length < 2) continue;
      
      double minX = path[0].dx;
      double maxX = path[0].dx;
      double avgY = path[0].dy;
      
      for (var point in path) {
        minX = min(minX, point.dx);
        maxX = max(maxX, point.dx);
        avgY = (avgY + point.dy) / 2;
      }
      
      double width = maxX - minX;
      
      if (width > 100) {
        linesToRemove.add(path);
        
        bool overlaps = false;
        Rect newRect = Rect.fromLTWH(minX, avgY - 20, width, 40);
        
        for (var element in textElements) {
          Rect existingRect = Rect.fromLTWH(
            element.position.dx, 
            element.position.dy, 
            element.size.width, 
            element.size.height
          );
          if (newRect.overlaps(existingRect)) {
            overlaps = true;
            break;
          }
        }
        
        if (!overlaps) {
          String? content = await showDialog<String>(
            context: context,
            builder: (context) => TextInputDialog(),
          );
          
          if (content != null && content.isNotEmpty) {
            setState(() {
              textElements.add(TextElement(
                position: Offset(minX, avgY - 20),
                size: Size(width, 40), // Initial height, will auto-expand
                controller: TextEditingController(text: content),
              ));
            });
          }
        }
      } else {
        linesToKeep.add(path);
      }
    }
    
    setState(() => paths = linesToKeep);
  }
}

class DrawingPainter extends CustomPainter {
  final List<List<Offset>> paths;
  final List<Offset> currentPath;
  final List<TextElement> textElements;
  final bool editMode;
  final TextElement? selectedElement;

  DrawingPainter({
    required this.paths,
    required this.currentPath,
    required this.textElements,
    required this.editMode,
    this.selectedElement,
  });

  @override
  void paint(Canvas canvas, Size size) {
    Paint paint = Paint()
      ..color = Colors.blue
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke
      ..strokeWidth = editMode ? 1.0 : 3.0;

    for (var path in paths) {
      if (path.length > 1) canvas.drawPoints(ui.PointMode.polygon, path, paint);
    }

    if (currentPath.length > 1) {
      canvas.drawPoints(ui.PointMode.polygon, currentPath, paint);
    }

    if (editMode && textElements.isNotEmpty) {
      final textPainter = TextPainter(
        text: TextSpan(
          text: 'Select text to edit',
          style: TextStyle(color: Colors.grey, fontSize: 16),
        ),
        textDirection: TextDirection.ltr,
      );
      textPainter.layout();
      textPainter.paint(canvas, Offset(size.width / 2 - textPainter.width / 2, 20));
    }
  }

  @override
  bool shouldRepaint(DrawingPainter oldDelegate) => 
      oldDelegate.paths != paths ||
      oldDelegate.currentPath != currentPath ||
      oldDelegate.textElements != textElements ||
      oldDelegate.editMode != editMode ||
      oldDelegate.selectedElement != selectedElement;
}

class TextElement {
  Offset position;
  Size size;
  TextEditingController controller;

  TextElement({
    required this.position,
    required this.size,
    required this.controller,
  });
}

enum Corner { none, left, right }

class TextInputDialog extends StatefulWidget {
  const TextInputDialog({super.key});

  @override
  _TextInputDialogState createState() => _TextInputDialogState();
}

class _TextInputDialogState extends State<TextInputDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Add Text Content'),
      content: TextField(
        controller: _controller,
        decoration: InputDecoration(hintText: 'Type multiple lines...'),
        maxLines: null,
        keyboardType: TextInputType.multiline,
        autofocus: true,
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text('Cancel'),
        ),
        TextButton(
          onPressed: () {
            if (_controller.text.isNotEmpty) Navigator.pop(context, _controller.text);
          },
          child: Text('Add'),
        ),
      ],
    );
  }
}