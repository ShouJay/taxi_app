import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async';
import '../config/app_config.dart';
import '../services/websocket_manager.dart';
import '../managers/playback_manager.dart';
import '../services/download_manager.dart';
import '../services/location_service.dart';
import '../models/download_info.dart';

// PlaybackInfo 在 playback_manager.dart 中定義

/// 設定頁面
class SettingsScreen extends StatefulWidget {
  final WebSocketManager webSocketManager;
  final PlaybackManager playbackManager;
  final DownloadManager downloadManager;
  final LocationService? locationService;
  final bool isAdminMode;
  final Future<void> Function(bool) onAdminModeChanged;
  final VoidCallback onBack;

  const SettingsScreen({
    Key? key,
    required this.webSocketManager,
    required this.playbackManager,
    required this.downloadManager,
    this.locationService,
    required this.isAdminMode,
    required this.onAdminModeChanged,
    required this.onBack,
  }) : super(key: key);

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late TextEditingController _deviceIdController;
  late TextEditingController _serverUrlController;
  String _connectionStatus = '檢查中...';
  String _lastUpdate = '---';
  bool _isSaving = false;
  late bool _isAdminMode;
  bool _isUpdatingAdminMode = false;

  // 下載進度相關
  Map<String, DownloadTask> _activeDownloads = {};
  Timer? _downloadMonitoringTimer;

  @override
  void initState() {
    super.initState();
    _deviceIdController = TextEditingController(
      text: widget.webSocketManager.deviceId,
    );
    _serverUrlController = TextEditingController(
      text: widget.webSocketManager.serverUrl,
    );
    _isAdminMode = widget.isAdminMode;
    _updateConnectionStatus();
    _startStatusMonitoring();
    _startDownloadMonitoring();
  }

  /// 開始監聽下載進度
  void _startDownloadMonitoring() {
    // 定期檢查下載任務
    _downloadMonitoringTimer = Timer.periodic(
      const Duration(milliseconds: 500),
      (timer) {
        if (!mounted) {
          timer.cancel();
          return;
        }

        final activeDownloads = widget.downloadManager.getActiveDownloads();
        setState(() {
          _activeDownloads = {
            for (var task in activeDownloads) task.advertisementId: task,
          };
        });
      },
    );
  }

  /// 更新連接狀態
  void _updateConnectionStatus() {
    setState(() {
      final isConnected = widget.webSocketManager.isConnected;
      final isRegistered = widget.webSocketManager.isRegistered;

      if (!isConnected) {
        _connectionStatus = '❌ 未連接';
      } else if (!isRegistered) {
        _connectionStatus = '⚠️ 已連接，但設備註冊失敗';
      } else {
        _connectionStatus = '✅ 已連接並已註冊';
      }
      _lastUpdate = DateTime.now().toString().substring(0, 19);
    });
  }

  /// 開始狀態監控
  void _startStatusMonitoring() {
    Future.doWhile(() async {
      await Future.delayed(const Duration(seconds: 2));
      if (mounted) {
        _updateConnectionStatus();
        return true;
      }
      return false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final isConnected = widget.webSocketManager.isConnected;
    final isRegistered = widget.webSocketManager.isRegistered;
    final IconData connectionIcon = !isConnected
        ? Icons.cloud_off
        : (isRegistered ? Icons.cloud_done : Icons.report_problem);
    final Color connectionColor = !isConnected
        ? Colors.red
        : (isRegistered ? Colors.green : Colors.orange);

    return Scaffold(
      appBar: AppBar(
        title: const Text('設定'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: widget.onBack,
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 設備設定
            _buildSectionTitle('設備設定'),
            const SizedBox(height: 16),
            _buildTextField(
              controller: _deviceIdController,
              label: '設備 ID',
              hint: '例如: taxi-AAB-1234-rooftop',
              icon: Icons.devices,
            ),
            const SizedBox(height: 16),
            _buildTextField(
              controller: _serverUrlController,
              label: '伺服器位址',
              hint: '例如: ws://your-server.com',
              icon: Icons.cloud,
            ),
            const SizedBox(height: 24),

            _buildAdminModeTile(),
            const SizedBox(height: 24),

            // 儲存按鈕
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _isSaving ? null : _saveSettings,
                icon: _isSaving
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.save),
                label: Text(_isSaving ? '儲存中...' : '儲存設定'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  textStyle: const TextStyle(fontSize: 16),
                ),
              ),
            ),

            const SizedBox(height: 32),
            const Divider(),
            const SizedBox(height: 32),

            // 通訊狀況
            _buildSectionTitle('通訊狀況'),
            const SizedBox(height: 16),
            _buildStatusCard(
              title: '連線狀態',
              value: _connectionStatus,
              icon: connectionIcon,
              color: connectionColor,
            ),
            const SizedBox(height: 12),
            _buildStatusCard(
              title: '最後更新',
              value: _lastUpdate,
              icon: Icons.access_time,
              color: Colors.blue,
            ),
            const SizedBox(height: 12),
            _buildStatusCard(
              title: '播放狀態',
              value: _getPlaybackStateText(),
              icon: Icons.play_circle,
              color: Colors.orange,
            ),
            const SizedBox(height: 12),
            _buildStatusCard(
              title: '播放隊列',
              value: '${widget.playbackManager.queueLength} 個廣告',
              icon: Icons.queue_music,
              color: Colors.purple,
            ),
            if (widget.playbackManager.playbackMode ==
                PlaybackMode.campaign) ...[
              const SizedBox(height: 12),
              _buildStatusCard(
                title: '活動播放模式',
                value: widget.playbackManager.activeCampaignId != null
                    ? '活動 ID: ${widget.playbackManager.activeCampaignId}'
                    : '活動播放中',
                icon: Icons.campaign,
                color: Colors.purpleAccent,
              ),
            ],

            // GPS 位置確認狀態
            if (widget.locationService != null) ...[
              const SizedBox(height: 12),
              _buildStatusCard(
                title: 'GPS 位置狀態',
                value: widget.locationService!.getLocationAckStatus(),
                icon: widget.locationService!.isLocationAcknowledged
                    ? Icons.location_on
                    : Icons.location_off,
                color: widget.locationService!.isLocationAcknowledged
                    ? Colors.green
                    : Colors.orange,
              ),
              const SizedBox(height: 12),
              _buildStatusCard(
                title: '位置統計',
                value:
                    '已發送: ${widget.locationService!.sentCount} | '
                    '已確認: ${widget.locationService!.ackCount}',
                icon: Icons.analytics,
                color: Colors.blue,
              ),
            ],

            const SizedBox(height: 32),
            const Divider(),
            const SizedBox(height: 32),

            // 下載進度
            _buildSectionTitle('下載進度'),
            const SizedBox(height: 16),
            _buildDownloadProgressSection(),

            const SizedBox(height: 32),
            const Divider(),
            const SizedBox(height: 32),

            // 播放列表
            _buildSectionTitle('播放列表'),
            const SizedBox(height: 16),
            _buildPlaylistSection(),

            const SizedBox(height: 32),
            const Divider(),
            const SizedBox(height: 32),

            // 操作按鈕
            _buildSectionTitle('操作'),
            const SizedBox(height: 16),
            _buildActionButton(
              label: '測試播放',
              icon: Icons.play_arrow,
              onPressed: _testPlayDefaultVideo,
            ),
            const SizedBox(height: 12),
            _buildActionButton(
              label: '重新連接',
              icon: Icons.refresh,
              onPressed: _reconnect,
            ),
            const SizedBox(height: 12),
            _buildActionButton(
              label: '清空播放隊列',
              icon: Icons.clear_all,
              onPressed: _clearQueue,
              color: Colors.orange,
            ),

            const SizedBox(height: 32),

            // 版本資訊
            Center(
              child: Text(
                'Taxi App v1.0.0',
                style: TextStyle(color: Colors.grey[600], fontSize: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 建立區段標題
  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
    );
  }

  /// 建立文字輸入框
  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
  }) {
    return TextField(
      controller: controller,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: Icon(icon),
        border: const OutlineInputBorder(),
      ),
    );
  }

  /// 建立狀態卡片
  Widget _buildStatusCard({
    required String title,
    required String value,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 32),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAdminModeTile() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.blue.withOpacity(0.3)),
      ),
      child: SwitchListTile(
        title: const Text(
          '管理員模式',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Text(
          '開啟後於播放畫面顯示調試資訊（GPS、播放來源等）',
          style: TextStyle(color: Colors.grey[600]),
        ),
        value: _isAdminMode,
        onChanged: _isUpdatingAdminMode ? null : _handleAdminModeChanged,
        secondary: Icon(
          _isAdminMode ? Icons.admin_panel_settings : Icons.visibility_off,
          color: _isAdminMode ? Colors.blue : Colors.grey,
        ),
      ),
    );
  }

  /// 建立操作按鈕
  Widget _buildActionButton({
    required String label,
    required IconData icon,
    required VoidCallback onPressed,
    Color? color,
  }) {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, color: color),
        label: Text(label, style: TextStyle(color: color)),
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 12),
          side: BorderSide(color: color ?? Colors.blue),
        ),
      ),
    );
  }

  /// 獲取播放狀態文字
  String _getPlaybackStateText() {
    switch (widget.playbackManager.state) {
      case PlaybackState.idle:
        return '閒置';
      case PlaybackState.loading:
        return '載入中';
      case PlaybackState.playing:
        return '播放中';
      case PlaybackState.paused:
        return '已暫停';
      case PlaybackState.error:
        return '錯誤';
    }
  }

  /// 儲存設定
  Future<void> _saveSettings() async {
    setState(() {
      _isSaving = true;
    });

    try {
      final newDeviceId = _deviceIdController.text.trim();

      if (newDeviceId.isEmpty) {
        _showMessage('設備 ID 不能為空');
        setState(() {
          _isSaving = false;
        });
        return;
      }

      // 儲存到本地
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(AppConfig.deviceIdKey, newDeviceId);

      // 更新 WebSocket 管理器
      widget.webSocketManager.updateDeviceId(newDeviceId);

      _showMessage('設定已儲存');
      print('✅ 設定已儲存: $newDeviceId');
    } catch (e) {
      _showMessage('儲存失敗: $e');
      print('❌ 儲存設定失敗: $e');
    } finally {
      setState(() {
        _isSaving = false;
      });
    }
  }

  /// 測試播放
  Future<void> _testPlayDefaultVideo() async {
    await widget.playbackManager.startAutoPlay();
    _showMessage('開始播放本地影片');
  }

  /// 重新連接
  void _reconnect() {
    widget.webSocketManager.disconnect();
    Future.delayed(const Duration(seconds: 1), () {
      widget.webSocketManager.connect();
      _showMessage('正在重新連接...');
    });
  }

  Future<void> _handleAdminModeChanged(bool value) async {
    setState(() {
      _isUpdatingAdminMode = true;
    });
    try {
      await widget.onAdminModeChanged(value);
      setState(() {
        _isAdminMode = value;
      });
    } catch (e) {
      _showMessage('切換管理員模式失敗: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isUpdatingAdminMode = false;
        });
      }
    }
  }

  /// 清空播放隊列
  Future<void> _clearQueue() async {
    await widget.playbackManager.startAutoPlay();
    _showMessage('播放隊列已清空，重新開始播放');
  }

  /// 建立播放列表區段
  Widget _buildPlaylistSection() {
    final playlist = widget.playbackManager.getFullPlaylist();
    final systemPlaylist = playlist
        .where((item) => !item.isLocalVideo)
        .toList();
    final localPlaylist = playlist.where((item) => item.isLocalVideo).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildPlaylistGroup(
          title: '播放清單（系統）',
          emptyHint: '目前沒有活動或排程中的影片',
          items: systemPlaylist,
        ),
        const SizedBox(height: 24),
        _buildPlaylistGroup(
          title: '本地影片清單',
          emptyHint: '尚未匯入本地影片',
          items: localPlaylist,
        ),
      ],
    );
  }

  Widget _buildPlaylistGroup({
    required String title,
    required String emptyHint,
    required List<PlaybackInfo> items,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        if (items.isEmpty)
          _buildEmptyPlaylistCard(emptyHint)
        else
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: items.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final item = items[index];
              return _buildPlaylistItem(item);
            },
          ),
      ],
    );
  }

  Widget _buildEmptyPlaylistCard(String hint) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.grey.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        hint,
        style: const TextStyle(color: Colors.grey),
        textAlign: TextAlign.center,
      ),
    );
  }

  /// 建立播放列表項目
  Widget _buildPlaylistItem(PlaybackInfo item) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Icon(
          item.isCurrentPlaying
              ? Icons.play_circle_filled
              : item.isLocalVideo
              ? Icons.video_library
              : Icons.cloud_download,
          color: item.isCurrentPlaying ? Colors.green : Colors.blue,
        ),
        title: Text(
          item.title,
          style: TextStyle(
            fontWeight: item.isCurrentPlaying
                ? FontWeight.bold
                : FontWeight.normal,
            color: item.isCurrentPlaying ? Colors.green : Colors.black,
          ),
        ),
        subtitle: Text(item.filename, style: const TextStyle(fontSize: 12)),
        trailing: item.isLocalVideo
            ? IconButton(
                icon: const Icon(Icons.delete, color: Colors.red),
                onPressed: () => _confirmDeleteVideo(item),
                tooltip: '刪除影片',
              )
            : null,
      ),
    );
  }

  /// 確認刪除影片
  Future<void> _confirmDeleteVideo(PlaybackInfo item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('確認刪除'),
        content: Text('確定要刪除影片 "${item.filename}" 嗎？\n\n此操作無法復原。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('刪除'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final success = await widget.playbackManager.deleteVideo(item.filename);
      if (success) {
        _showMessage('已刪除影片: ${item.filename}');
        setState(() {}); // 刷新界面
      } else {
        _showMessage('刪除失敗');
      }
    }
  }

  /// 顯示訊息
  void _showMessage(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 2)),
    );
  }

  /// 建立下載進度區段
  Widget _buildDownloadProgressSection() {
    if (_activeDownloads.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.grey.withOpacity(0.1),
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Text(
          '目前沒有進行中的下載任務',
          style: TextStyle(color: Colors.grey),
          textAlign: TextAlign.center,
        ),
      );
    }

    return Column(
      children: _activeDownloads.values.map((task) {
        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.blue.withOpacity(0.1),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.blue.withOpacity(0.3)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.download, color: Colors.blue, size: 24),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          task.downloadInfo.filename,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '廣告 ID: ${task.advertisementId}',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.blue,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '${task.progress}%',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              LinearProgressIndicator(
                value: task.progress / 100,
                backgroundColor: Colors.grey.withOpacity(0.3),
                valueColor: const AlwaysStoppedAnimation<Color>(Colors.blue),
                minHeight: 8,
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '分片: ${task.downloadedChunks.length}/${task.totalChunks}',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey[700],
                    ),
                  ),
                  Text(
                    '狀態: ${_getDownloadStatusText(task.status)}',
                    style: TextStyle(
                      fontSize: 12,
                      color: _getDownloadStatusColor(task.status),
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              if (task.errorMessage != null) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.red.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.error, color: Colors.red, size: 16),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          task.errorMessage!,
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.red,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        );
      }).toList(),
    );
  }

  /// 獲取下載狀態文字
  String _getDownloadStatusText(DownloadStatus status) {
    switch (status) {
      case DownloadStatus.pending:
        return '等待中';
      case DownloadStatus.downloading:
        return '下載中';
      case DownloadStatus.completed:
        return '已完成';
      case DownloadStatus.failed:
        return '失敗';
      case DownloadStatus.paused:
        return '已暫停';
    }
  }

  /// 獲取下載狀態顏色
  Color _getDownloadStatusColor(DownloadStatus status) {
    switch (status) {
      case DownloadStatus.pending:
        return Colors.grey;
      case DownloadStatus.downloading:
        return Colors.blue;
      case DownloadStatus.completed:
        return Colors.green;
      case DownloadStatus.failed:
        return Colors.red;
      case DownloadStatus.paused:
        return Colors.orange;
    }
  }

  @override
  void dispose() {
    _downloadMonitoringTimer?.cancel();
    _deviceIdController.dispose();
    _serverUrlController.dispose();
    super.dispose();
  }
}
