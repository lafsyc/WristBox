# WristBox

<img src="assets/images/brands/wristbox.png" alt="WristBox" width="96">

面向小米手环的 Android 第三方连接、应用安装与管理工具。基于 [OronBox](https://github.com/zxor-org/OronBox) 修改，以 **AGPL-3.0** 发布。

源码地址：**https://github.com/lafsyc/WristBox**

## 功能

- 小米账号同步设备与连接 Key；本地日志读取和手动导入作为补充。
- 保存多台设备，单台活动连接，安装任务按设备串行执行。
- 本地选择、搜索和安装 RPK / BIN，查看设备信息和已安装应用，卸载应用。
- 云端 RPK / 小米表盘容器 BIN 商店、型号与固件匹配、设备绑定资源激活、更新与弹窗公告。
- 可选邮箱账号、昵称与头像；商店浏览和设备授权不强制邮箱登录。
- 明暗主题、动态安装进度、连接教程和首次使用隐私说明。

日志在手机本地解析，不上传。不同型号、固件和运动健康版本的兼容性以实机测试为准；系统蓝牙已连接不等于应用认证成功。安装前确认文件来源及设备型号。

## 仓库范围

这是 **Android 客户端源码仓库**，包含 Android 原生实现、Flutter 界面、共用设备协议、客户端加密/验签实现、必要素材、许可证、测试和构建脚本。内部 Dart 包名保留 `oronbox`，应用名称为 WristBox。

不包含 Windows 专用界面和原生工程、云服务端实现及运维部署、签名私钥、服务器私钥、账号数据库、用户日志、设备 Key、商店安装包、付费资源、构建缓存和设计草稿。部分共用代码仍包含跨平台分支或平台库依赖，不构成 Windows 发行工程。

`assets/certificates/` 仅含客户端校验所需的 **公开 CA 证书和签名公钥**，不含服务器私钥。公开源码不授予云服务管理权限或商店资源授权；这些权限由服务端校验。

## 构建

环境：Flutter **3.47.5** / Dart **3.13.4**、JDK 17 或兼容版本、Android SDK 36（以及 Flutter 要求的 NDK / Build Tools）。最低 Android 版本为 8.0（API 26）。依赖版本由 `pubspec.lock` 固定。

```sh
git clone https://github.com/lafsyc/WristBox.git
cd WristBox
flutter pub get
flutter build apk --debug --target lib/main_android.dart
```

不注入服务配置时，可调试本地连接与安装；邮箱和商店等云端功能不会连接任何默认服务器。

正式构建需使用自己的签名：复制 `android/key.properties.example` 为 `android/key.properties` 并填写本机签名配置。将 `config/build.example.json` 复制为 `config/production.local.json`，填写自己的 HTTPS 服务地址，再执行：

```sh
flutter build apk --release --target lib/main_android.dart --dart-define-from-file=config/production.local.json
```

Windows PowerShell 也可执行 `./tool/build-android.ps1 -Flutter flutter`，默认读取上述本地配置，也可用 `-ConfigFile` 指定路径；缺失配置或仍为示例地址时会停止打包。生成文件位于 `build/app/outputs/flutter-apk/`。不要提交本地配置、`key.properties` 和签名文件；使用自己的签名构建的应用不能直接覆盖官方签名版本。

本地连接与安装不依赖 WristBox 邮箱账号。云端功能依赖服务可用性和服务器授权；源码不包含线上账号、激活记录或自托管服务端。仓库仅保留示例配置，官方服务地址由私有打包配置注入。替换服务需实现相同接口并配置对应的公钥/证书，不能通过跳过 TLS 或签名校验来接入。

`WRISTBOX_AUTH_USE_BUNDLED_CA` 默认为 `false`，使用系统信任根；只有服务确实使用随包 CA 时才设为 `true`，且该 CA 仅用于配置的 HTTPS 主机和端口。本地配置已被 Git 忽略，导出源码时也不会复制。编译参数会进入应用二进制，不能用于隐藏密码、私钥或访问令牌。

## 验证

```sh
flutter analyze --no-fatal-infos lib/steadylink lib/main.dart lib/main_android.dart test/steadylink
flutter test --no-pub test/steadylink
```

此仓库仍保留部分上游基础模块；上面的检查针对当前 Android 产品入口。自动化不能代替真实蓝牙、各厂商权限和手环固件测试。

## 许可与致谢

项目许可证见 [LICENSE](LICENSE)，上游与第三方声明见 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) 及 `assets/licenses/`。上游基线为 OronBox `1af1924bb0061d2afb5d3708b986e0fffa85beeb`。本仓库从整理后的 Android 源码快照开始记录历史，保留代码内原作者版权及署名。

商店中的应用、图片与其他资源由各自权利人授权，不因工具开源自动成为开源资源。本工具非小米或 Redmi 官方应用，与设备厂商无官方隶属关系。

问题反馈可提交 GitHub Issue。涉及安全问题，请按 [SECURITY.md](SECURITY.md) 私下反馈，勿在公开 Issue 中贴出日志、账号令牌、设备 Key 或完整激活码。
