# SteadyLink 第三方来源

SteadyLink 是基于 [OronBox](https://github.com/zxor-org/OronBox) 的修改版本，
以 GNU Affero General Public License v3.0（AGPL-3.0）发布，完整许可证见 `LICENSE`。
上游基线提交：`1af1924bb0061d2afb5d3708b986e0fffa85beeb`。

沿用部分包括小米账号登录及设备凭据获取、蓝牙与小米设备协议、安装包解析、
Windows RFCOMM 与 WebView2 集成。原作者版权与源代码中的署名保持不变。
原项目说明保存在 `docs/oronbox-upstream-readme.md`。

SteadyLink 新增专用桌面界面、设备操作队列、Windows 凭据加密存储、
连接生命周期与平台线程回调调整。内部 Dart 包名暂时保留 `oronbox` 以方便追溯上游。
Android 0.4.0 增加 Material 3 手机界面、绘制式动态进度、Android Keystore 凭据存储和独立应用标识；
复用上游 Android 蓝牙传输、账号二次验证 WebView 与后台连接服务。

协议实现另参考 [AstroBox](https://github.com/AstralSightStudios/AstroBox-NG)。
当前实现主要复用 OronBox；独立克隆的参考仓库不随程序打包。

界面使用 Flutter 的开源 Material 组件与 Material Icons；没有引入商业 UI 模板。
0.2.0 的布局和视觉方向参考 Spacedrive 的桌面工作区与 shadcn/ui 的克制组件风格；
界面由 Flutter 独立实现，未复制这两个项目的代码、图标或图片素材。
Flutter 和各依赖的版权条款可以通过程序“关于 → 查看许可”查看。
依赖版本由 `pubspec.lock` 固定；其他上游协议与资源声明见 `assets/licenses/`。

Microsoft WebView2 SDK 及运行时遵守 Microsoft 的相应许可。
发布构建所用 SDK 的许可证随 SDK NuGet 包提供。

对外分发本项目的修改版时，应遵守 AGPL-3.0 并提供对应版本的完整源代码及构建说明。

Android 0.5.2 手环轮廓参考 AstroBox-NG 仓库 images/screenshot_device.png 的简洁设备外形；
由 Flutter Canvas 独立绘制，未复制图片或前端代码。内部电量和传输动效为 SteadyLink 实现。

Android 0.5.3 使用显示名称 WristBox，图标由用户指定的同级 WristBox 项目共享资源提供。
保留 io.steadylink.app 包标识和现有签名以兼容覆盖升级；上游版权与 AGPL-3.0 许可不变。
