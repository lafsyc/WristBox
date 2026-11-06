import 'dart:async';
import 'dart:io';

import 'theme.dart';
import 'error_message.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:dio/dio.dart';
import 'package:oronbox/src/features/accounts/services/mi_account_service.dart';
import 'package:oronbox/src/features/accounts/models/mi_account_models.dart';
import 'package:oronbox/src/features/accounts/services/mi_account_two_factor_resolver.dart';

MiAccountService steadyAccountService() => MiAccountService(
  dio: Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 20),
      receiveTimeout: const Duration(seconds: 30),
      sendTimeout: const Duration(seconds: 30),
    ),
  ),
);

class AccountDialog extends StatefulWidget {
  const AccountDialog({super.key, required this.importDevices});
  final Future<int> Function(List<MiCloudDevice>) importDevices;
  @override
  State<AccountDialog> createState() => _AccountDialogState();
}

class _AccountDialogState extends State<AccountDialog> {
  final _username = TextEditingController();
  final _password = TextEditingController();
  final _service = steadyAccountService();
  bool _busy = false;
  bool _checking = true;
  MiAccountToken? _token;
  String? _error;
  String _status = '';

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      _token = await _service.loadStoredToken();
    } catch (_) {
      _error = '无法读取登录状态，请重新登录';
    }
    if (mounted) setState(() => _checking = false);
  }

  @override
  void dispose() {
    _username.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _sync() async {
    if (_token == null &&
        (_username.text.trim().isEmpty || _password.text.isEmpty)) {
      setState(() => _error = '请输入小米账号和密码');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _status = _token == null ? '正在登录小米账号…' : '正在同步设备…';
    });
    try {
      var token = _token;
      if (token == null) {
        try {
          token = await _service.login(
            username: _username.text.trim(),
            password: _password.text,
          );
        } on MiAccountTwoFactorRequired catch (challenge) {
          if (!mounted) return;
          setState(() => _status = '请在小米验证窗口完成验证');
          final cookies = await createMiAccountTwoFactorResolver().resolve(
            context,
            Uri.parse(challenge.url),
          );
          token = await _service.completeTwoFactorLogin(
            challenge: challenge,
            cookieHeader: cookies,
          );
        } finally {
          _password.clear();
        }
        await _service.persistToken(token);
        _token = token;
      }
      if (mounted) setState(() => _status = '正在同步设备和认证资料…');
      final devices = await _service.fetchBoundDevices(token: token);
      final int count;
      try {
        count = await widget.importDevices(devices);
      } catch (error) {
        if (mounted) setState(() => _error = friendlyError(error));
        return;
      }
      if (!mounted) return;
      if (count == 0) {
        setState(() => _error = '账号未返回可用的手环 Key。请确认设备已绑定到此小米账号，也可以手动添加。');
      } else {
        Navigator.of(context).pop(count);
      }
    } on MiAccountSessionExpired {
      _token = null;
      if (mounted) setState(() => _error = '登录已过期，请重新输入账号和密码');
    } on DioException catch (_) {
      if (mounted) {
        setState(() => _error = '无法连接小米服务。请检查网络，关闭影响连接的代理后重试；服务暂时不可用时可稍后同步。');
      }
    } on TimeoutException catch (_) {
      if (mounted) setState(() => _error = '同步等待超时，请检查网络后重新同步。');
    } on PlatformException catch (_) {
      if (mounted) {
        setState(() => _error = '无法完成系统验证或保存安全凭据，请重试；若持续失败，请重新打开应用后再同步。');
      }
    } catch (_) {
      // Do not surface request objects, passwords, cookies or verification URLs.
      if (mounted) setState(() => _error = '登录或同步失败，请检查网络、账号密码及小米验证结果后重试。');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: AlertDialog(
      scrollable: true,
      title: const Text('同步小米设备'),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('已添加的设备也会更新 Key。恢复出厂设置后，请先在小米运动健康重新绑定，再同步。'),
            const SizedBox(height: 14),
            const Text('使用小米运动健康绑定的账号，自动获取设备和连接 Key。'),
            const SizedBox(height: 24),
            if (_checking)
              const LinearProgressIndicator()
            else if (_token == null) ...[
              TextField(
                controller: _username,
                enabled: !_busy,
                decoration: const InputDecoration(
                  labelText: '小米账号',
                  hintText: '手机号 / 邮箱 / 小米 ID',
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _password,
                enabled: !_busy,
                obscureText: true,
                autocorrect: false,
                enableSuggestions: false,
                onSubmitted: (_) {
                  if (!_busy) unawaited(_sync());
                },
                decoration: const InputDecoration(labelText: '密码'),
              ),
            ] else ...[
              Row(
                children: [
                  Icon(
                    Icons.verified_user_outlined,
                    color: context.colors.success,
                  ),
                  const SizedBox(width: 8),
                  const Expanded(child: Text('已保存小米账号登录状态')),
                ],
              ),
              TextButton(
                onPressed: _busy
                    ? null
                    : () async {
                        await _service.clearStoredToken();
                        if (mounted) setState(() => _token = null);
                      },
                child: const Text('退出账号 / 使用其他账号'),
              ),
            ],
            if (_busy) ...[
              const SizedBox(height: 20),
              const LinearProgressIndicator(),
              const SizedBox(height: 10),
              Text(_status),
            ],
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 16),
                child: Text(
                  _error!,
                  style: TextStyle(color: context.colors.danger),
                ),
              ),
            const SizedBox(height: 20),
            Text(
              Platform.isAndroid
                  ? '密码不保存。登录状态和设备 Key 使用 Android Keystore 在本机加密保存。'
                  : '密码不保存。登录状态和设备 Key 使用 Windows 本地加密保存。',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: _busy || _checking ? null : _sync,
          child: Text(_token == null ? '登录并同步' : '同步设备'),
        ),
      ],
    ),
  );
}
