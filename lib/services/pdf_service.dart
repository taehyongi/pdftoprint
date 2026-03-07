import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:pdf/widgets.dart' as pw;
import 'package:pdfx/pdfx.dart' as pdfx;
import 'package:syncfusion_flutter_pdf/pdf.dart' as sf;

class InterleaveSet {
  final String pathA;
  final String pathB;
  final bool reverseA;
  final bool reverseB;
  final int rotationA; // 0, 90, 180, 270
  final int rotationB; // 0, 90, 180, 270

  InterleaveSet({
    required this.pathA,
    required this.pathB,
    this.reverseA = false,
    this.reverseB = false,
    this.rotationA = 0,
    this.rotationB = 0,
  });

  Map<String, dynamic> toJson() => {
    'pathA': pathA,
    'pathB': pathB,
    'reverseA': reverseA,
    'reverseB': reverseB,
    'rotationA': rotationA,
    'rotationB': rotationB,
  };

  factory InterleaveSet.fromJson(Map<String, dynamic> json) => InterleaveSet(
    pathA: json['pathA'],
    pathB: json['pathB'],
    reverseA: json['reverseA'],
    reverseB: json['reverseB'],
    rotationA: json['rotationA'] ?? 0,
    rotationB: json['rotationB'] ?? 0,
  );
}

class PdfService {
  /// Removes background from a PDF by whitening pixels using parallel processing.
  Future<String> removeBackground({
    required String inputPath,
    required String outputPath,
    required int whitePoint,
    required int blackPoint,
    void Function(double)? onProgress,
  }) async {
    debugPrint("[PdfService] Starting parallel removeBackground");
    final inputBytes = await File(inputPath).readAsBytes();
    final document = await pdfx.PdfDocument.openData(inputBytes);
    final pageCount = document.pagesCount;
    await document.close();

    final int processorCount = Platform.numberOfProcessors;
    // We want to leave some headroom, but use at least 1 isolate.
    final int isolateCount = (processorCount > 1) ? processorCount - 1 : 1;
    final int pagesPerIsolate = (pageCount / isolateCount).ceil();

    debugPrint("[PdfService] Page count: $pageCount, Using $isolateCount isolates, ~$pagesPerIsolate pages each");

    final List<ReceivePort> receivePorts = [];
    final List<Isolate> isolates = [];
    final List<Future<Map<int, Uint8List>>> resultsFutures = [];
    
    int completedPages = 0;
    final token = RootIsolateToken.instance!;

    for (int i = 0; i < isolateCount; i++) {
      final int startPage = i * pagesPerIsolate + 1;
      int endPage = (i + 1) * pagesPerIsolate;
      if (endPage > pageCount) endPage = pageCount;
      if (startPage > pageCount) break;

      final receivePort = ReceivePort();
      receivePorts.add(receivePort);
      
      final completer = Completer<Map<int, Uint8List>>();
      resultsFutures.add(completer.future);

      final isolate = await Isolate.spawn(
        _removeBackgroundIsolateEntry,
        {
          'inputBytes': inputBytes,
          'whitePoint': whitePoint,
          'blackPoint': blackPoint,
          'startPage': startPage,
          'endPage': endPage,
          'token': token,
          'sendPort': receivePort.sendPort,
        },
      );
      isolates.add(isolate);

      receivePort.listen((message) {
        if (message is double) {
          // This is a partial progress from one isolate.
          // In a multi-isolate world, we need to track total progress.
          // However, for simplicity, we count pages.
        } else if (message is int) {
          // One page completed
          completedPages++;
          if (onProgress != null) onProgress(completedPages / pageCount);
        } else if (message is Map<int, Uint8List>) {
          completer.complete(message);
        } else if (message is String && message.startsWith("ERROR:")) {
          completer.completeError(message.replaceFirst("ERROR:", ""));
        }
      });
    }

    try {
      final List<Map<int, Uint8List>> chunks = await Future.wait(resultsFutures);
      final Map<int, Uint8List> allPages = {};
      for (var chunk in chunks) {
        allPages.addAll(chunk);
      }

      // We need to add pages in correct order
      for (int i = 1; i <= pageCount; i++) {
        final pageData = allPages[i];
        if (pageData == null) continue;
      }
      
      // To keep it simple and avoid dimension issues, let's refine the isolate entry to return [bytes, width, height]
      // and update the aggregation.
      
      return await _buildFinalPdf(allPages, outputPath);
    } catch (e) {
      debugPrint("[PdfService] Error in parallel removeBackground: $e");
      rethrow;
    } finally {
      for (var p in receivePorts) {
        p.close();
      }
      for (var iso in isolates) {
        iso.kill();
      }
    }
  }


  Future<String> _buildFinalPdf(Map<int, Uint8List> pagesData, String outputPath) async {
    final pdfCreator = pw.Document();
    final sortedKeys = pagesData.keys.toList()..sort();
    
    for (var key in sortedKeys) {
      final image = pw.MemoryImage(pagesData[key]!);
      pdfCreator.addPage(
        pw.Page(
          build: (pw.Context context) => pw.FullPage(
            ignoreMargins: true,
            child: pw.Image(image, fit: pw.BoxFit.contain),
          ),
        ),
      );
    }
    
    final resultBytes = await pdfCreator.save();
    await File(outputPath).writeAsBytes(resultBytes);
    return outputPath;
  }

  static void _removeBackgroundIsolateEntry(Map<String, dynamic> params) async {
    final Uint8List inputBytes = params['inputBytes'];
    final int whitePoint = params['whitePoint'];
    final int blackPoint = params['blackPoint'];
    final int startPage = params['startPage'];
    final int endPage = params['endPage'];
    final RootIsolateToken token = params['token'];
    final SendPort sendPort = params['sendPort'];

    final Map<int, Uint8List> processedPages = {};

    try {
      BackgroundIsolateBinaryMessenger.ensureInitialized(token);
      final document = await pdfx.PdfDocument.openData(inputBytes);

      for (int i = startPage; i <= endPage; i++) {
        final page = await document.getPage(i);
        final pageImage = await page.render(
          width: page.width * 2,
          height: page.height * 2,
          quality: 100,
        );

        if (pageImage == null) {
          await page.close();
          continue;
        }

        final rawImage = img.decodeImage(pageImage.bytes);
        if (rawImage != null) {
          for (final pixel in rawImage) {
            int r = pixel.r.toInt();
            int g = pixel.g.toInt();
            int b = pixel.b.toInt();

            if (r >= whitePoint && g >= whitePoint && b >= whitePoint) {
              pixel.r = 255; pixel.g = 255; pixel.b = 255;
            } else if (r <= blackPoint && g <= blackPoint && b <= blackPoint) {
              pixel.r = 0; pixel.g = 0; pixel.b = 0;
            } else {
              double range = (whitePoint - blackPoint).toDouble();
              if (range > 0) {
                pixel.r = (((r - blackPoint) / range).clamp(0.0, 1.0) * 255).toInt();
                pixel.g = (((g - blackPoint) / range).clamp(0.0, 1.0) * 255).toInt();
                pixel.b = (((b - blackPoint) / range).clamp(0.0, 1.0) * 255).toInt();
              }
            }
          }
          processedPages[i] = Uint8List.fromList(img.encodeJpg(rawImage, quality: 85));
        }

        await page.close();
        sendPort.send(i); // Signal one page done
      }

      await document.close();
      sendPort.send(processedPages);
    } catch (e) {
      sendPort.send("ERROR: $e");
    }
  }

  /// Helper to draw a template with specific rotation using Graphics transforms
  static void _drawRotatedTemplate(sf.PdfPage page, sf.PdfTemplate template, int rotationDegrees) {
    page.graphics.save();
    
    final double w = template.size.width;
    final double h = template.size.height;

    if (rotationDegrees == 90) {
      page.graphics.translateTransform(h, 0);
      page.graphics.rotateTransform(90);
    } else if (rotationDegrees == 180) {
      page.graphics.translateTransform(w, h);
      page.graphics.rotateTransform(180);
    } else if (rotationDegrees == 270) {
      page.graphics.translateTransform(0, w);
      page.graphics.rotateTransform(270);
    }

    page.graphics.drawPdfTemplate(template, const Offset(0, 0));
    page.graphics.restore();
  }

  /// Helper to get the correct size for a rotated template
  static Size _getRotatedSize(Size original, int rotationDegrees) {
    if (rotationDegrees == 90 || rotationDegrees == 270) {
      return Size(original.height, original.width);
    }
    return original;
  }

  /// Merges multiple PDFs into one in a background isolate.
  Future<String> mergePdfs({
    required List<String> paths,
    required String outputName,
    required List<bool> reverseFlags,
    required List<int> rotations,
    void Function(double)? onProgress,
  }) async {
    debugPrint("[PdfService] Starting background mergePdfs");
    final receivePort = ReceivePort();
    final token = RootIsolateToken.instance!;
    
    final isolate = await Isolate.spawn(
      _mergeIsolateEntry,
      {
        'paths': paths,
        'outputName': outputName,
        'reverseFlags': reverseFlags,
        'rotations': rotations,
        'token': token,
        'sendPort': receivePort.sendPort,
      },
    );

    final completer = Completer<String>();
    
    receivePort.listen((message) {
      if (message is double) {
        if (onProgress != null) onProgress(message);
      } else if (message is String) {
        if (message.startsWith("ERROR:")) {
          completer.completeError(message.replaceFirst("ERROR:", ""));
        } else {
          completer.complete(message);
        }
      }
    });

    try {
      return await completer.future;
    } finally {
      receivePort.close();
      isolate.kill();
    }
  }

  static void _mergeIsolateEntry(Map<String, dynamic> params) async {
    final List<String> paths = params['paths'];
    final String outputName = params['outputName'];
    final List<bool> reverseFlags = params['reverseFlags'];
    final List<int> rotations = params['rotations'];
    final RootIsolateToken token = params['token'];
    final SendPort sendPort = params['sendPort'];

    try {
      BackgroundIsolateBinaryMessenger.ensureInitialized(token);
      final sf.PdfDocument finalDoc = sf.PdfDocument();
      finalDoc.pageSettings.margins.all = 0;

      for (int i = 0; i < paths.length; i++) {
        sendPort.send(i / paths.length);
        
        final path = paths[i];
        if (path.isEmpty) continue;

        final bytes = await File(path).readAsBytes();
        final sf.PdfDocument inputDoc = sf.PdfDocument(inputBytes: bytes);
        
        final bool isReverse = i < reverseFlags.length ? reverseFlags[i] : false;
        final int rotation = i < rotations.length ? rotations[i] : 0;
        
        if (isReverse) {
          for (int j = inputDoc.pages.count - 1; j >= 0; j--) {
            final sf.PdfPage page = inputDoc.pages[j];
            final sf.PdfTemplate template = page.createTemplate();
            final sf.PdfPage newPage = finalDoc.pages.add();
            finalDoc.pageSettings.size = PdfService._getRotatedSize(template.size, rotation);
            PdfService._drawRotatedTemplate(newPage, template, rotation);
          }
        } else {
          for (int j = 0; j < inputDoc.pages.count; j++) {
            final sf.PdfPage page = inputDoc.pages[j];
            final sf.PdfTemplate template = page.createTemplate();
            final sf.PdfPage newPage = finalDoc.pages.add();
            finalDoc.pageSettings.size = PdfService._getRotatedSize(template.size, rotation);
            PdfService._drawRotatedTemplate(newPage, template, rotation);
          }
        }
        inputDoc.dispose();
      }

      sendPort.send(0.9);
      final List<int> resultBytes = await finalDoc.save();
      finalDoc.dispose();

      await File(outputName).writeAsBytes(resultBytes);
      sendPort.send(1.0);
      sendPort.send(outputName);
    } catch (e) {
      sendPort.send("ERROR: $e");
    }
  }

  /// Interleaves pages from two PDFs in a background isolate.
  Future<String> interleavePdfs({
    required String pathA,
    required String pathB,
    required String outputPath,
    bool reverseA = false,
    bool reverseB = false,
    int rotationA = 0,
    int rotationB = 0,
    void Function(double)? onProgress,
  }) async {
    debugPrint("[PdfService] Starting background interleavePdfs");
    final receivePort = ReceivePort();
    final token = RootIsolateToken.instance!;

    final isolate = await Isolate.spawn(
      _interleaveIsolateEntry,
      {
        'pathA': pathA,
        'pathB': pathB,
        'outputPath': outputPath,
        'reverseA': reverseA,
        'reverseB': reverseB,
        'rotationA': rotationA,
        'rotationB': rotationB,
        'token': token,
        'sendPort': receivePort.sendPort,
      },
    );

    final completer = Completer<String>();

    receivePort.listen((message) {
      if (message is double) {
        if (onProgress != null) onProgress(message);
      } else if (message is String) {
        if (message.startsWith("ERROR:")) {
          completer.completeError(message.replaceFirst("ERROR:", ""));
        } else {
          completer.complete(message);
        }
      }
    });

    try {
      return await completer.future;
    } finally {
      receivePort.close();
      isolate.kill();
    }
  }

  static void _interleaveIsolateEntry(Map<String, dynamic> params) async {
    final String pathA = params['pathA'];
    final String pathB = params['pathB'];
    final String outputPath = params['outputPath'];
    final bool reverseA = params['reverseA'];
    final bool reverseB = params['reverseB'];
    final int rotationA = params['rotationA'];
    final int rotationB = params['rotationB'];
    final RootIsolateToken token = params['token'];
    final SendPort sendPort = params['sendPort'];

    try {
      BackgroundIsolateBinaryMessenger.ensureInitialized(token);
      final sf.PdfDocument finalDoc = sf.PdfDocument();
      finalDoc.pageSettings.margins.all = 0;
      
      final bytesA = await File(pathA).readAsBytes();
      final bytesB = await File(pathB).readAsBytes();
      
      final sf.PdfDocument docA = sf.PdfDocument(inputBytes: bytesA);
      final sf.PdfDocument docB = sf.PdfDocument(inputBytes: bytesB);

      int maxPages = docA.pages.count > docB.pages.count ? docA.pages.count : docB.pages.count;

      final int rotA = rotationA;
      final int rotB = rotationB;

      for (int i = 0; i < maxPages; i++) {
        sendPort.send(i / maxPages);
        
        if (i < docA.pages.count) {
          int index = reverseA ? (docA.pages.count - 1 - i) : i;
          final sf.PdfPage page = docA.pages[index];
          final sf.PdfTemplate template = page.createTemplate();
          finalDoc.pageSettings.size = PdfService._getRotatedSize(template.size, rotA);
          final sf.PdfPage newPage = finalDoc.pages.add();
          PdfService._drawRotatedTemplate(newPage, template, rotA);
        }
        if (i < docB.pages.count) {
          int index = reverseB ? (docB.pages.count - 1 - i) : i;
          final sf.PdfPage page = docB.pages[index];
          final sf.PdfTemplate template = page.createTemplate();
          finalDoc.pageSettings.size = PdfService._getRotatedSize(template.size, rotB);
          final sf.PdfPage newPage = finalDoc.pages.add();
          PdfService._drawRotatedTemplate(newPage, template, rotB);
        }
      }

      sendPort.send(0.9);
      final List<int> resultBytes = await finalDoc.save();
      docA.dispose();
      docB.dispose();
      finalDoc.dispose();

      await File(outputPath).writeAsBytes(resultBytes);
      sendPort.send(1.0);
      sendPort.send(outputPath);
    } catch (e) {
      sendPort.send("ERROR: $e");
    }
  }
  /// Interleaves multiple sets of PDFs and merges them in a background isolate.
  Future<String> batchInterleavePdfs({
    required List<InterleaveSet> sets,
    required String outputPath,
    void Function(double)? onProgress,
  }) async {
    debugPrint("[PdfService] Starting background batchInterleavePdfs with ${sets.length} sets");
    final receivePort = ReceivePort();
    final token = RootIsolateToken.instance!;

    final isolate = await Isolate.spawn(
      _batchInterleaveIsolateEntry,
      {
        'sets': sets.map((s) => s.toJson()).toList(),
        'outputPath': outputPath,
        'token': token,
        'sendPort': receivePort.sendPort,
      },
    );

    final completer = Completer<String>();

    receivePort.listen((message) {
      if (message is double) {
        if (onProgress != null) onProgress(message);
      } else if (message is String) {
        if (message.startsWith("ERROR:")) {
          completer.completeError(message.replaceFirst("ERROR:", ""));
        } else {
          completer.complete(message);
        }
      }
    });

    try {
      return await completer.future;
    } finally {
      receivePort.close();
      isolate.kill();
    }
  }

  static void _batchInterleaveIsolateEntry(Map<String, dynamic> params) async {
    final List<dynamic> setsJson = params['sets'];
    final String outputPath = params['outputPath'];
    final RootIsolateToken token = params['token'];
    final SendPort sendPort = params['sendPort'];

    try {
      BackgroundIsolateBinaryMessenger.ensureInitialized(token);
      final sf.PdfDocument finalDoc = sf.PdfDocument();
      finalDoc.pageSettings.margins.all = 0;
      
      for (int s = 0; s < setsJson.length; s++) {
        final set = InterleaveSet.fromJson(setsJson[s]);
        
        final bytesA = await File(set.pathA).readAsBytes();
        final bytesB = await File(set.pathB).readAsBytes();
        
        final sf.PdfDocument docA = sf.PdfDocument(inputBytes: bytesA);
        final sf.PdfDocument docB = sf.PdfDocument(inputBytes: bytesB);

        int maxPages = docA.pages.count > docB.pages.count ? docA.pages.count : docB.pages.count;

        final int rotA = set.rotationA;
        final int rotB = set.rotationB;

        for (int i = 0; i < maxPages; i++) {
          // Approximate progress across all sets
          sendPort.send((s + (i / maxPages)) / setsJson.length);
          
          if (i < docA.pages.count) {
            int index = set.reverseA ? (docA.pages.count - 1 - i) : i;
            final sf.PdfPage page = docA.pages[index];
            final sf.PdfTemplate template = page.createTemplate();
            finalDoc.pageSettings.size = PdfService._getRotatedSize(template.size, rotA);
            final sf.PdfPage newPage = finalDoc.pages.add();
            PdfService._drawRotatedTemplate(newPage, template, rotA);
          }
          if (i < docB.pages.count) {
            int index = set.reverseB ? (docB.pages.count - 1 - i) : i;
            final sf.PdfPage page = docB.pages[index];
            final sf.PdfTemplate template = page.createTemplate();
            finalDoc.pageSettings.size = PdfService._getRotatedSize(template.size, rotB);
            final sf.PdfPage newPage = finalDoc.pages.add();
            PdfService._drawRotatedTemplate(newPage, template, rotB);
          }
        }
        
        docA.dispose();
        docB.dispose();
      }

      sendPort.send(0.95);
      final List<int> resultBytes = await finalDoc.save();
      finalDoc.dispose();

      await File(outputPath).writeAsBytes(resultBytes);
      sendPort.send(1.0);
      sendPort.send(outputPath);
    } catch (e) {
      sendPort.send("ERROR: $e");
    }
  }
}
