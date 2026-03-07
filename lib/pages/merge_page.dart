import 'package:flutter/material.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_picker/file_picker.dart';
import '../services/pdf_service.dart';
import '../main.dart'; // Import for AppToast
import 'package:path/path.dart' as p;

class MergePage extends StatefulWidget {
  const MergePage({super.key});

  @override
  State<MergePage> createState() => _MergePageState();
}

class _MergePageState extends State<MergePage> {
  final List<PdfFileItem> _files = [];
  bool _isProcessing = false;
  double _progress = 0;
  final TextEditingController _outputController = TextEditingController();
  final PdfService _pdfService = PdfService();
  bool _isDragging = false;

  @override
  void dispose() {
    _outputController.dispose();
    super.dispose();
  }

  void _addFiles(List<String> paths) {
    setState(() {
      for (var path in paths) {
        if (path.toLowerCase().endsWith('.pdf')) {
          _files.add(PdfFileItem(path: path));
        }
      }
      if (_files.isNotEmpty && _outputController.text.isEmpty) {
        // Default to Downloads folder if possible
        String dir = p.dirname(_files.first.path);
        _outputController.text = p.join(dir, "merged_${DateTime.now().millisecondsSinceEpoch}.pdf");
      }
    });
  }

  void _pickFiles() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
      allowMultiple: true,
    );
    if (result != null) {
      _addFiles(result.paths.whereType<String>().toList());
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

  void _performMerge() async {
    if (_files.isEmpty || _outputController.text.isEmpty) {
      AppToast.show(context, "파일을 추가하고 출력 경로를 지정해 주세요.", isError: true);
      return;
    }

    setState(() {
      _isProcessing = true;
      _progress = 0;
    });

    try {
      final paths = _files.map((f) => f.path).toList();
      final reverses = _files.map((f) => f.isReverse).toList();
      final rotations = _files.map((f) => f.rotation).toList();
      final outputName = _outputController.text;

      final result = await _pdfService.mergePdfs(
        paths: paths, 
        outputName: outputName, 
        reverseFlags: reverses,
        rotations: rotations,
        onProgress: (p) => setState(() => _progress = p),
      );
      
      if (mounted) {
        AppToast.show(context, "병합이 완료되었습니다: ${p.basename(result)}");
      }
    } catch (e) {
      if (mounted) {
        AppToast.show(context, "병합 오류: $e", isError: true);
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
            _buildFileListSection(),
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

  Widget _buildFileListSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_files.isEmpty) 
          SizedBox(height: 160, width: double.infinity, child: _buildEmptyState())
        else 
          _buildFileList(),
      ],
    );
  }

  Widget _buildHeader() {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          "PDF 합치기",
          style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: Colors.white),
        ),
        SizedBox(height: 4),
        Text(
          "여러 PDF 파일을 하나로 합치고 순서와 회전 방향을 자유롭게 조정하세요.",
          style: TextStyle(color: Color(0xFF94A3B8), fontSize: 16),
        ),
      ],
    );
  }


  Widget _buildOutputSection() {
    final bool isEnabled = _files.isNotEmpty;
    
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
                hintText: isEnabled ? "출력 파일 경로" : "파일을 먼저 추가해 주세요",
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

  Widget _buildEmptyState() {
    return DropTarget(
      onDragEntered: (_) => setState(() => _isDragging = true),
      onDragExited: (_) => setState(() => _isDragging = false),
      onDragDone: (details) {
        setState(() => _isDragging = false);
        _addFiles(details.files.map((f) => f.path).toList());
      },
      child: Container(
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
              child: const Icon(Icons.add_to_photos_rounded, size: 24, color: Color(0xFF818CF8)),
            ),
            const SizedBox(height: 12),
            const Text("PDF 파일을 여기에 끌어다 놓으세요", style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500, color: Colors.white)),
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

  Widget _buildFileList() {
    return DropTarget(
      onDragEntered: (_) => setState(() => _isDragging = true),
      onDragExited: (_) => setState(() => _isDragging = false),
      onDragDone: (details) {
        setState(() => _isDragging = false);
        _addFiles(details.files.map((f) => f.path).toList());
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: _isDragging ? const Color(0xFF818CF8) : Colors.transparent,
            width: 2,
          ),
          color: _isDragging ? const Color(0xFF6366F1).withValues(alpha: 0.05) : Colors.transparent,
        ),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text("${_files.length}개의 파일 선택됨", style: const TextStyle(color: Color(0xFF94A3B8))),
                TextButton.icon(
                  onPressed: _pickFiles,
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text("파일 추가"),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _buildFileListItems(),
          ],
        ),
      ),
    );
  }

  Widget _buildFileListItems() {
    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: _files.length,
      itemBuilder: (context, index) => _buildFileItem(index),
    );
  }

  Widget _buildFileItem(int index) {
    final item = _files[index];
    return Container(
      key: ValueKey(item.path + index.toString()),
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.03)),
      ),
      child: Row(
        children: [
          const Icon(Icons.drag_indicator_rounded, color: Color(0xFF475569)),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(p.basename(item.path), style: const TextStyle(fontWeight: FontWeight.w600, color: Colors.white)),
                Text(item.path, style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)), overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
          _buildRotationSelector(item),
          const SizedBox(width: 16),
          Switch(
            value: item.isReverse,
            onChanged: (v) => setState(() => item.isReverse = v),
            activeThumbColor: const Color(0xFF818CF8),
          ),
          const Text("역순", style: TextStyle(fontSize: 12, color: Colors.white70)),
          const SizedBox(width: 12),
          IconButton(
            icon: const Icon(Icons.close_rounded, color: Colors.redAccent, size: 20),
            onPressed: () => setState(() => _files.removeAt(index)),
          ),
        ],
      ),
    );
  }

  Widget _buildRotationSelector(PdfFileItem item) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(8),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<int>(
          value: item.rotation,
          items: [0, 90, 180, 270].map((angle) => DropdownMenuItem<int>(
            value: angle,
            child: Text("$angle°", style: const TextStyle(fontSize: 12, color: Colors.white)),
          )).toList(),
          onChanged: (v) {
            if (v != null) {
              setState(() => item.rotation = v);
            }
          },
          dropdownColor: const Color(0xFF1E293B),
          icon: const Icon(Icons.rotate_right_rounded, size: 16, color: Color(0xFF818CF8)),
        ),
      ),
    );
  }

  Widget _buildActionFooter() {
    final bool isEnabled = _files.isNotEmpty;
    
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
                    Text("처리 중...", style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 12)),
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
              onPressed: (isEnabled && !_isProcessing) ? _performMerge : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF6366F1),
                foregroundColor: Colors.white,
                disabledBackgroundColor: const Color(0xFF1E293B),
              ),
              child: _isProcessing
                  ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text("병합 시작", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            ),
          ),
        ),
      ],
    );
  }
}

class PdfFileItem {
  final String path;
  bool isReverse;
  int rotation; // 0, 90, 180, 270

  PdfFileItem({
    required this.path, 
    this.isReverse = false,
    this.rotation = 0,
  });
}
