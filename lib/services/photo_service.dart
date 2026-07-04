import 'dart:io';
import 'dart:typed_data';
import 'package:photo_manager/photo_manager.dart';
import 'package:permission_handler/permission_handler.dart';

/// 相册服务层：封装所有与相册相关的底层操作
/// 包括权限请求、照片读取、缩略图获取、删除等
class PhotoService {
  // ============================================================
  // 权限管理
  // ============================================================

  /// 请求相册访问权限
  /// 返回 true 表示已授权（完全授权或受限授权）
  Future<bool> requestPermission() async {
    // photo_manager 内置权限请求，自动处理 iOS/Android 平台差异
    // iOS: 请求 NSPhotoLibraryUsageDescription
    // Android 13+: 请求 READ_MEDIA_IMAGES / READ_MEDIA_VIDEO
    // Android 12-: 请求 READ_EXTERNAL_STORAGE
    final PermissionState state = await PhotoManager.requestPermissionExtend();

    if (state == PermissionState.authorized ||
        state == PermissionState.limited) {
      return true;
    }

    return false;
  }

  /// 检查当前是否已有相册权限
  Future<bool> hasPermission() async {
    final PermissionState state = await PhotoManager.requestPermissionExtend();
    return state == PermissionState.authorized ||
        state == PermissionState.limited;
  }

  /// 检查权限是否被永久拒绝（用户选择了"不再询问"）
  /// 此时需要引导用户前往系统设置手动开启
  Future<bool> isPermanentlyDenied() async {
    if (Platform.isIOS) {
      final status = await Permission.photos.status;
      return status.isPermanentlyDenied;
    } else {
      // Android: 检查存储权限
      final status = await Permission.storage.status;
      if (status.isPermanentlyDenied) return true;
      // Android 13+ 检查细粒度媒体权限
      final photosStatus = await Permission.photos.status;
      return photosStatus.isPermanentlyDenied;
    }
  }

  /// 打开系统设置页面，让用户手动开启权限
  Future<bool> openSettings() async {
    return await openAppSettings();
  }

  // ============================================================
  // 照片读取
  // ============================================================

  /// 加载所有照片和视频（分页加载，避免一次性加载过多导致 OOM）
  /// 返回按创建时间倒序排列的列表（最新的在最前面）
  Future<List<AssetEntity>> loadAllMedia() async {
    final List<AssetEntity> allAssets = [];

    // 获取"所有照片"相册路径，onlyAll: true 表示只取汇总路径
    final List<AssetPathEntity> paths = await PhotoManager.getAssetPathList(
      type: RequestType.common, // 包含图片和视频
      onlyAll: true,
    );

    if (paths.isEmpty) return allAssets;

    final AssetPathEntity allPath = paths.first;
    final int totalCount = await allPath.assetCountAsync;

    int page = 0;
    const int pageSize = 200; // 每页 200 张，平衡加载速度和内存

    while (page * pageSize < totalCount) {
      final List<AssetEntity> pageAssets = await allPath.getAssetListPaged(
        page: page,
        size: pageSize,
      );

      if (pageAssets.isEmpty) break;
      allAssets.addAll(pageAssets);
      page++;
    }

    // 按创建时间倒序，最新的照片先展示
    allAssets.sort((a, b) {
      final DateTime dateA = a.createDateTime ?? DateTime(2000);
      final DateTime dateB = b.createDateTime ?? DateTime(2000);
      return dateB.compareTo(dateA);
    });

    return allAssets;
  }

  // ============================================================
  // 缩略图与原图
  // ============================================================

  /// 获取缩略图二进制数据
  /// [entity] 照片/视频资源对象
  /// [width] / [height] 缩略图目标尺寸（像素），建议不超过屏幕宽度
  Future<Uint8List?> getThumbnail({
    required AssetEntity entity,
    int width = 400,
    int height = 400,
  }) async {
    try {
      return await entity.thumbDataWithSize(width, height);
    } catch (_) {
      return null;
    }
  }

  /// 获取原图文件路径
  Future<String?> getOriginalFilePath(AssetEntity entity) async {
    try {
      final file = await entity.file;
      return file?.path;
    } catch (_) {
      return null;
    }
  }

  // ============================================================
  // 删除操作
  // ============================================================

  /// 批量删除照片/视频
  /// 照片会移入系统"最近删除"（iOS 30天内可恢复）/ 回收站（Android）
  /// [ids] 要删除的资源 ID 列表
  /// 返回成功删除的 ID 列表
  Future<List<String>> deleteAssets(List<String> ids) async {
    if (ids.isEmpty) return [];
    try {
      final List<String> result =
          await PhotoManager.editor.deleteWithIds(ids);
      return result;
    } catch (_) {
      return [];
    }
  }

  // ============================================================
  // 工具方法
  // ============================================================

  /// 判断资源是否为视频
  bool isVideo(AssetEntity entity) {
    return entity.type == AssetType.video;
  }

  /// 按年月将照片分组，用于分组清理功能
  /// key 格式: "2024年1月"
  Map<String, List<AssetEntity>> groupByMonth(List<AssetEntity> assets) {
    final Map<String, List<AssetEntity>> grouped = {};

    for (final asset in assets) {
      final DateTime date = asset.createDateTime ?? DateTime(2000);
      final String key = '${date.year}年${date.month}月';
      grouped.putIfAbsent(key, () => []);
      grouped[key]!.add(asset);
    }

    return grouped;
  }

  /// 按月分组排序（降序），返回排序后的条目列表
  List<MapEntry<String, List<AssetEntity>>> groupByMonthSorted(
      List<AssetEntity> assets) {
    final grouped = groupByMonth(assets);
    final entries = grouped.entries.toList();

    // 按每组中第一张照片的日期降序排列
    entries.sort((a, b) {
      final dateA = a.value.first.createDateTime ?? DateTime(2000);
      final dateB = b.value.first.createDateTime ?? DateTime(2000);
      return dateB.compareTo(dateA);
    });

    return entries;
  }
}
