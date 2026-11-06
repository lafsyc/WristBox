import 'package:flutter/material.dart';

class ConnectionGuidePage extends StatelessWidget {
  const ConnectionGuidePage({
    super.key,
    required this.onAccount,
    required this.onLogs,
    required this.onSettings,
    required this.onManual,
  });
  final VoidCallback onAccount, onLogs, onSettings, onManual;
  @override
  Widget build(BuildContext context) {
    Widget section(
      String title,
      String body, {
      String? action,
      VoidCallback? onTap,
    }) => Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: Theme.of(context).textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 10),
            Text(body, style: const TextStyle(height: 1.75)),
            if (action != null) ...[
              const SizedBox(height: 10),
              TextButton(onPressed: onTap, child: Text(action)),
            ],
          ],
        ),
      ),
    );
    return Scaffold(
      appBar: AppBar(title: const Text('连接教程')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Text(
                '先获取 Key，再连接手环',
                style: Theme.of(context).textTheme.headlineSmall
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 12),
              const Text(
                '以下方法按顺序尝试即可，不需要每一种都做。手机蓝牙保持开启，允许“附近的设备”权限，手环唤醒并靠近手机。',
                style: TextStyle(height: 1.75),
              ),
              const SizedBox(height: 24),
              section(
                '获取 Key · 小米账号同步',
                '打开“我的 → 小米账号”，登录与小米运动健康相同的小米账号，同步设备和 Key。这里是小米账号，不是 WristBox 邮箱账号；连接手环不要求登录 WristBox。',
                action: '打开小米账号同步',
                onTap: onAccount,
              ),
              section(
                '获取 Key · 本地日志自动读取',
                '1. 在小米运动健康中连接并同步目标手环。\n2. 进入“我的 → 关于”，连续点击运动健康 Logo，按提示导出日志。不同版本入口可能不同。\n3. 首次授权 Download/wearablelog 或 Download/ResearchLog 日志文件夹。\n4. 之后从日志页面打开运动健康、导出并返回，自动查找新日志；也可点击“自动读取最新日志”。\n5. 读取后直接点击你的设备，自动填入地址、导入并验证连接；找不到设备时会尝试蓝牙搜索。正常流程无需输入 MAC 或选择 Key。\n\n日志只在本地读取，不是上传文件。部分运动健康版本不输出 Key，此时使用账号同步。恢复出厂后需要重新获取 Key。',
                action: '打开日志自动读取',
                onTap: onLogs,
              ),
              section(
                '方式一 · 已绑定手机直接连接',
                '推荐先尝试。保留手机与手环现有的系统配对，不必先在手环点“连接新设备”。在 WristBox 设备页点击连接；如果手机或手环出现配对确认，及时确认并等待认证完成。\n\n这适合你在同一台手机已经绑定手环、运动健康未运行但系统蓝牙仍保持连接的情况；不保证两个应用能同时操作手环。',
              ),
              section(
                '方式二 · 手环进入连接模式',
                '直接连接失败时，在手环的“设置 → 系统”等位置寻找“连接新手机 / 连接新设备”，具体名称以手环固件为准。先阅读手环提示，再回到 WristBox 发起连接并确认配对。\n\n不要把“恢复出厂设置”当作普通连接步骤；如果设备提示会解除绑定或清除数据，请先停止并确认影响。',
              ),
              section(
                '方式三 · 开启重建配对兼容选项',
                '进入“我的 → 蓝牙连接方式”，开启“连接前重建系统配对”，然后重新连接。这会尝试移除并重建目标手环的系统配对，运动健康连接、手环解锁手机等功能可能需要重新配置。\n\n仅在默认方式失败后尝试，通常保持关闭。这个选项不能修复过期或错误的 Key。',
                action: '打开蓝牙连接设置',
                onTap: onSettings,
              ),
              section(
                '已有 Key · 手动添加或更新',
                '已有可信 Key 时，可以手动填写设备资料。设备恢复出厂并重新绑定后，使用设备菜单的“更新 Key”，或重新进行账号同步、日志读取。不要把日志或完整 Key 公开分享。',
                action: '手动添加设备',
                onTap: onManual,
              ),
              section(
                '连接后先确认这些',
                '查看电量、型号和设备信息能否刷新，再尝试安装适配型号的 RPK/BIN。系统蓝牙显示“已连接”不等于 WristBox 已认证成功。\n\n等待中可以点“取消连接”。持续失败时，检查 Key 是否最新、配对提示是否已确认，以及其他应用是否占用连接；请记录型号、固件和中文错误提示。',
              ),
            ],
          ),
        ),
      ),
    );
  }
}
