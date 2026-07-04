import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/photos_provider.dart';
import '../services/photo_service.dart';
import 'delete_list_screen.dart';

/// 滑动筛选主界面
/// 核心交互：左滑删除 / 右滑保留，类似 Tinder 卡片滑动
class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen>
    with SingleTickerProviderStateMixin {
  // ---- 动画 ----
  late AnimationController _animController;

  // ---- 拖拽 ----
  double _dragOffset = 0; // 当前拖拽的 X 偏移
  bool _isAnimating = false; // 是否正在执行飞走/回弹动画
  double _animStartValue = 0; // 动画起始值
  double _animTargetValue = 0; // 动画目标值（>0 右飞保留，<0 左飞删除，0 回弹）

  // ---- 图片缓存 ----
  Uint8List? _currentImageData;
  String? _currentImageId;
  bool _isCurrentVideo = false;
  bool _isLoadingImage = false;

  final PhotoService _photoService = PhotoService();

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _animController.addListener(_onAnimationUpdate);
    _animController.addStatusListener(_onAnimationStatusChange);

    // 首帧后初始化数据
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<PhotosProvider>().initialize();
    });
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  // ============================================================
  // 动画回调
  // ============================================================

  void _onAnimationUpdate() => setState(() {});

  void _onAnimationStatusChange(AnimationStatus status) {
    if (status == AnimationStatus.completed) {
      // 动画结束：重置状态并执行对应操作
      setState(() {
        _isAnimating = false;
        _dragOffset = 0;
        _animController.reset();
        _currentImageData = null;
        _currentImageId = null;
      });

      if (_animTargetValue < 0) {
        // 左滑飞走 → 标记删除
        context.read<PhotosProvider>().markCurrentForDeletion();
      }
      // 移到下一张
      context.read<PhotosProvider>().advanceToNext();
    }
  }

  // ============================================================
  // 计算属性
  // ============================================================

  /// 当前卡片的 X 偏移（拖拽中 = dragOffset，动画中 = 插值）
  double get _cardOffset {
    if (_isAnimating) {
      return _animStartValue +
          (_animTargetValue - _animStartValue) * _animController.value;
    }
    return _dragOffset;
  }

  /// 卡片旋转角度（模拟 Tinder 的随滑动旋转效果）
  double get _rotationAngle {
    final screenWidth = MediaQuery.of(context).size.width;
    return (_cardOffset / screenWidth) * 0.15; // 最大约 8.6°
  }

  /// 左侧删除图标透明度（左滑时渐显）
  double get _deleteIconOpacity {
    final threshold = MediaQuery.of(context).size.width / 3;
    if (_cardOffset >= 0) return 0;
    return (-_cardOffset / threshold).clamp(0.0, 1.0);
  }

  /// 右侧保留图标透明度（右滑时渐显）
  double get _keepIconOpacity {
    final threshold = MediaQuery.of(context).size.width / 3;
    if (_cardOffset <= 0) return 0;
    return (_cardOffset / threshold).clamp(0.0, 1.0);
  }

  // ============================================================
  // 手势处理
  // ============================================================

  void _onPanStart(DragStartDetails details) {
    if (_isAnimating) return;
    setState(() => _dragOffset = 0);
  }

  void _onPanUpdate(DragUpdateDetails details) {
    if (_isAnimating) return;
    setState(() => _dragOffset += details.delta.dx);
  }

  void _onPanEnd(DragEndDetails details) {
    if (_isAnimating) return;

    final screenWidth = MediaQuery.of(context).size.width;
    final threshold = screenWidth / 3; // 1/3 屏幕宽度为触发阈值

    if (_dragOffset < -threshold) {
      _startAnim(-screenWidth * 2); // 左滑删除 → 飞走
    } else if (_dragOffset > threshold) {
      _startAnim(screenWidth * 2); // 右滑保留 → 飞走
    } else {
      _startAnim(0); // 回弹到中心
    }
  }

  /// 启动飞走/回弹动画
  void _startAnim(double target) {
    setState(() {
      _isAnimating = true;
      _animStartValue = _dragOffset;
      _animTargetValue = target;
    });
    _animController.reset();
    _animController.forward();
  }

  // ============================================================
  // 图片加载
  // ============================================================

  Future<void> _loadCurrentImage() async {
    final provider = context.read<PhotosProvider>();
    final photo = provider.currentPhoto;
    if (photo == null) return;

    final String photoId = photo.id;

    setState(() => _isCurrentVideo = _photoService.isVideo(photo));

    final screenWidth = MediaQuery.of(context).size.width.toInt();
    final data = await _photoService.getThumbnail(
      entity: photo,
      width: screenWidth,
      height: screenWidth,
    );

    if (!mounted) return;
    setState(() {
      _currentImageId = photoId;
      _currentImageData = data;
      _isLoadingImage = false;
    });
  }

  // ============================================================
  // UI 构建
  // ============================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Consumer<PhotosProvider>(
        builder: (context, provider, _) {
          if (provider.isLoading) return _buildLoadingView();
          if (provider.error != null && !provider.hasPermission) {
            return _buildPermissionDeniedView(provider);
          }
          if (provider.error != null && provider.allPhotos.isEmpty) {
            return _buildErrorView(provider);
          }
          if (provider.allPhotos.isEmpty && !provider.isLoading) {
            return _buildEmptyView();
          }
          if (provider.isAllProcessed) return _buildAllDoneView(provider);

          // 检查是否需要加载新图片
          final currentPhotoId = provider.currentPhoto?.id;
          if (_currentImageId != currentPhotoId &&
              currentPhotoId != null &&
              !_isAnimating &&
              !_isLoadingImage) {
            _isLoadingImage = true;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) _loadCurrentImage();
            });
          }

          return _buildSwipeView(provider);
        },
      ),
    );
  }

  /// 加载中
  Widget _buildLoadingView() {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(color: Colors.white),
          SizedBox(height: 16),
          Text('正在加载照片...',
              style: TextStyle(color: Colors.white70, fontSize: 16)),
        ],
      ),
    );
  }

  /// 权限被拒绝
  Widget _buildPermissionDeniedView(PhotosProvider provider) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.photo_library_outlined,
                color: Colors.white54, size: 80),
            const SizedBox(height: 24),
            Text(
              provider.error ?? '需要相册权限',
              style: const TextStyle(color: Colors.white, fontSize: 18),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            const Text(
              '我们需要访问您的相册来帮助您筛选和清理照片',
              style: TextStyle(color: Colors.white54, fontSize: 14),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            if (provider.isPermanentlyDenied) ...[
              const Text(
                '权限已被永久拒绝，请在系统设置中手动开启',
                style: TextStyle(color: Colors.orange, fontSize: 13),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () => provider.goToAppSettings(),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                  foregroundColor: Colors.white,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
                ),
                child: const Text('前往系统设置'),
              ),
            ] else ...[
              ElevatedButton(
                onPressed: () => provider.initialize(),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                  foregroundColor: Colors.white,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
                ),
                child: const Text('授予权限'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// 加载失败
  Widget _buildErrorView(PhotosProvider provider) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, color: Colors.red, size: 64),
            const SizedBox(height: 16),
            Text(provider.error ?? '加载失败',
                style:
                    const TextStyle(color: Colors.white70, fontSize: 16),
                textAlign: TextAlign.center),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () => provider.retryLoad(),
              child: const Text('重试'),
            ),
          ],
        ),
      ),
    );
  }

  /// 相册为空
  Widget _buildEmptyView() {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.photo_camera, color: Colors.white54, size: 80),
          SizedBox(height: 16),
          Text('相册中暂无照片',
              style: TextStyle(color: Colors.white70, fontSize: 18)),
        ],
      ),
    );
  }

  /// 全部浏览完毕
  Widget _buildAllDoneView(PhotosProvider provider) {
    return SafeArea(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.check_circle_outline,
                  color: Colors.green, size: 80),
              const SizedBox(height: 24),
              const Text(
                '全部照片已浏览完毕！',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                '共标记 ${provider.deleteCount} 张照片待删除',
                style: const TextStyle(color: Colors.white54, fontSize: 16),
              ),
              const SizedBox(height: 32),
              if (provider.deleteCount > 0)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () => _goToDeleteList(),
                      icon: const Icon(Icons.delete_outline),
                      label: Text('查看待删除 (${provider.deleteCount})'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                    ),
                  ),
                ),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: () =>
                      _showResetDialog(provider),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white70,
                    side: const BorderSide(color: Colors.white30),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: const Text('重新开始'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 主滑动界面
  Widget _buildSwipeView(PhotosProvider provider) {
    return SafeArea(
      child: Stack(
        children: [
          // 下一张照片的模糊背景
          if (provider.hasNext) _buildBackgroundCard(),

          // 可拖拽的当前照片卡片
          _buildDraggableCard(),

          // 左侧删除图标（左滑时渐显）
          Positioned(
            left: 30,
            top: MediaQuery.of(context).size.height * 0.12,
            child: IgnorePointer(
              child: Opacity(
                opacity: _deleteIconOpacity,
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.red.withValues(alpha: 0.85),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const Column(
                    children: [
                      Icon(Icons.delete, color: Colors.white, size: 48),
                      SizedBox(height: 4),
                      Text('删除',
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
              ),
            ),
          ),

          // 右侧保留图标（右滑时渐显）
          Positioned(
            right: 30,
            top: MediaQuery.of(context).size.height * 0.12,
            child: IgnorePointer(
              child: Opacity(
                opacity: _keepIconOpacity,
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.green.withValues(alpha: 0.85),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const Column(
                    children: [
                      Icon(Icons.check_circle, color: Colors.white, size: 48),
                      SizedBox(height: 4),
                      Text('保留',
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
              ),
            ),
          ),

          // 底部操作栏
          Positioned(
            left: 0, right: 0, bottom: 0,
            child: _buildBottomBar(provider),
          ),
        ],
      ),
    );
  }

  /// 背景卡片（下一张照片占位）
  Widget _buildBackgroundCard() {
    final screenWidth = MediaQuery.of(context).size.width;
    return Center(
      child: Container(
        width: screenWidth - 20,
        height: MediaQuery.of(context).size.height * 0.75,
        decoration: BoxDecoration(
          color: Colors.grey[900],
          borderRadius: BorderRadius.circular(16),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: const Center(
            child: Icon(Icons.photo, color: Colors.white10, size: 64),
          ),
        ),
      ),
    );
  }

  /// 可拖拽的当前照片卡片
  Widget _buildDraggableCard() {
    final screenWidth = MediaQuery.of(context).size.width;

    return GestureDetector(
      onPanStart: _onPanStart,
      onPanUpdate: _onPanUpdate,
      onPanEnd: _onPanEnd,
      child: Center(
        child: Transform.translate(
          offset: Offset(_cardOffset, 0),
          child: Transform.rotate(
            angle: _rotationAngle,
            child: Container(
              width: screenWidth - 20,
              height: MediaQuery.of(context).size.height * 0.75,
              decoration: BoxDecoration(
                color: Colors.grey[900],
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.6),
                    blurRadius: 20,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: _buildPhotoContent(),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// 卡片内的照片内容
  Widget _buildPhotoContent() {
    if (_currentImageData != null) {
      return Stack(
        fit: StackFit.expand,
        children: [
          Image.memory(
            _currentImageData!,
            fit: BoxFit.contain,
            gaplessPlayback: true,
          ),
          if (_isCurrentVideo)
            const Center(
              child: Icon(Icons.play_circle_fill,
                  color: Colors.white70, size: 64),
            ),
        ],
      );
    }

    return const Center(
      child: CircularProgressIndicator(color: Colors.white30),
    );
  }

  /// 底部控制栏
  Widget _buildBottomBar(PhotosProvider provider) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [
            Colors.black.withValues(alpha: 0.9),
            Colors.black.withValues(alpha: 0.5),
            Colors.transparent,
          ],
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 进度条
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: provider.totalCount > 0
                  ? (provider.currentIndex + 1) / provider.totalCount
                  : 0,
              backgroundColor: Colors.white24,
              color: Colors.blue,
              minHeight: 4,
            ),
          ),
          const SizedBox(height: 12),

          // 信息行
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(provider.progressText,
                  style:
                      const TextStyle(color: Colors.white70, fontSize: 14)),

              Row(
                children: [
                  // 撤销按钮
                  if (provider.deleteCount > 0)
                    GestureDetector(
                      onTap: () => provider.undoLastMark(),
                      child: Container(
                        margin: const EdgeInsets.only(right: 12),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.white30),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const Text('撤销',
                            style:
                                TextStyle(color: Colors.white70, fontSize: 13)),
                      ),
                    ),

                  // 待删除数量标识
                  GestureDetector(
                    onTap: () => _goToDeleteList(),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        color: provider.deleteCount > 0
                            ? Colors.red
                            : Colors.grey[800],
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.delete_outline,
                              color: Colors.white, size: 18),
                          const SizedBox(width: 4),
                          Text(
                            '${provider.deleteCount}',
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 14,
                                fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 10),

          // 操作提示
          const Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(Icons.arrow_back, color: Colors.red, size: 14),
                  SizedBox(width: 4),
                  Text('左滑删除',
                      style: TextStyle(color: Colors.white54, fontSize: 12)),
                ],
              ),
              Row(
                children: [
                  Text('右滑保留',
                      style: TextStyle(color: Colors.white54, fontSize: 12)),
                  SizedBox(width: 4),
                  Icon(Icons.arrow_forward, color: Colors.green, size: 14),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ============================================================
  // 导航
  // ============================================================

  void _goToDeleteList() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const DeleteListScreen()),
    );
  }

  void _showResetDialog(PhotosProvider provider) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('重新开始'),
        content: const Text('将清除所有标记记录，重新浏览所有照片。\n确定要重新开始吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              provider.retryLoad();
              setState(() {
                _currentImageData = null;
                _currentImageId = null;
                _dragOffset = 0;
                _isLoadingImage = false;
              });
            },
            child:
                const Text('确定', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }
}
