import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';
import '../services/photo_service.dart';

/// 全局状态管理：使用 ChangeNotifier + Provider 模式
/// 管理照片列表、滑动进度、待删除标记等所有应用状态
class PhotosProvider extends ChangeNotifier {
  final PhotoService _photoService = PhotoService();

  // ============================================================
  // 状态变量
  // ============================================================

  /// 所有照片/视频列表（按创建时间倒序）
  List<AssetEntity> _allPhotos = [];
  List<AssetEntity> get allPhotos => _allPhotos;

  /// 当前正在展示的照片索引
  int _currentIndex = 0;
  int get currentIndex => _currentIndex;

  /// 当前展示的照片资源（便捷访问器）
  AssetEntity? get currentPhoto {
    if (_allPhotos.isEmpty || _currentIndex >= _allPhotos.length) return null;
    return _allPhotos[_currentIndex];
  }

  /// 标记为"待删除"的照片 ID 集合
  final Set<String> _deleteMarkedIds = {};
  Set<String> get deleteMarkedIds => _deleteMarkedIds;

  /// 获取所有已标记为待删除的照片实体列表（保持原顺序）
  List<AssetEntity> get deleteMarkedPhotos {
    return _allPhotos.where((p) => _deleteMarkedIds.contains(p.id)).toList();
  }

  /// 是否正在加载数据
  bool _isLoading = false;
  bool get isLoading => _isLoading;

  /// 错误信息
  String? _error;
  String? get error => _error;

  /// 是否有相册权限
  bool _hasPermission = false;
  bool get hasPermission => _hasPermission;

  /// 权限是否被永久拒绝
  bool _isPermanentlyDenied = false;
  bool get isPermanentlyDenied => _isPermanentlyDenied;

  /// 本次会话中已确认删除的数量（用于反馈）
  int _deletedCount = 0;
  int get deletedCount => _deletedCount;

  // ============================================================
  // 计算属性
  // ============================================================

  /// 照片总数
  int get totalCount => _allPhotos.length;

  /// 待删除数量
  int get deleteCount => _deleteMarkedIds.length;

  /// 进度文本，如"第 5 张 / 共 200 张"
  String get progressText {
    if (_allPhotos.isEmpty) return '';
    return '第 ${_currentIndex + 1} 张 / 共 $totalCount 张';
  }

  /// 是否还有下一张照片
  bool get hasNext => _currentIndex < _allPhotos.length - 1;

  /// 是否已全部浏览完毕
  bool get isAllProcessed => _currentIndex >= _allPhotos.length;

  /// 按月份分组（用于分组清理）
  List<MapEntry<String, List<AssetEntity>>> get groupedByMonth {
    return _photoService.groupByMonthSorted(_allPhotos);
  }

  // ============================================================
  // 核心操作
  // ============================================================

  /// 初始化：请求权限 → 加载照片列表
  Future<void> initialize() async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    // 1. 请求权限
    _hasPermission = await _photoService.requestPermission();

    if (!_hasPermission) {
      _isPermanentlyDenied = await _photoService.isPermanentlyDenied();
      _isLoading = false;
      _error = _isPermanentlyDenied
          ? '相册权限已被拒绝，请在系统设置中手动开启'
          : '需要相册访问权限才能使用此功能';
      notifyListeners();
      return;
    }

    // 2. 加载照片
    try {
      _allPhotos = await _photoService.loadAllMedia();
      _currentIndex = 0;
      _deleteMarkedIds.clear();
      _deletedCount = 0;
      _error = null;
    } catch (e) {
      _error = '加载照片失败，请重试';
    }

    _isLoading = false;
    notifyListeners();
  }

  /// 标记当前照片为"待删除"（左滑触发）
  void markCurrentForDeletion() {
    if (currentPhoto == null) return;
    _deleteMarkedIds.add(currentPhoto!.id);
    notifyListeners();
  }

  /// 取消单张照片的删除标记（在待删除列表中使用）
  void unmarkDeletion(String photoId) {
    _deleteMarkedIds.remove(photoId);
    notifyListeners();
  }

  /// 批量取消删除标记
  void unmarkMultipleDeletions(List<String> photoIds) {
    _deleteMarkedIds.removeAll(photoIds);
    notifyListeners();
  }

  /// 移到下一张照片（右滑保留后触发）
  void advanceToNext() {
    if (hasNext) {
      _currentIndex++;
      notifyListeners();
    }
  }

  /// 撤销最近一次标记（主界面快速撤销）
  void undoLastMark() {
    if (currentPhoto != null &&
        _deleteMarkedIds.contains(currentPhoto!.id)) {
      _deleteMarkedIds.remove(currentPhoto!.id);
      notifyListeners();
    }
  }

  /// 确认删除所有标记的照片（或指定的照片列表）
  /// [specificIds] 可选，指定要删除的 ID 子集，默认删除全部已标记的照片
  /// 返回成功删除的数量
  Future<int> confirmDelete({List<String>? specificIds}) async {
    final List<String> idsToDelete =
        specificIds ?? _deleteMarkedIds.toList();
    if (idsToDelete.isEmpty) return 0;

    // 调用系统 API 删除
    final List<String> deletedIds =
        await _photoService.deleteAssets(idsToDelete);

    // 更新本地状态
    _deleteMarkedIds.removeAll(deletedIds);
    _allPhotos.removeWhere((photo) => deletedIds.contains(photo.id));
    _deletedCount += deletedIds.length;

    // 调整当前索引（防止越界）
    if (_currentIndex >= _allPhotos.length) {
      _currentIndex = _allPhotos.isNotEmpty ? _allPhotos.length - 1 : 0;
    }

    notifyListeners();
    return deletedIds.length;
  }

  /// 打开系统设置（权限被永久拒绝时使用）
  Future<void> goToAppSettings() async {
    await _photoService.openSettings();
  }

  /// 重新加载（从设置返回后或错误恢复时使用）
  Future<void> retryLoad() async {
    await initialize();
  }
}
