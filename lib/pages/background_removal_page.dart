import 'package:flutter/material.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import '../services/pdf_service.dart';
import '../main.dart';

class BackgroundRemovalPage extends StatefulWidget {
  const BackgroundRemovalPage({super.key});

  @override
  State<BackgroundRemovalPage> createState() => _BackgroundRemovalPageState();
}

class _BackgroundRemovalPageState extends State<BackgroundRemovalPage> {
  double _whitePoint = 220;
  double _blackPoint = 50;
  bool _isProcessing = false;
  double _progress = 0;
  String? _inputPath;
  final TextEditingController _outputController = TextEditingController();
  final PdfService _pdfService = PdfService();
  bool _isDragging = false;

  @override
  void dispose() {
    _outputController.dispose();
    super.dispose();
  }

  void _onFilesDropped(DropDoneDetails details) async {
    if (details.files.isEmpty) return;
    
    final file = details.files.first;
    if (!file.path.toLowerCase().endsWith('.pdf')) {
      AppToast.show(context, "PDF 파일만 지원합니다.", isError: true);
      return;
    }

    setState(() {
      _inputPath = file.path;
      _outputController.text = p.join(
        p.dirname(_inputPath!),
        '${p.basenameWithoutExtension(_inputPath!)}_cleaned.pdf',
      );
    });
  }

  void _pickFiles() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
    );
    if (result != null) {
      final path = result.files.single.path;
      if (path != null) {
        setState(() {
          _inputPath = path;
          _outputController.text = p.join(
            p.dirname(_inputPath!),
            '${p.basenameWithoutExtension(_inputPath!)}_cleaned.pdf',
          );
        });
      }
    }
  }

  void _pickOutputPath() async {
    String? result = await FilePicker.platform.saveFile(
      dialogTitle: '저장 위치 선택',
      fileName: p.basename(_outputController.text),
      type: FileType.custom,
      allowedExtensions: ['pdf'],
    );
    if (result != null) {
      if (!result.toLowerCase().endsWith('.pdf')) result += '.pdf';
      setState(() => _outputController.text = result!);
    }
  }

  void _startProcessing() async {
    if (_inputPath == null || _outputController.text.isEmpty) return;

    setState(() {
      _isProcessing = true;
      _progress = 0;
    });

    try {
      final outputPath = _outputController.text;
      final result = await _pdfService.removeBackground(
        inputPath: _inputPath!, 
        outputPath: outputPath,
        whitePoint: _whitePoint.toInt(), 
        blackPoint: _blackPoint.toInt(),
        onProgress: (p) => setState(() => _progress = p),
      );
      
      if (mounted) {
        AppToast.show(context, "보정이 완료되었습니다: ${p.basename(result)}");
      }
    } catch (e, stack) {
      debugPrint("Page Level Error: $e");
      debugPrint("Stack: $stack");
      if (mounted) {
        AppToast.show(context, "처리 중 오류 발생: $e", isError: true);
      }
    } finally {
      if (mounted) {
        setState(() => _isProcessing = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeader(),
            const SizedBox(height: 40),
            _buildSettingsCard(),
            const SizedBox(height: 32),
            _buildInputSection(),
            const SizedBox(height: 48),
            const Divider(color: Colors.white10),
            const SizedBox(height: 40),
            _buildOutputSection(),
            const SizedBox(height: 32),
            _buildActionFooter(),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          "배경 제거",
          style: GoogleFonts.outfit(fontSize: 32, fontWeight: FontWeight.bold, color: Colors.white),
        ),
        const SizedBox(height: 4),
        Text(
          "스마트한 PDF 이미지 보정 및 배경 제거를 통해 가독성을 높이세요.",
          style: TextStyle(color: const Color(0xFF94A3B8), fontSize: 16),
        ),
      ],
    );
  }


  Widget _buildInputSection() {
    return _inputPath == null ? _buildDropZone() : _buildSelectedFileCard();
  }

  Widget _buildSelectedFileCard() {
    return DropTarget(
      onDragEntered: (_) => setState(() => _isDragging = true),
      onDragExited: (_) => setState(() => _isDragging = false),
      onDragDone: (details) {
        setState(() => _isDragging = false);
        _onFilesDropped(details);
      },
      child: Container(
        padding: const EdgeInsets.all(20),
        width: double.infinity,
        decoration: BoxDecoration(
          color: const Color(0xFF1E293B),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: _isDragging ? const Color(0xFF818CF8) : Colors.white.withValues(alpha: 0.05),
            width: _isDragging ? 2 : 1,
          ),
          boxShadow: _isDragging ? [
            BoxShadow(color: const Color(0xFF6366F1).withValues(alpha: 0.2), blurRadius: 12, spreadRadius: 2)
          ] : null,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF818CF8).withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.picture_as_pdf_rounded, size: 24, color: Color(0xFF818CF8)),
            ),
            const SizedBox(height: 12),
            Text(p.basename(_inputPath!), style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
            const SizedBox(height: 2),
            Text(_inputPath!, style: TextStyle(color: const Color(0xFF64748B), fontSize: 13), textAlign: TextAlign.center),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: () => setState(() => _inputPath = null),
              icon: const Icon(Icons.refresh_rounded, size: 16),
              label: const Text("파일 다시 선택"),
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFF94A3B8),
                side: const BorderSide(color: Color(0xFF334155)),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOutputSection() {
    final bool isEnabled = _inputPath != null;
    
    return Opacity(
      opacity: isEnabled ? 1.0 : 0.5,
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: const Color(0xFF1E293B),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("출력 설정", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
            const SizedBox(height: 16),
            TextField(
              controller: _outputController,
              enabled: isEnabled,
              style: const TextStyle(fontSize: 14),
              decoration: InputDecoration(
                hintText: isEnabled ? "출력 파일 경로" : "파일을 먼저 선택해 주세요",
                filled: true,
                fillColor: const Color(0xFF0F172A),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: isEnabled ? _pickOutputPath : null,
                icon: const Icon(Icons.folder_open_rounded, size: 18),
                label: const Text("저장 위치 변경"),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF334155),
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: const Color(0xFF0F172A),
                  disabledForegroundColor: Colors.white24,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSettingsCard() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text("이미지 보정 설정", style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
          const SizedBox(height: 16),
          Row(
            spacing: 24,
            children: [
              Expanded(
                child: _buildSliderField("배경 밝기", _whitePoint, (v) => setState(() => _whitePoint = v), const Color(0xFF818CF8)),
              ),
              Expanded(
                child: _buildSliderField("글자 농도", _blackPoint, (v) => setState(() => _blackPoint = v), const Color(0xFFF87171)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSliderField(String label, double value, ValueChanged<double> onChanged, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: Text(label, style: const TextStyle(fontWeight: FontWeight.w600, color: Colors.white), overflow: TextOverflow.ellipsis)),
            const SizedBox(width: 8),
            Text(value.toInt().toString(), style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 16)),
          ],
        ),
        const SizedBox(height: 4),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            activeTrackColor: color,
            inactiveTrackColor: color.withValues(alpha: 0.1),
            thumbColor: Colors.white,
            overlayColor: color.withValues(alpha: 0.2),
          ),
          child: Slider(
            value: value,
            min: 0,
            max: 255,
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }

  Widget _buildDropZone() {
    return DropTarget(
      onDragEntered: (_) => setState(() => _isDragging = true),
      onDragExited: (_) => setState(() => _isDragging = false),
      onDragDone: (details) {
        setState(() => _isDragging = false);
        _onFilesDropped(details);
      },
      child: Container(
        width: double.infinity,
        height: 160,
        decoration: BoxDecoration(
          color: const Color(0xFF1E293B).withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: _isDragging ? const Color(0xFF818CF8) : Colors.white.withValues(alpha: 0.05), 
            width: _isDragging ? 2 : 1,
            style: BorderStyle.solid
          ),
          boxShadow: _isDragging ? [
            BoxShadow(color: const Color(0xFF6366F1).withValues(alpha: 0.2), blurRadius: 12, spreadRadius: 2)
          ] : null,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF6366F1).withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.cloud_upload_rounded, size: 24, color: Color(0xFF818CF8)),
            ),
            const SizedBox(height: 12),
            Text("보정할 PDF 파일을 여기에 끌어다 놓으세요", style: GoogleFonts.outfit(fontSize: 15, fontWeight: FontWeight.w500, color: Colors.white)),
            const SizedBox(height: 2),
            TextButton(
              onPressed: _pickFiles,
              child: const Text("또는 파일 선택하기", style: TextStyle(color: Color(0xFF818CF8), fontWeight: FontWeight.w600)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionFooter() {
    final bool isEnabled = _inputPath != null;
    
    return Column(
      children: [
        if (_isProcessing) ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 12),
            child: Column(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: LinearProgressIndicator(
                    value: _progress,
                    minHeight: 8,
                    backgroundColor: const Color(0xFF0F172A),
                    valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF6366F1)),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text("보정 중...", style: TextStyle(color: const Color(0xFF94A3B8), fontSize: 12)),
                    Text("${(_progress * 100).toInt()}%", style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF818CF8))),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
        ],
        SizedBox(
          width: double.infinity,
          height: 56,
          child: Opacity(
            opacity: isEnabled ? 1.0 : 0.5,
            child: ElevatedButton(
              onPressed: (isEnabled && !_isProcessing) ? _startProcessing : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF6366F1),
                foregroundColor: Colors.white,
                disabledBackgroundColor: const Color(0xFF1E293B),
              ),
              child: _isProcessing
                  ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text("보정 시작", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            ),
          ),
        ),
      ],
    );
  }
}
