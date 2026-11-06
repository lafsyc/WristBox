import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'account_profile_dialog.dart';
import 'wristbox_account.dart';

class AccountIdChip extends StatelessWidget {
  const AccountIdChip({super.key, required this.id});
  final int? id;
  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    return Material(
      color: c.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: id == null
            ? null
            : () async {
                await Clipboard.setData(ClipboardData(text: '$id'));
                if (context.mounted) {
                  ScaffoldMessenger.of(context)
                      .showSnackBar(const SnackBar(content: Text('账号 ID 已复制')));
                }
              },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                id == null ? 'ID 待同步' : 'ID $id',
                style: TextStyle(
                  fontSize: 12,
                  color: c.onSurfaceVariant,
                  letterSpacing: .5,
                ),
              ),
              if (id != null) ...[
                const SizedBox(width: 10),
                Icon(Icons.copy_rounded, size: 13, color: c.onSurfaceVariant),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class AccountIdentityCard extends StatelessWidget {
  const AccountIdentityCard({
    super.key,
    required this.session,
    required this.onOpen,
  });
  final WristBoxSession? session;
  final VoidCallback onOpen;
  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    return Material(
      color: c.surfaceContainerLow,
      borderRadius: BorderRadius.circular(26),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onOpen,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  AccountAvatar(session: session, radius: 32),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          session?.displayName ?? '登录 WristBox',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 21,
                            fontWeight: FontWeight.w600,
                            letterSpacing: -.4,
                          ),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          session == null ? '邮箱登录 / 注册' : '编辑头像与个人资料',
                          style: TextStyle(
                            fontSize: 12,
                            color: c.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    Icons.chevron_right_rounded,
                    color: c.onSurfaceVariant,
                    size: 20,
                  ),
                ],
              ),
              if (session != null) ...[
                const SizedBox(height: 20),
                Wrap(
                  spacing: 12,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    AccountIdChip(id: session!.id),
                    if (session!.role == 'admin')
                      Text(
                        '管理员',
                        style: TextStyle(fontSize: 12, color: c.primary),
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class MembershipPlaceholder extends StatelessWidget {
  const MembershipPlaceholder({super.key});
  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    return Material(
      color: c.surfaceContainerLow,
      borderRadius: BorderRadius.circular(24),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => showDialog<void>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('会员功能筹备中'),
            content: const Text(
              '这里将用于展示会员激活状态与权益。\n\n目前尚未开放激活、付费或会员权益，后续以正式公告为准。',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('知道了'),
              ),
            ],
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.workspace_premium_outlined,
                    color: c.primary,
                    size: 24,
                  ),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text(
                      '会员中心',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Icon(
                    Icons.chevron_right_rounded,
                    size: 18,
                    color: c.onSurfaceVariant,
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 10,
                runSpacing: 5,
                children: [
                  Text(
                    '会员状态',
                    style: TextStyle(fontSize: 12, color: c.onSurfaceVariant),
                  ),
                  const Text('暂未开放', style: TextStyle(fontSize: 12)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
