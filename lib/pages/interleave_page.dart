import 'package:flutter/material.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_picker/file_picker.dart';
import '../services/pdf_service.dart';
import '../main.dart';
import 'package:path/path.dart' as p;

class InterleavePage extends StatefulWidget {
  const InterleavePage({super.key});

  @override
  State<InterleavePage> createState() => _InterleavePageState();
}

class _InterleaveSetData {
  String? pathA;
  String? pathB;
  bool reverseA = false;
  bool reverseB = false;
  int rotationA = 0;
  int rotationB = 0;
  bool isDraggingA = false;
  bool isDraggingB = false;
}

class _InterleavePageState extends State<InterleavePage> {
  final List<_InterleaveSetData> _sets = [_InterleaveSetData()];
  bool _isProcessing = false;
  double _progress = 0;
  final TextEditingController _outputController = TextEditingController();
  final PdfService _pdfService = PdfService();

  @override
  void dispose() {
    _outputController.dispose();
    super.dispose();
  }

  void _addSet() {
    setState(() {
      _sets.add(_InterleaveSetData());
    });
  }

  void _removeSet(int index) {
    if (_sets.length > 1) {
      setState(() {
        _sets.removeAt(index);
      });
    } else {
      setState(() {
        _sets[0] = _InterleaveSetData();
      });
    }
    _updateOutputPath();
  }

  void _pickFile(int setIndex, bool isA) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
    );
    if (result != null) {
      setState(() {
        if (isA) {
          _sets[setIndex].pathA = result.files.single.path;
        } else {
          _sets[setIndex].pathB = result.files.single.path;
        }
        _updateOutputPath();
      });
    }
  }

  void _updateOutputPath() {
    if (_sets.any((s) => s.pathA != null && s.pathB != null) && _outputController.text.isEmpty) {
      final firstValidSet = _sets.firstWhere((s) => s.pathA != null || s.pathB != null);
      final String? baseFile = firstValidSet.pathA ?? firstValidSet.pathB;
      if (baseFile != null) {
        String dir = p.dirname(baseFile);
        _outputController.text = p.join(dir, "batch_interleaved_${DateTime.now().millisecondsSinceEpoch}.pdf");
      }
    }
  }

  void _pickOutputPath() async {
    String? result = await FilePicker.platform.saveFile(
      dialogTitle: '저장 위치 선택',
      fileName: p.basename(_outputController.text.isEmpty ? "interleaved.pdf" : _outputController.text),
      type: FileType.custom,
      allowedExtensions: ['pdf'],
    );
    if (result != null) {
      if (!result.toLowerCase().endsWith('.pdf')) result += '.pdf';
      setState(() => _outputController.text = result!);
    }
  }

  void _performInterleave() async {
    final validSets = _sets.where((s) => s.pathA != null && s.pathB != null).toList();
    if (validSets.isEmpty || _outputController.text.isEmpty) {
      AppToast.show(context, "최소 한 세트의 파일을 모두 선택하고 출력 경로를 지정해 주세요.", isError: true);
      return;
    }

    setState(() {
      _isProcessing = true;
      _progress = 0;
    });

    try {
      final serviceSets = validSets.map((s) => InterleaveSet(
        pathA: s.pathA!,
        pathB: s.pathB!,
        reverseA: s.reverseA,
        reverseB: s.reverseB,
        rotationA: s.rotationA,
        rotationB: s.rotationB,
      )).toList();

      final result = await _pdfService.batchInterleavePdfs(
        sets: serviceSets,
        outputPath: _outputController.text,
        onProgress: (p) => setState(() => _progress = p),
      );
      
      if (mounted) {
        AppToast.show(context, "배치 교차 병합이 완료되었습니다: ${p.basename(result)}");
      }
    } catch (e) {
      if (mounted) {
        AppToast.show(context, "교차 병합 오류: $e", isError: true);
      }
    } finally {
      if (mounted) {
        setState(() => _isProcessing = false);
      }
    }
  }

  Widget _buildRotationSelectorForInterleave(int setIndex, bool isA) {
    final set = _sets[setIndex];
    final int rotation = isA ? set.rotationA : set.rotationB;
    
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      height: 24,
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(6),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<int>(
          value: rotation,
          items: [0, 90, 180, 270].map((angle) => DropdownMenuItem<int>(
            value: angle,
            child: Text("$angle°", style: const TextStyle(fontSize: 10, color: Colors.white)),
          )).toList(),
          onChanged: (v) {
            if (v != null) {
              setState(() {
                if (isA) {
                  set.rotationA = v;
                } else {
                  set.rotationB = v;
                }
              });
            }
          },
          dropdownColor: const Color(0xFF1E293B),
          icon: const Icon(Icons.rotate_right_rounded, size: 12, color: Color(0xFF818CF8)),
        ),
      ),
    );
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
            _buildSetsSection(),
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
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                "교차 병합",
                style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: Colors.white),
              ),
              SizedBox(height: 4),
              Text(
                "여러 세트의 PDF 파일을 각각 교차 병합한 후 하나로 합칩니다.",
                style: TextStyle(color: Color(0xFF94A3B8), fontSize: 16),
              ),
            ],
          ),
        ),
        ElevatedButton.icon(
          onPressed: _isProcessing ? null : _addSet,
          icon: const Icon(Icons.add_rounded, size: 20),
          label: const Text("세트 추가"),
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF6366F1),
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          ),
        ),
      ],
    );
  }

  Widget _buildSetsSection() {
    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: _sets.length,
      separatorBuilder: (context, index) => const SizedBox(height: 32),
      itemBuilder: (context, index) => _buildSetCard(index),
    );
  }

  Widget _buildSetCard(int index) {
    final set = _sets[index];
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B).withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(32),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                "세트 ${index + 1}",
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF818CF8)),
              ),
              if (_sets.length > 1 || set.pathA != null || set.pathB != null)
                IconButton(
                  icon: const Icon(Icons.delete_outline_rounded, color: Colors.white24),
                  onPressed: () => _removeSet(index),
                ),
            ],
          ),
          const SizedBox(height: 20),
          _buildFileSlot(index, true),
          const SizedBox(height: 16),
          const Center(child: Icon(Icons.sync_alt_rounded, color: Colors.white10, size: 20)),
          const SizedBox(height: 16),
          _buildFileSlot(index, false),
        ],
      ),
    );
  }

  Widget _buildFileSlot(int setIndex, bool isA) {
    final set = _sets[setIndex];
    final path = isA ? set.pathA : set.pathB;
    final isDragging = isA ? set.isDraggingA : set.isDraggingB;
    final isReverse = isA ? set.reverseA : set.reverseB;
    final label = isA ? "파일 A (홀수 페이지)" : "파일 B (짝수 페이지)";
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: const TextStyle(fontWeight: FontWeight.w600, color: Colors.white60, fontSize: 13)),
            Row(
              children: [
                _buildRotationSelectorForInterleave(setIndex, isA),
                const SizedBox(width: 8),
                const Text("역순", style: TextStyle(fontSize: 11, color: Colors.white60)),
                const SizedBox(width: 4),
                SizedBox(
                  height: 20,
                  child: Switch(
                    value: isReverse,
                    onChanged: (v) => setState(() {
                      if (isA) {
                        set.reverseA = v;
                      } else {
                        set.reverseB = v;
                      }
                    }),
                    activeThumbColor: const Color(0xFF818CF8),
                    activeTrackColor: const Color(0xFF6366F1).withValues(alpha: 0.5),
                    inactiveThumbColor: const Color(0xFF475569),
                    inactiveTrackColor: const Color(0xFF334155),
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 8),
        DropTarget(
          onDragEntered: (_) => setState(() {
            if (isA) {
              set.isDraggingA = true;
            } else {
              set.isDraggingB = true;
            }
          }),
          onDragExited: (_) => setState(() {
            if (isA) {
              set.isDraggingA = false;
            } else {
              set.isDraggingB = false;
            }
          }),
          onDragDone: (details) {
            setState(() { 
              if(isA) {
                set.isDraggingA = false;
                set.pathA = details.files.first.path;
              } else {
                set.isDraggingB = false;
                set.pathB = details.files.first.path;
              }
              _updateOutputPath();
            });
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            height: 80,
            decoration: BoxDecoration(
              color: const Color(0xFF0F172A),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isDragging ? const Color(0xFF818CF8) : Colors.white.withValues(alpha: 0.05),
                width: isDragging ? 2 : 1,
              ),
            ),
            child: InkWell(
              onTap: () => _pickFile(setIndex, isA),
              borderRadius: BorderRadius.circular(16),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  children: [
                    Icon(
                      path == null ? Icons.add_circle_outline_rounded : Icons.picture_as_pdf_rounded,
                      size: 24,
                      color: path == null ? const Color(0xFF475569) : const Color(0xFF818CF8),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        path == null ? "파일 선택" : p.basename(path),
                        style: TextStyle(
                          fontSize: 14,
                          color: path == null ? const Color(0xFF64748B) : Colors.white,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (path != null)
                      IconButton(
                        icon: const Icon(Icons.close_rounded, size: 18, color: Colors.white24),
                        onPressed: () => setState(() {
                          if (isA) {
                            set.pathA = null;
                          } else {
                            set.pathB = null;
                          }
                        }),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildOutputSection() {
    final bool isEnabled = _sets.any((s) => s.pathA != null && s.pathB != null);
    
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

  Widget _buildActionFooter() {
    final bool isEnabled = _sets.any((s) => s.pathA != null && s.pathB != null);
    
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
                    Text("처리 중...", style: TextStyle(color: const Color(0xFF94A3B8), fontSize: 12)),
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
              onPressed: (isEnabled && !_isProcessing) ? _performInterleave : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF6366F1),
                foregroundColor: Colors.white,
                disabledBackgroundColor: const Color(0xFF1E293B),
              ),
              child: _isProcessing
                  ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text("배치 교차 병합 시작", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            ),
          ),
        ),
      ],
    );
  }
}
