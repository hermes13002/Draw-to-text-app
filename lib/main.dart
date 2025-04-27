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
  final double screenPadding = 20.0;
  
  // Alignment guides
  List<AlignmentGuide> activeGuides = [];
  double snapThreshold = 8.0;
  bool showGrid = false;
  double gridSize = 20.0;

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
                  activeGuides.clear();
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
              icon: Icon(Icons.grid_on, color: showGrid ? Colors.blue : null),
              onPressed: () {
                setState(() {
                  showGrid = !showGrid;
                });
              },
              tooltip: 'Toggle Grid',
            ),
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
        child: LayoutBuilder(
          builder: (context, constraints) {
            return Stack(
              children: [
                // Grid Background
                if (showGrid)
                  CustomPaint(
                    painter: GridPainter(
                      gridSize: gridSize,
                      color: Colors.grey.withOpacity(0.3),
                    ),
                    size: Size.infinite,
                  ),
                
                // Drawing Canvas
                // Handles drawing rectangles and text elements on the canvas.
                // Uses GestureDetector to track touch events for drawing and moving elements.
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
                            _startPoint!.dx.clamp(screenPadding, constraints.maxWidth - screenPadding),
                            _startPoint!.dy.clamp(screenPadding, constraints.maxHeight - screenPadding),
                          ),
                          Offset(
                            _currentPoint!.dx.clamp(screenPadding, constraints.maxWidth - screenPadding),
                            _currentPoint!.dy.clamp(screenPadding, constraints.maxHeight - screenPadding),
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
                              _startPoint!.dx.clamp(screenPadding, constraints.maxWidth - screenPadding),
                              _startPoint!.dy.clamp(screenPadding, constraints.maxHeight - screenPadding),
                            ),
                            Offset(
                              _currentPoint!.dx.clamp(screenPadding, constraints.maxWidth - screenPadding),
                              _currentPoint!.dy.clamp(screenPadding, constraints.maxHeight - screenPadding),
                            ),
                          )
                        : null,
                      textElements: textElements,
                      editMode: _editMode,
                      selectedElement: _selectedElement,
                    ),
                    child: Container(
                      width: constraints.maxWidth,
                      height: constraints.maxHeight,
                    ),
                  ),
                ),
                
                // Text Elements
                // Places text elements on the canvas
                // Handles selection, dragging, and alignment of text elements.
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
                          setState(() {
                            _dragStartOffset = details.localPosition;
                            activeGuides.clear();
                          });
                        }
                      },
                      onPanUpdate: (details) {
                        if (isSelected && _positionEditMode && _dragStartOffset != null) {
                          setState(() {
                            // Calculate proposed new position
                            Offset newPosition = element.position + (details.localPosition - _dragStartOffset!);
                            
                            // Clear previous guides
                            activeGuides.clear();
                            
                            // Check for alignments
                            _checkAlignments(element, newPosition, constraints);
                            
                            // Apply snapping if close to guide
                            for (var guide in activeGuides) {
                              if (guide.type == GuideType.horizontal) {
                                if ((newPosition.dy - guide.position).abs() < snapThreshold) {
                                  newPosition = Offset(newPosition.dx, guide.position);
                                }
                              } else if (guide.type == GuideType.vertical) {
                                if ((newPosition.dx - guide.position).abs() < snapThreshold) {
                                  newPosition = Offset(guide.position, newPosition.dy);
                                }
                              }
                            }
                            
                            // Update position with constraints
                            element.position = Offset(
                              newPosition.dx.clamp(screenPadding, constraints.maxWidth - screenPadding - element.size.width),
                              newPosition.dy.clamp(screenPadding, constraints.maxHeight - screenPadding - element.size.height),
                            );
                            
                            _dragStartOffset = details.localPosition;
                          });
                        }
                      },
                      onPanEnd: (details) {
                        setState(() {
                          activeGuides.clear();
                        });
                      },
                      child: _buildTextElement(element, isSelected, constraints),
                    ),
                  );
                }).toList(),
                
                // Alignment Guides
                // Displays alignment guides when dragging elements
                // Shows guides for edges, centers, and spacing between elements.
                if (_editMode && _positionEditMode && _selectedElement != null)
                  ...activeGuides.map((guide) {
                    return Positioned(
                      left: guide.type == GuideType.vertical ? guide.position : 0,
                      top: guide.type == GuideType.horizontal ? guide.position : 0,
                      child: Container(
                        width: guide.type == GuideType.vertical ? 1 : constraints.maxWidth,
                        height: guide.type == GuideType.horizontal ? 1 : constraints.maxHeight,
                        decoration: BoxDecoration(
                          border: Border(
                            top: guide.type == GuideType.horizontal 
                              ? BorderSide(color: guide.color, width: 1, style: BorderStyle.solid)
                              : BorderSide.none,
                            left: guide.type == GuideType.vertical 
                              ? BorderSide(color: guide.color, width: 1, style: BorderStyle.solid)
                              : BorderSide.none,
                          ),
                        ),
                        child: guide.label != null ? Center(
                          child: Container(
                            padding: EdgeInsets.all(2),
                            color: guide.color.withOpacity(0.2),
                            child: Text(
                              guide.label!,
                              style: TextStyle(color: guide.color, fontSize: 12),
                            ),
                          ),
                        ) : null,
                      ),
                    );
                  }),
                
                // Alignment Toolbar
                // Displays alignment options when an element is selected
                // Allows user to align selected element with other elements or screen edges.
                if (_editMode && _positionEditMode && _selectedElement != null)
                  Positioned(
                    bottom: 20,
                    right: 20,
                    child: AlignmentToolbar(
                      onAlign: (alignment) {
                        _alignSelectedElements(alignment);
                      },
                    ),
                  ),
              ],
            );
          },
        ),
      ),
      floatingActionButton: _editMode ? null : FloatingActionButton(
        child: Icon(Icons.text_fields),
        onPressed: _processRectangles,
      ),
    );
  }

  // Builds the text element with a TextField or Text widget based on edit mode
  // Handles resizing and alignment guides for the text element.
  Widget _buildTextElement(TextElement element, bool isSelected, BoxConstraints constraints) {
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
              _buildResizeHandle(element, Corner.top, constraints),
              // Right resize handle
              _buildResizeHandle(element, Corner.right, constraints),
              // Bottom resize handle
              _buildResizeHandle(element, Corner.bottom, constraints),
              // Left resize handle
              _buildResizeHandle(element, Corner.left, constraints),
            ],
          ],
        );
      },
    );
  }

  // Builds the resize handle for the text element
  Widget _buildResizeHandle(TextElement element, Corner corner, BoxConstraints constraints) {
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
                      element.position.dx + newWidth <= constraints.maxWidth - screenPadding) {
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
                      element.position.dy + newHeight <= constraints.maxHeight - screenPadding) {
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

  // Checks for alignment guides based on the current position of the moving element
  void _checkAlignments(TextElement movingElement, Offset newPosition, BoxConstraints constraints) {
    Rect movingRect = Rect.fromLTWH(
      newPosition.dx, 
      newPosition.dy, 
      movingElement.size.width, 
      movingElement.size.height
    );
    
    // Check against other elements
    for (var element in textElements) {
      if (element == movingElement) continue;
      
      Rect fixedRect = Rect.fromLTWH(
        element.position.dx,
        element.position.dy,
        element.size.width,
        element.size.height
      );
      
      // Edge alignments
      _checkEdgeAlignment(movingRect, fixedRect);
      
      // Center alignments
      _checkCenterAlignment(movingRect, fixedRect);
      
      // Spacing
      _checkSpacing(movingRect, fixedRect);
    }
    
    // Screen edge guides
    _checkScreenAlignment(movingRect, constraints);
  }

  // Checks for alignment guides based on the current position of the moving element
  void _checkEdgeAlignment(Rect moving, Rect fixed) {
    // Left edge
    if ((moving.left - fixed.left).abs() < 20) {
      activeGuides.add(AlignmentGuide(GuideType.vertical, fixed.left, label: "Left"));
    }
    
    // Right edge
    if ((moving.right - fixed.right).abs() < 20) {
      activeGuides.add(AlignmentGuide(GuideType.vertical, fixed.right, label: "Right"));
    }
    
    // Top edge
    if ((moving.top - fixed.top).abs() < 20) {
      activeGuides.add(AlignmentGuide(GuideType.horizontal, fixed.top, label: "Top"));
    }
    
    // Bottom edge
    if ((moving.bottom - fixed.bottom).abs() < 20) {
      activeGuides.add(AlignmentGuide(GuideType.horizontal, fixed.bottom, label: "Bottom"));
    }
  }

  // Checks for center alignment guides based on the current position of the moving element
  void _checkCenterAlignment(Rect moving, Rect fixed) {
    // Vertical center
    if ((moving.center.dx - fixed.center.dx).abs() < 20) {
      activeGuides.add(AlignmentGuide(
        GuideType.vertical, 
        fixed.center.dx,
        label: "Center",
        color: Colors.green
      ));
    }
    
    // Horizontal center
    if ((moving.center.dy - fixed.center.dy).abs() < 20) {
      activeGuides.add(AlignmentGuide(
        GuideType.horizontal, 
        fixed.center.dy,
        label: "Middle",
        color: Colors.green
      ));
    }
  }

  // Checks for spacing guides based on the current position of the moving element
  void _checkSpacing(Rect moving, Rect fixed) {
    // Horizontal spacing
    if ((moving.left - fixed.right).abs() < 40) {
      activeGuides.add(AlignmentGuide(
        GuideType.vertical, 
        moving.left,
        label: "${(moving.left - fixed.right).abs().toStringAsFixed(0)}px",
        color: Colors.orange
      ));
    }
    
    // Vertical spacing
    if ((moving.top - fixed.bottom).abs() < 40) {
      activeGuides.add(AlignmentGuide(
        GuideType.horizontal, 
        moving.top,
        label: "${(moving.top - fixed.bottom).abs().toStringAsFixed(0)}px",
        color: Colors.orange
      ));
    }
  }

  // Checks for screen alignment guides based on the current position of the moving element
  void _checkScreenAlignment(Rect rect, BoxConstraints constraints) {
    // Screen edges
    if ((rect.left - screenPadding).abs() < 20) {
      activeGuides.add(AlignmentGuide(
        GuideType.vertical, 
        screenPadding,
        label: "Left Margin",
        color: Colors.purple
      ));
    }
    
    if ((rect.right - (constraints.maxWidth - screenPadding)).abs() < 20) {
      activeGuides.add(AlignmentGuide(
        GuideType.vertical, 
        constraints.maxWidth - screenPadding,
        label: "Right Margin",
        color: Colors.purple
      ));
    }
    
    if ((rect.top - screenPadding).abs() < 20) {
      activeGuides.add(AlignmentGuide(
        GuideType.horizontal, 
        screenPadding,
        label: "Top Margin",
        color: Colors.purple
      ));
    }
    
    if ((rect.bottom - (constraints.maxHeight - screenPadding)).abs() < 20) {
      activeGuides.add(AlignmentGuide(
        GuideType.horizontal, 
        constraints.maxHeight - screenPadding,
        label: "Bottom Margin",
        color: Colors.purple
      ));
    }
    
    // Screen center
    final screenCenterX = constraints.maxWidth / 2;
    if ((rect.center.dx - screenCenterX).abs() < 20) {
      activeGuides.add(AlignmentGuide(
        GuideType.vertical, 
        screenCenterX,
        label: "Screen Center",
        color: Colors.purple
      ));
    }
    
    final screenCenterY = constraints.maxHeight / 2;
    if ((rect.center.dy - screenCenterY).abs() < 20) {
      activeGuides.add(AlignmentGuide(
        GuideType.horizontal, 
        screenCenterY,
        label: "Screen Middle",
        color: Colors.purple
      ));
    }
  }

  // Aligns the selected element with other elements or screen edges based on the selected alignment type
  void _alignSelectedElements(AlignmentType alignment) {
    if (_selectedElement == null) return;
    
    setState(() {
      Rect selectedRect = Rect.fromLTWH(
        _selectedElement!.position.dx,
        _selectedElement!.position.dy,
        _selectedElement!.size.width,
        _selectedElement!.size.height
      );
      
      for (var element in textElements) {
        if (element == _selectedElement) continue;
        
        Rect otherRect = Rect.fromLTWH(
          element.position.dx,
          element.position.dy,
          element.size.width,
          element.size.height
        );
        
        switch (alignment) {
          case AlignmentType.left:
            if ((selectedRect.left - otherRect.left).abs() < 20) {
              _selectedElement!.position = Offset(
                otherRect.left,
                _selectedElement!.position.dy
              );
            }
            break;
          case AlignmentType.right:
            if ((selectedRect.right - otherRect.right).abs() < 20) {
              _selectedElement!.position = Offset(
                otherRect.right - _selectedElement!.size.width,
                _selectedElement!.position.dy
              );
            }
            break;
          case AlignmentType.top:
            if ((selectedRect.top - otherRect.top).abs() < 20) {
              _selectedElement!.position = Offset(
                _selectedElement!.position.dx,
                otherRect.top
              );
            }
            break;
          case AlignmentType.bottom:
            if ((selectedRect.bottom - otherRect.bottom).abs() < 20) {
              _selectedElement!.position = Offset(
                _selectedElement!.position.dx,
                otherRect.bottom - _selectedElement!.size.height
              );
            }
            break;
          case AlignmentType.centerVertical:
            if ((selectedRect.center.dx - otherRect.center.dx).abs() < 20) {
              _selectedElement!.position = Offset(
                otherRect.center.dx - (_selectedElement!.size.width / 2),
                _selectedElement!.position.dy
              );
            }
            break;
          case AlignmentType.centerHorizontal:
            if ((selectedRect.center.dy - otherRect.center.dy).abs() < 20) {
              _selectedElement!.position = Offset(
                _selectedElement!.position.dx,
                otherRect.center.dy - (_selectedElement!.size.height / 2)
              );
            }
            break;
        }
      }
    });
  }

  // Deletes the selected text element from the canvas
  void _deleteSelectedElement() {
    if (_selectedElement != null) {
      setState(() {
        textElements.remove(_selectedElement);
        _selectedElement = null;
      });
    }
  }

  // Toggles the edit mode for the canvas
  // In edit mode, the user can select and move text elements or rectangles.
  void _toggleEditMode() {
    setState(() {
      _editMode = !_editMode;
      _contentEditMode = false;
      _positionEditMode = false;
      activeGuides.clear();
      if (!_editMode) _selectedElement = null;
    });
  }

  // Processes rectangles to check for overlaps with text elements
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

  // Exports the current drawing to a PDF file
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

  // Calculates the content bounds of all rectangles and text elements
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


enum GuideType { horizontal, vertical, spacing }

// Represents an alignment guide for snapping elements to edges or centers
class AlignmentGuide {
  final GuideType type;
  final double position;
  final String? label;
  final Color color;

  AlignmentGuide(this.type, this.position, {this.label, this.color = Colors.blue});
}

enum AlignmentType {
  left,
  right,
  top,
  bottom,
  centerVertical,
  centerHorizontal
}

class AlignmentToolbar extends StatelessWidget {
  final Function(AlignmentType) onAlign;

  const AlignmentToolbar({super.key, required this.onAlign});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: EdgeInsets.all(8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildAlignmentButton(Icons.format_align_left, AlignmentType.left),
            _buildAlignmentButton(Icons.format_align_center, AlignmentType.centerVertical),
            _buildAlignmentButton(Icons.format_align_right, AlignmentType.right),
            SizedBox(height: 8),
            _buildAlignmentButton(Icons.vertical_align_top, AlignmentType.top),
            _buildAlignmentButton(Icons.vertical_align_center, AlignmentType.centerHorizontal),
            _buildAlignmentButton(Icons.vertical_align_bottom, AlignmentType.bottom),
          ],
        ),
      ),
    );
  }

  Widget _buildAlignmentButton(IconData icon, AlignmentType type) {
    return IconButton(
      icon: Icon(icon),
      onPressed: () => onAlign(type),
      tooltip: type.toString().split('.').last,
    );
  }
}

class GridPainter extends CustomPainter {
  final double gridSize;
  final Color color;

  GridPainter({required this.gridSize, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.0;

    // Draw vertical lines
    for (double x = 0; x < size.width; x += gridSize) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }

    // Draw horizontal lines
    for (double y = 0; y < size.height; y += gridSize) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// Custom painter for drawing rectangles and text elements on the canvas
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

// Represents a text element on the canvas
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