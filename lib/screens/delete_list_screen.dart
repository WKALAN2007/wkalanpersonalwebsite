import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:provider/provider.dart';
import '../providers/photos_provider.dart';
import '../services/photo_service.dart';

/// 待删除照片列表界面
/// 按月份分组展示所有标记为待删除的照片
/// 支持反悔取消标记、一键清理整月、批量确认删除
class DeleteListScreen extends StatefulWidget {
  const DeleteListScreen({super.key});

  @override
  State<DeleteListScreen> createState() => _DeleteListScreenState();
}

class _DeleteListScreenState extends State<DeleteListScreen> {
  final PhotoService _photoService = PhotoService();

  /// 缩略图缓存（key = asset.id, value = 缩略图字节数据）
  final Map<String, Uint8List?> _thumbnailCache = {};

  /// 被选中"反悔"的照片 ID 集合
  final Set<String> _selectedUndoIds = {};

  /// 是否处于全选模式
  bool _isAllSelected = false;

  /// 缓存数量上限（防止内存溢出）
  static const int _maxCacheSize = 200;

  @override
  void dispose() {
    _thumbnailCache.clear();
    super.dispose();
  }

  // ============================================================
  // 缩略图加载
  // ============================================================

  Future<Uint8List?> _loadThumbnail(AssetEntity entity) async {
    if (_thumbnailCache.containsKey(entity.id)) {
      return _thumbnailCache[entity.id];
    }

    final data = await _photoService.getThumbnail(
      entity: entity,
      width: 200,
      height: 200,
    );

    if (mounted) {
      setState(() {
        // 缓存超限时清空旧缓存
        if (_thumbnailCache.length >= _maxCacheSize) {
          _thumbnailCache.clear();
        }
        _thumbnailCache[entity.id] = data;
      });
    }

    return data;
  }

  // ============================================================
  // UI 构建
  // ============================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('待删除照片'),
        backgroundColor: Colors.grey[950],
        foregroundColor: Colors.white,
        actions: [
          Consumer<PhotosProvider>(
            builder: (context, provider, _) {
              if (provider.deleteCount == 0) {
                return const SizedBox.shrink();
              }
              return TextButton(
                onPressed: () => _toggleSelectAll(provider),
                child: Text(
                  _isAllSelected ? '取消全选' : '全选',
                  style: const TextStyle(color: Colors.white70),
                ),
              );
            },
          ),
        ],
      ),
      body: Consumer<PhotosProvider>(
        builder: (context, provider, _) {
          final photos = provider.deleteMarkedPhotos;

          if (photos.isEmpty) {
            return const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.check_circle, color: Colors.green, size: 64),
                  SizedBox(height: 16),
                  Text('没有待删除的照片',
                      style: TextStyle(color: Colors.white70, fontSize: 16)),
                  SizedBox(height: 8),
                  Text('返回主界面继续筛选',
                      style: TextStyle(color: Colors.white54, fontSize: 14)),
                ],
              ),
            );
          }

          return _buildGroupedList(photos, provider);
        },
      ),
      bottomNavigationBar: Consumer<PhotosProvider>(
        builder: (context, provider, _) {
          final deleteCount = provider.deleteCount;
          if (deleteCount == 0) return const SizedBox.shrink();

          return Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.grey[950],
              border:
                  const Border(top: BorderSide(color: Colors.white12)),
            ),
            child: SafeArea(
              child: Row(
                children: [
                  // 取消标记按钮（选中了照片时显示）
                  if (_selectedUndoIds.isNotEmpty) ...[
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => _undoSelected(provider),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.white,
                          side: const BorderSide(color: Colors.white30),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        child: Text('取消标记 (${_selectedUndoIds.length})'),
                      ),
                    ),
                    const SizedBox(width: 12),
                  ],
                  // 确认删除按钮
                  Expanded(
                    flex: 2,
                    child: ElevatedButton(
                      onPressed: () =>
                          _showConfirmDialog(provider),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      child: Text(
                        '确认删除 $deleteCount 张照片',
                        style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  /// 按月份分组显示的照片列表
  Widget _buildGroupedList(
      List<AssetEntity> photos, PhotosProvider provider) {
    final groupedEntries = _photoService.groupByMonthSorted(photos);

    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 80),
      itemCount: groupedEntries.length,
      itemBuilder: (context, index) {
        final entry = groupedEntries[index];
        return _buildMonthSection(
            entry.key, entry.value, provider);
      },
    );
  }

  /// 单个月份的区块
  Widget _buildMonthSection(
      String month, List<AssetEntity> photos, PhotosProvider provider) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 月份标题行
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(month,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold)),
              Text('${photos.length} 张',
                  style:
                      const TextStyle(color: Colors.white54, fontSize: 13)),
            ],
          ),
        ),

        // 照片缩略图网格（每行 4 张）
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          gridDelegate:
              const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 4,
            crossAxisSpacing: 4,
            mainAxisSpacing: 4,
          ),
          itemCount: photos.length,
          itemBuilder: (context, index) =>
              _buildPhotoTile(photos[index], provider),
        ),

        // 一键清理本月按钮
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => _deleteMonth(month, photos, provider),
              icon: const Icon(Icons.delete_sweep, size: 18),
              label: Text('一键清理本月 (${photos.length}张)'),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.red[300],
                side: BorderSide(color: Colors.red[300]!),
              ),
            ),
          ),
        ),

        const Divider(color: Colors.white12, height: 1),
      ],
    );
  }

  /// 单张照片的缩略图方块
  Widget _buildPhotoTile(AssetEntity entity, PhotosProvider provider) {
    final isSelected = _selectedUndoIds.contains(entity.id);
    final isVideo = _photoService.isVideo(entity);

    return GestureDetector(
      onTap: () => _toggleUndoSelection(entity.id, provider),
      child: Stack(
        fit: StackFit.expand,
        children: [
          // 缩略图
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: FutureBuilder<Uint8List?>(
              future: _loadThumbnail(entity),
              builder: (context, snapshot) {
                if (snapshot.hasData && snapshot.data != null) {
                  return Image.memory(snapshot.data!,
                      fit: BoxFit.cover);
                }
                return Container(
                  color: Colors.grey[850],
                  child: const Center(
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white24),
                  ),
                );
              },
            ),
          ),

          // 视频标识
          if (isVideo)
            const Positioned(
              bottom: 4,
              right: 4,
              child: Icon(Icons.play_circle_fill,
                  color: Colors.white70, size: 18),
            ),

          // 选中覆盖层（蓝色蒙版 + 撤销图标）
          if (isSelected)
            Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(4),
                color: Colors.blue.withValues(alpha: 0.4),
                border: Border.all(color: Colors.blue, width: 2.5),
              ),
              child: const Center(
                child: Icon(Icons.undo, color: Colors.white, size: 28),
              ),
            ),

          // 未选中的轻微红色标记（表示待删除状态）
          if (!isSelected)
            Positioned(
              top: 3,
              right: 3,
              child: Container(
                width: 8,
                height: 8,
                decoration: const BoxDecoration(
                  color: Colors.red,
                  shape: BoxShape.circle,
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ============================================================
  // 交互逻辑
  // ============================================================

  /// 切换单张照片的"反悔选中"状态
  void _toggleUndoSelection(String photoId, PhotosProvider provider) {
    setState(() {
      if (_selectedUndoIds.contains(photoId)) {
        _selectedUndoIds.remove(photoId);
        _isAllSelected = false;
      } else {
        _selectedUndoIds.add(photoId);
        if (_selectedUndoIds.length == provider.deleteCount) {
          _isAllSelected = true;
        }
      }
    });
  }

  /// 全选 / 取消全选
  void _toggleSelectAll(PhotosProvider provider) {
    setState(() {
      if (_isAllSelected) {
        _selectedUndoIds.clear();
        _isAllSelected = false;
      } else {
        _selectedUndoIds.clear();
        _selectedUndoIds
            .addAll(provider.deleteMarkedPhotos.map((p) => p.id));
        _isAllSelected = true;
      }
    });
  }

  /// 取消选中照片的删除标记（反悔）
  void _undoSelected(PhotosProvider provider) {
    provider.unmarkMultipleDeletions(_selectedUndoIds.toList());
    setState(() {
      _selectedUndoIds.clear();
      _isAllSelected = false;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('已取消标记'),
        backgroundColor: Colors.blue,
        duration: Duration(seconds: 2),
      ),
    );
  }

  /// 一键清理某个月的所有待删除照片
  void _deleteMonth(String month, List<AssetEntity> photos,
      PhotosProvider provider) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('一键清理本月照片'),
        content: Text(
          '确定要删除 $month 的 ${photos.length} 张照片吗？\n\n'
          '照片将移入系统"最近删除"，30天内可在相册应用中恢复。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              final ids = photos.map((p) => p.id).toList();
              final count =
                  await provider.confirmDelete(specificIds: ids);
              if (mounted) {
                setState(() {
                  _selectedUndoIds.removeAll(ids);
                  _isAllSelected = false;
                });
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                        '已删除 $count 张照片，30天内可在相册恢复'),
                    backgroundColor: Colors.green,
                    duration: const Duration(seconds: 3),
                  ),
                );
              }
            },
            child: const Text('确定删除',
                style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  /// 确认删除二次弹窗（安全机制）
  void _showConfirmDialog(PhotosProvider provider) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('⚠️ 确认删除'),
        content: Text(
          '即将删除 ${provider.deleteCount} 张照片。\n\n'
          '照片将移入系统"最近删除"相册，\n'
          '30天内可在系统相册中恢复。\n\n'
          '此操作不可撤销，确定继续吗？',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              final count = await provider.confirmDelete();
              if (!mounted) return;

              setState(() {
                _selectedUndoIds.clear();
                _isAllSelected = false;
              });

              // Toast 提示
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                      '已删除 $count 张照片，30天内可在相册恢复'),
                  backgroundColor: Colors.green,
                  duration: const Duration(seconds: 3),
                  behavior: SnackBarBehavior.floating,
                ),
              );

              // 如果全部删完，返回上一页
              if (provider.deleteCount == 0) {
                Navigator.of(context).pop();
              }
            },
            child: const Text('确认删除',
                style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }
}
