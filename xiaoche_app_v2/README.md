# xiaoche_app_v2

小车远程控制与视频监控 Flutter 客户端。

## 功能概览

- WebSocket 连接小车控制端，支持连接、断开、取消连接和断线自动重连。
- 支持手动、自动、急停三种控制模式切换。
- 指令控制台支持文本指令、快捷指令、日志查看和语音输入。
- 虚拟手柄支持前进、后退、左转、右转、停止，以及速度百分比调节。
- RTSP 视频监控支持 live / yolo 两路流切换、播放状态提示和失败重连。
- Atlas 状态回传面板显示 AI 决策状态、障碍方向、置信度、FPS、推理时延和当前执行命令。
- Atlas 自然语言指令口支持将自然语言控制命令发送到后端，并展示决策结果。
- 设置页支持保存默认端口、重连参数、Atlas IP、RTSP 端口、流路径、鉴权信息、传输协议和主题颜色。

## 目录结构

```text
lib/
  main.dart                    应用入口、主题和路由
  home_page.dart               首页、连接入口、模式切换
  connection_model.dart        小车连接状态、日志、自动重连
  car_socket_service.dart      小车 WebSocket 底层封装
  command_page.dart            指令控制台和语音输入
  control_page.dart            虚拟手柄控制页
  video_page.dart              RTSP 视频、Atlas 状态和 LLM 指令页
  settings_model.dart          本地设置持久化
  settings_page.dart           设置页面
  atlas_status_ws_client.dart  Atlas 状态 WebSocket 客户端
  atlas_command_ws_client.dart Atlas 指令 WebSocket 客户端
  speech_service.dart          Android 语音识别 MethodChannel 封装
  ai_overlay.dart              AI 检测框绘制工具
```

## 运行方式

进入 v2 项目目录：

```bash
cd xiaoche_app_v2
flutter pub get
flutter run
```

Android 端语音输入依赖系统语音服务和麦克风权限。模拟器上可能出现网络或语音服务不可用，建议用真机测试。

## 连接与协议

首页可以输入小车控制端地址：

- 输入完整地址：`ws://192.168.1.10:8080`
- 只输入 IP：应用会按设置页的默认端口自动补全，例如 `ws://192.168.1.10:8080`

常用控制命令：

```text
MODE MANUAL
MODE AUTO
MODE EMG
forward 30000
backward 30000
left 30000
right 30000
stop 0
```

虚拟手柄默认发送 JSON：

```json
{"cmd":"forward","speed":30000}
```

如果后端仍使用旧文本协议，可以在控制页打开“文本协议兼容模式”。

## 视频与 Atlas 配置

设置页中的默认值：

```text
Atlas IP: 192.168.137.2
RTSP port: 8554
Live path: live
Yolo path: yolo
Atlas status WS: ws://<Atlas IP>:8765
Atlas command WS: ws://<Atlas IP>:8766
```

RTSP 地址由应用自动生成：

```text
rtsp://<username>:<password>@<Atlas IP>:8554/live
rtsp://<username>:<password>@<Atlas IP>:8554/yolo
```

未设置用户名时会省略鉴权信息。

## 备注

当前 v2 目录保留了原 Flutter 包名 `xiaoche_app_v1`，Android namespace、applicationId 和 MethodChannel 名称也仍沿用 v1。这样可以减少迁移时的构建风险；如果后续需要彻底改名，可以再统一调整工程配置。
