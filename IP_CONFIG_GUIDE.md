# 服務器 IP 地址配置問題解決方案

## 問題描述

Flutter 應用程式正在嘗試連接到 `http://10.0.2.2:8080`，但這個 IP 地址是 Android 模擬器的特殊地址，不適用於 iPad 模擬器或其他平台。

## 解決方案

### 1. 使用重置配置功能

在應用程式的設置頁面中，點擊 **"重置配置"** 按鈕，這會將服務器 URL 重置為正確的 `http://192.168.0.103:8080`。

### 2. 手動更新配置

在設置頁面中：
1. 將服務器 URL 更改為 `http://192.168.0.103:8080`
2. 點擊 **"儲存設定"** 按鈕

### 3. 清除應用數據（如果上述方法無效）

#### Android 模擬器
```bash
# 清除應用數據
adb shell pm clear com.example.taxi_app
```

#### iOS 模擬器
```bash
# 重置模擬器
xcrun simctl erase all
```

### 4. 重新安裝應用

如果問題仍然存在，可以重新安裝應用：

```bash
flutter clean
flutter pub get
flutter run
```

## 配置說明

### 正確的配置
```dart
const String serverUrl = 'http://192.168.0.103:8080';
```

### 平台特定配置

| 平台 | 推薦配置 | 備用配置 |
|------|----------|----------|
| Android 模擬器 | `192.168.0.103:8080` | `10.0.2.2:8080` |
| iOS 模擬器 | `192.168.0.103:8080` | `localhost:8080` |
| 實體設備 | `192.168.0.103:8080` | - |

## 自動配置

應用程式現在會自動檢測運行環境並使用適當的配置：

```dart
class ServerConfig {
  static const String dockerHost = '192.168.0.103';
  static const int dockerPort = 8080;
  
  static String get host {
    if (Platform.isAndroid) {
      return dockerHost; // Android 使用主機 IP
    } else if (Platform.isIOS) {
      return localHost; // iOS 可以使用 localhost
    } else {
      return dockerHost; // 其他平台使用主機 IP
    }
  }
}
```

## 驗證配置

使用應用內建的連接測試功能來驗證配置是否正確：

1. 打開設置頁面
2. 點擊 **"測試連線"** 按鈕
3. 如果顯示 "連線測試成功"，則配置正確

## 故障排除

### 如果仍然連接到錯誤的 IP

1. **檢查數據庫配置**：應用可能從數據庫讀取舊配置
2. **使用重置功能**：點擊 "重置配置" 按鈕
3. **清除應用數據**：完全清除應用數據並重新安裝

### 如果連接失敗

1. **檢查網絡**：確保設備和主機在同一網絡
2. **檢查防火牆**：確保 8080 端口開放
3. **檢查 Docker**：確保 Docker 容器正在運行

## 更新日誌

- **v1.0.0**: 使用 `10.0.2.2:8080`（有問題）
- **v1.1.0**: 更新為 `192.168.0.103:8080`（正確）
- **v1.2.0**: 添加自動環境檢測和重置功能
