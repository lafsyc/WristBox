import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

const sourceRepository = 'https://github.com/lafsyc/WristBox';
const sourceLicense = 'AGPL-3.0';

/// Shared disclosure for first launch and About. No network before a user tap.
class OpenSourceNotice extends StatelessWidget {
  const OpenSourceNotice({super.key, this.compact = false});
  final bool compact;

  Future<void> _open(BuildContext context) async {
    try {
      if (await launchUrl(
        Uri.parse(sourceRepository),
        mode: LaunchMode.externalApplication,
      )) {
        return;
      }
    } catch (_) {
      // The selectable URL remains usable without an external browser.
    }
    if (context.mounted) {
      ScaffoldMessenger.maybeOf(
        context,
      )?.showSnackBar(const SnackBar(content: Text('无法打开浏览器，请复制下方开源地址后访问。')));
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        '安卓客户端已开源 · $sourceLicense',
        style: Theme.of(context).textTheme.titleSmall,
      ),
      const SizedBox(height: 6),
      if (!compact) ...[
        const Text(
          '基于 OronBox，保留上游版权与许可。商店资源另有授权，开源不代表获得全部资源的使用权。',
          style: TextStyle(height: 1.6),
        ),
        const SizedBox(height: 6),
      ],
      const SelectableText(sourceRepository, style: TextStyle(fontSize: 12)),
      TextButton.icon(
        onPressed: () => _open(context),
        icon: const Icon(Icons.open_in_new_rounded, size: 18),
        label: const Text('查看开源仓库'),
      ),
    ],
  );
}
