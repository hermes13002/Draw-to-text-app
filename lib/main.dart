import 'dart:io';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

void main() {
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Rectangle to Text',
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
  Offset? _startPoint;
  Offset? _currentPoint;
  List<Rect> rectangles = [];
  List<TextElement> textElements = [];
  
  bool _editMode = false;
  bool _contentEditMode = false;
  bool _positionEditMode = false;
  TextElement? _selectedElement;
  Offset? _dragStartOffset;
  bool _isResizing = false;
  Corner _resizingCorner = Corner.none;
  
  // Screen padding constants
  final double screenPadding = 8.0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Rectangle to Text'),
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
            // DELETE BUTTON - Only visible when in edit mode and an element is selected
            if (_selectedElement != null)
              IconButton(
                icon: Icon(Icons.delete, color: Colors.red),
                onPressed: _deleteSelectedElement,
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
            IconButton(
              icon: Icon(Icons.picture_as_pdf),
              onPressed: _exportToPDF,
              tooltip: 'Export to PDF',
            ),
          ]
        ],
      ),
      body: Padding(
        padding: EdgeInsets.all(screenPadding),
        child: Stack(
          children: [
            GestureDetector(
              onPanStart: (details) {
                if (_editMode) return;
                setState(() {
                  _startPoint = details.localPosition;
                  _currentPoint = details.localPosition;
                });
              },
              onPanUpdate: (details) {
                if (_editMode) return;
                setState(() => _currentPoint = details.localPosition);
              },
              onPanEnd: (details) {
                if (_editMode) return;
                setState(() {
                  if (_startPoint != null && _currentPoint != null) {
                    final rect = Rect.fromPoints(
                      Offset(
                        _startPoint!.dx.clamp(screenPadding, MediaQuery.of(context).size.width - screenPadding),
                        _startPoint!.dy.clamp(screenPadding, MediaQuery.of(context).size.height - screenPadding),
                      ),
                      Offset(
                        _currentPoint!.dx.clamp(screenPadding, MediaQuery.of(context).size.width - screenPadding),
                        _currentPoint!.dy.clamp(screenPadding, MediaQuery.of(context).size.height - screenPadding),
                      ),
                    );
                    if (rect.width.abs() > 5 && rect.height.abs() > 5) {
                      rectangles.add(rect);
                    }
                  }
                  _startPoint = null;
                  _currentPoint = null;
                });
              },
              child: CustomPaint(
                painter: DrawingPainter(
                  rectangles: rectangles,
                  currentRect: _startPoint != null && _currentPoint != null 
                    ? Rect.fromPoints(
                        Offset(
                          _startPoint!.dx.clamp(screenPadding, MediaQuery.of(context).size.width - screenPadding),
                          _startPoint!.dy.clamp(screenPadding, MediaQuery.of(context).size.height - screenPadding),
                        ),
                        Offset(
                          _currentPoint!.dx.clamp(screenPadding, MediaQuery.of(context).size.width - screenPadding),
                          _currentPoint!.dy.clamp(screenPadding, MediaQuery.of(context).size.height - screenPadding),
                        ),
                      )
                    : null,
                  textElements: textElements,
                  editMode: _editMode,
                  selectedElement: _selectedElement,
                ),
                child: Container(
                  width: MediaQuery.of(context).size.width - 2 * screenPadding,
                  height: MediaQuery.of(context).size.height - 2 * screenPadding,
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
                        // Constrain movement within screen bounds
                        final newPosition = element.position + (details.localPosition - _dragStartOffset!);
                        element.position = Offset(
                          newPosition.dx.clamp(screenPadding, MediaQuery.of(context).size.width - screenPadding - element.size.width),
                          newPosition.dy.clamp(screenPadding, MediaQuery.of(context).size.height - screenPadding - element.size.height),
                        );
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
      ),
      floatingActionButton: _editMode ? null : FloatingActionButton(
        child: Icon(Icons.text_fields),
        onPressed: _processRectangles,
      ),
    );
  }

  Widget _buildTextElement(TextElement element, bool isSelected) {
    final textPainter = TextPainter(
      text: TextSpan(
        text: element.controller.text,
        style: TextStyle(fontSize: 16),
      ),
      maxLines: null,
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: element.size.width - 16);

    final calculatedHeight = textPainter.size.height + 16;
    
    return StatefulBuilder(
      builder: (context, setState) {
        if (_contentEditMode && element == _selectedElement) {
          element.size = Size(element.size.width, calculatedHeight);
        }
        
        return Stack(
          children: [
            Container(
              width: element.size.width,
              height: _contentEditMode && element == _selectedElement 
                  ? null
                  : max(calculatedHeight, 40),
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
                      onChanged: (text) => setState(() {}),
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
              // Top resize handle
              _buildResizeHandle(element, Corner.top),
              // Right resize handle
              _buildResizeHandle(element, Corner.right),
              // Bottom resize handle
              _buildResizeHandle(element, Corner.bottom),
              // Left resize handle
              _buildResizeHandle(element, Corner.left),
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
      top: corner == Corner.top ? 0 : null,
      bottom: corner == Corner.bottom ? 0 : null,
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
              
              switch (corner) {
                case Corner.left:
                  final newWidth = element.size.width - delta.dx;
                  if (newWidth > 50 && 
                      element.position.dx + delta.dx >= screenPadding) {
                    element.position += Offset(delta.dx, 0);
                    element.size = Size(newWidth, element.size.height);
                  }
                  break;
                case Corner.right:
                  final newWidth = element.size.width + delta.dx;
                  if (newWidth > 50 && 
                      element.position.dx + newWidth <= MediaQuery.of(context).size.width - screenPadding) {
                    element.size = Size(newWidth, element.size.height);
                  }
                  break;
                case Corner.top:
                  final newHeight = element.size.height - delta.dy;
                  if (newHeight > 30 && 
                      element.position.dy + delta.dy >= screenPadding) {
                    element.position += Offset(0, delta.dy);
                    element.size = Size(element.size.width, newHeight);
                  }
                  break;
                case Corner.bottom:
                  final newHeight = element.size.height + delta.dy;
                  if (newHeight > 30 && 
                      element.position.dy + newHeight <= MediaQuery.of(context).size.height - screenPadding) {
                    element.size = Size(element.size.width, newHeight);
                  }
                  break;
                case Corner.none:
                  break;
              }
              
              _dragStartOffset = details.localPosition;
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

  void _deleteSelectedElement() {
    if (_selectedElement != null) {
      setState(() {
        textElements.remove(_selectedElement);
        _selectedElement = null;
      });
    }
  }

  void _toggleEditMode() {
    setState(() {
      _editMode = !_editMode;
      _contentEditMode = false;
      _positionEditMode = false;
      if (!_editMode) _selectedElement = null;
    });
  }

  Future<void> _processRectangles() async {
    List<Rect> rectsToRemove = [];
    
    for (var rect in rectangles) {
      if (rect.width > 100 && rect.height > 20) {
        rectsToRemove.add(rect);
        
        bool overlaps = false;
        Rect newRect = Rect.fromLTWH(
          rect.left, 
          rect.top, 
          rect.width, 
          rect.height
        );
        
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
                position: Offset(rect.left, rect.top),
                size: Size(rect.width, rect.height),
                controller: TextEditingController(text: content),
              ));
            });
          }
        }
      }
    }
    
    setState(() => rectangles.removeWhere((r) => rectsToRemove.contains(r)));
  }

  Future<void> _exportToPDF() async {
    try {
      final pdf = pw.Document(
        title: 'Drawing Export',
        author: 'Rectangle to Text App',
      );

      const a4Width = 210.0 * PdfPageFormat.mm;
      const a4Height = 297.0 * PdfPageFormat.mm;
      const margin = 10.0 * PdfPageFormat.mm;

      final contentWidth = a4Width - (2 * margin);
      final contentHeight = a4Height - (2 * margin);

      Rect contentBounds = _calculateContentBounds();

      double scale = min(
        contentWidth / contentBounds.width,
        contentHeight / contentBounds.height,
      ).clamp(0.1, 1.0);

      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          margin: pw.EdgeInsets.all(0),
          build: (pw.Context context) {
            return pw.Transform.scale(
              scale: scale,
              child: pw.Container(
                width: contentWidth,
                height: contentHeight,
                color: PdfColors.white,
                child: pw.Stack(
                  children: [
                    ...rectangles.map((rect) => pw.CustomPaint(
                      painter: (PdfGraphics canvas, size) {
                        canvas.drawRect(
                          rect.left - contentBounds.left,
                          rect.top - contentBounds.top,
                          rect.width,
                          rect.height,
                        );
                      },
                    )),
                    
                    ...textElements.map((element) => pw.Positioned(
                      left: element.position.dx - contentBounds.left,
                      top: element.position.dy - contentBounds.top,
                      child: pw.Container(
                        width: element.size.width,
                        height: element.size.height,
                        child: pw.Text(
                          element.controller.text,
                          style: pw.TextStyle(
                            fontSize: 16,
                            color: PdfColors.black,
                          ),
                        ),
                      ),
                    )),
                  ],
                ),
              ),
            );
          },
        ),
      );

      final output = await getTemporaryDirectory();
      final file = File('${output.path}/drawing_export.pdf');
      await file.writeAsBytes(await pdf.save());

      await Share.shareXFiles([XFile(file.path)],
        text: 'Here is my drawing export',
        subject: 'Drawing Export',
      );

    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('PDF export failed: ${e.toString()}')),
      );
    }
  }

  Rect _calculateContentBounds() {
    double minX = double.infinity;
    double minY = double.infinity;
    double maxX = double.negativeInfinity;
    double maxY = double.negativeInfinity;

    for (var rect in rectangles) {
      minX = min(minX, rect.left);
      minY = min(minY, rect.top);
      maxX = max(maxX, rect.right);
      maxY = max(maxY, rect.bottom);
    }

    for (var element in textElements) {
      minX = min(minX, element.position.dx);
      minY = min(minY, element.position.dy);
      maxX = max(maxX, element.position.dx + element.size.width);
      maxY = max(maxY, element.position.dy + element.size.height);
    }

    if (minX == double.infinity) {
      return Rect.fromLTRB(0, 0, 100, 100);
    }

    return Rect.fromLTRB(minX, minY, maxX, maxY);
  }
}

class DrawingPainter extends CustomPainter {
  final List<Rect> rectangles;
  final Rect? currentRect;
  final List<TextElement> textElements;
  final bool editMode;
  final TextElement? selectedElement;

  DrawingPainter({
    required this.rectangles,
    required this.currentRect,
    required this.textElements,
    required this.editMode,
    this.selectedElement,
  });

  @override
  void paint(Canvas canvas, Size size) {
    Paint paint = Paint()
      ..color = Colors.blue
      ..style = PaintingStyle.stroke
      ..strokeWidth = editMode ? 1.0 : 3.0;

    for (var rect in rectangles) {
      canvas.drawRect(rect, paint);
    }

    if (currentRect != null) {
      canvas.drawRect(currentRect!, paint);
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
      oldDelegate.rectangles != rectangles ||
      oldDelegate.currentRect != currentRect ||
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

enum Corner { none, left, right, top, bottom }

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
        decoration: InputDecoration(
          hintText: 'Type text...',
          enabled: true,
          border: OutlineInputBorder(),
          enabledBorder: OutlineInputBorder(
            borderSide: BorderSide(color: Colors.grey, width: 1.0),
            borderRadius: BorderRadius.circular(8.0),
          ),
        ),
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