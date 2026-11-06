import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:oronbox/src/core/services/shared_prefs_service.dart';

import 'network_error.dart';
import 'account_profile_dialog.dart';
import 'profile_dashboard.dart';

const _accountBase = String.fromEnvironment(
  'WRISTBOX_AUTH_URL',
  // Configure the deployment endpoint at build time.
  defaultValue: 'https://api.example.invalid/wristbox-accounts',
);
const _sessionKey = 'wristbox.account.session';

class WristBoxSession {
  const WristBoxSession(
    this.token,
    this.email,
    this.role, {
    this.id,
    this.nickname = '',
    this.avatar,
  });
  final String token, email, role;
  final int? id;
  final String nickname;
  final String? avatar;
  String get displayName => nickname.isNotEmpty ? nickname : 'WristBox 用户';
  factory WristBoxSession.fromJson(Map<String, dynamic> json) {
    final user = (json['user'] as Map).cast<String, dynamic>();
    return WristBoxSession(
      json['token'] as String,
      user['email'] as String,
      user['role'] as String,
      id: user['id'] as int?,
      nickname: user['nickname'] as String? ?? '',
      avatar: user['avatar'] as String?,
    );
  }
  Map<String, dynamic> toJson() => {
    'token': token,
    'user': {
      'email': email,
      'role': role,
      'id': id,
      'nickname': nickname,
      'avatar': avatar,
    },
  };
}

class WristBoxAccountService {
  WristBoxAccountService({Dio? dio, String? baseUrl})
    : _dio =
          dio ??
          Dio(
            BaseOptions(
              connectTimeout: const Duration(seconds: 15),
              receiveTimeout: const Duration(seconds: 20),
              sendTimeout: const Duration(seconds: 20),
              followRedirects: false,
            ),
          ),
      _baseUrl = baseUrl ?? _accountBase,
      _customDio = dio != null;
  final Dio _dio;
  final String _baseUrl;
  final bool _customDio;
  bool _trustConfigured = false;
  Future<void> _configureTrust() async {
    if (_trustConfigured ||
        _customDio ||
        Uri.parse(_baseUrl).host != Uri.parse(_accountBase).host) {
      return;
    }
    final certificate = await rootBundle.load(
      "assets/certificates/wristbox-server-ca.pem",
    );
    final context = SecurityContext(withTrustedRoots: false);
    context.setTrustedCertificatesBytes(
      certificate.buffer.asUint8List(
        certificate.offsetInBytes,
        certificate.lengthInBytes,
      ),
    );
    _dio.httpClientAdapter = IOHttpClientAdapter(
      createHttpClient: () => HttpClient(context: context),
    );
    _trustConfigured = true;
  }

  String _url(String path) {
    final uri = Uri.tryParse(_baseUrl);
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment) {
      throw StateError('账号服务尚未配置安全连接，请联系管理员');
    }
    return '${_baseUrl.replaceAll(RegExp(r"/+$"), '')}$path';
  }

  Future<Map<String, dynamic>> _post(
    String path,
    Map<String, dynamic> body, {
    String? token,
  }) async {
    _url(path);
    await _configureTrust();
    final result = await _dio.post<dynamic>(
      _url(path),
      data: body,
      options: Options(
        headers: token == null ? null : {'Authorization': 'Bearer $token'},
      ),
    );
    return (result.data as Map).cast<String, dynamic>();
  }

  Future<Dio> authenticatedClient(WristBoxSession session) async {
    _url('');
    await _configureTrust();
    _dio.options.baseUrl = '${_baseUrl.replaceAll(RegExp(r"/+$"), '')}/';
    _dio.options.headers['Authorization'] = 'Bearer ${session.token}';
    return _dio;
  }

  Future<Dio> publicClient() async {
    _url('');
    await _configureTrust();
    _dio.options.baseUrl = '${_baseUrl.replaceAll(RegExp(r"/+$"), '')}/';
    _dio.options.headers.remove('Authorization');
    return _dio;
  }

  Future<void> sendCode(String email, bool register) async {
    await _post('/v1/auth/code', {
      'email': email,
      'purpose': register ? 'register' : 'login',
    });
  }

  Future<WristBoxSession> authenticate(
    String email,
    String secret, {
    required bool register,
    required bool useCode,
    String? password,
  }) async {
    final body = <String, dynamic>{'email': email};
    body[useCode ? 'code' : 'password'] = secret;
    if (register && password != null && password.isNotEmpty) {
      body['password'] = password;
    }
    final session = WristBoxSession.fromJson(
      await _post(register ? '/v1/auth/register' : '/v1/auth/login', body),
    );
    final prefs = SharedPrefsService.instance;
    if (!prefs.isSecureStorageReady) throw StateError('安全存储不可用，无法保存登录状态');
    await prefs.setString(_sessionKey, jsonEncode(session.toJson()));
    return session;
  }

  WristBoxSession? stored() {
    final prefs = SharedPrefsService.instance;
    if (!prefs.isInitialized || !prefs.isSecureStorageReady) return null;
    final raw = prefs.getString(_sessionKey);
    if (raw == null) return null;
    try {
      return WristBoxSession.fromJson(
        (jsonDecode(raw) as Map).cast<String, dynamic>(),
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> logout(WristBoxSession session) async {
    try {
      await _post('/v1/auth/logout', {}, token: session.token);
    } on DioException catch (error) {
      if (error.response?.statusCode != 401) rethrow;
    }
    await SharedPrefsService.instance.remove(_sessionKey);
  }

  Future<WristBoxSession> _updated(
    WristBoxSession original,
    dynamic data,
  ) async {
    final updated = WristBoxSession.fromJson({
      'token': original.token,
      'user': (data as Map)['user'],
    });
    // Do not overwrite a newer login or resurrect a session after logout.
    if (stored()?.token == original.token) {
      await SharedPrefsService.instance.setString(
        _sessionKey,
        jsonEncode(updated.toJson()),
      );
    }
    return updated;
  }

  Future<WristBoxSession> refresh(WristBoxSession session) async {
    final client = await authenticatedClient(session);
    return _updated(session, (await client.get<dynamic>('v1/auth/me')).data);
  }

  Future<WristBoxSession> updateProfile(
    WristBoxSession session,
    String nickname,
  ) async {
    final client = await authenticatedClient(session);
    return _updated(
      session,
      (await client.patch<dynamic>(
        'v1/account/profile',
        data: {'nickname': nickname},
      )).data,
    );
  }

  Future<WristBoxSession> updateAvatar(
    WristBoxSession session,
    Uint8List? bytes,
  ) async {
    final client = await authenticatedClient(session);
    final result = bytes == null
        ? await client.delete<dynamic>('v1/account/avatar')
        : await client.post<dynamic>(
            'v1/account/avatar',
            data: Stream.value(bytes),
            options: Options(
              headers: {
                'Content-Type': 'application/octet-stream',
                'Content-Length': bytes.length,
              },
            ),
          );
    return _updated(session, result.data);
  }
}

String accountError(Object error) {
  if (error is StateError) return error.message;
  if (error is DioException) {
    final data = error.response?.data;
    if ([400, 413].contains(error.response?.statusCode) &&
        data is Map &&
        data['detail'] is String) {
      return data['detail'] as String;
    }
    if (error.response?.statusCode == 403 &&
        data is Map &&
        ['暂时停止新用户注册', '账号已被停用，请联系管理员'].contains(data['detail'])) {
      return data['detail'] as String;
    }
    return switch (error.response?.statusCode) {
      400 || 422 => '输入格式不正确，请检查填写内容后重试',
      401 => '验证码或密码不正确，或验证码已过期',
      403 => '此账号暂不可用，请联系管理员',
      409 => '账号已存在或当前操作不适用，请尝试登录',
      429 => '操作太频繁，请稍后再试',
      null => networkErrorMessage(error),
      _ => '账号服务暂时不可用，请稍后再试',
    };
  }
  return '操作未完成，请稍后重试';
}

class WristBoxAccountButton extends StatefulWidget {
  const WristBoxAccountButton({
    super.key,
    this.onChanged,
    this.prominent = false,
  });
  final VoidCallback? onChanged;
  final bool prominent;
  @override
  State<WristBoxAccountButton> createState() => _WristBoxAccountButtonState();
}

class _WristBoxAccountButtonState extends State<WristBoxAccountButton> {
  final _service = WristBoxAccountService();
  WristBoxSession? _session;
  @override
  void initState() {
    super.initState();
    _session = _service.stored();
    final cached = _session;
    if (cached != null) {
      _service
          .refresh(cached)
          .then((fresh) {
            if (mounted && _session?.token == fresh.token) {
              setState(() => _session = fresh);
            }
          })
          .catchError((Object _) {
            // Keep the cached profile offline; opening the editor shows sync errors.
          });
    }
  }

  Future<void> _open() async {
    if (_session != null) {
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) =>
            AccountProfileDialog(service: _service, session: _session!),
      );
      if (mounted) {
        setState(() => _session = _service.stored());
        widget.onChanged?.call();
      }
      return;
    }
    final result = await showDialog<WristBoxSession>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _WristBoxLoginDialog(service: _service),
    );
    if (mounted && result != null) {
      setState(() => _session = result);
      widget.onChanged?.call();
    }
  }

  @override
  Widget build(BuildContext context) => widget.prominent
      ? AccountIdentityCard(session: _session, onOpen: _open)
      : Material(
          color: Colors.transparent,
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 12),
            leading: AccountAvatar(session: _session, radius: 20),
            title: Text(
              _session?.displayName ?? '邮箱账号',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text(
              _session == null
                  ? '邮箱登录 / 注册'
                  : '${_session!.id == null ? '账号资料' : 'ID ${_session!.id}'} · ${_session!.email}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: _open,
          ),
        );
}

class _WristBoxLoginDialog extends StatefulWidget {
  const _WristBoxLoginDialog({required this.service});
  final WristBoxAccountService service;
  @override
  State<_WristBoxLoginDialog> createState() => _WristBoxLoginDialogState();
}

class _WristBoxLoginDialogState extends State<_WristBoxLoginDialog> {
  final _email = TextEditingController(),
      _secret = TextEditingController(),
      _password = TextEditingController();
  bool _register = false, _useCode = true, _busy = false;
  String? _error, _status;
  @override
  void dispose() {
    _email.dispose();
    _secret.dispose();
    _password.dispose();
    super.dispose();
  }

  bool get _validEmail =>
      RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(_email.text.trim());
  Future<void> _send() async {
    if (!_validEmail) {
      setState(() => _error = '请输入有效的邮箱地址');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _status = null;
    });
    try {
      await widget.service.sendCode(_email.text.trim(), _register);
      if (mounted) setState(() => _status = '验证码已发送，请检查邮箱');
    } catch (e) {
      if (mounted) setState(() => _error = accountError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _submit() async {
    if (!_validEmail) {
      setState(() => _error = '请输入有效的邮箱地址');
      return;
    }
    if (_secret.text.isEmpty) {
      setState(() => _error = _useCode ? '请输入邮箱验证码' : '请输入密码');
      return;
    }
    if (_register && _password.text.isNotEmpty && _password.text.length < 12) {
      setState(() => _error = '密码需至少 12 位，或留空仅使用验证码登录');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _status = null;
    });
    try {
      final session = await widget.service.authenticate(
        _email.text.trim(),
        _secret.text,
        register: _register,
        useCode: _useCode,
        password: _register ? _password.text : null,
      );
      if (mounted) Navigator.pop(context, session);
    } catch (e) {
      if (mounted) setState(() => _error = accountError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _mode(bool register, bool useCode) => setState(() {
    _register = register;
    _useCode = useCode;
    _secret.clear();
    _password.clear();
    _error = null;
    _status = null;
  });
  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(_register ? '注册 WristBox 账号' : '登录 WristBox 账号'),
    content: SizedBox(
      width: 410,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('WristBox 账号与小米账号分开；小米账号用于同步手环。'),
            const SizedBox(height: 16),
            TextField(
              controller: _email,
              enabled: !_busy,
              keyboardType: TextInputType.emailAddress,
              autofillHints: const [AutofillHints.email],
              decoration: const InputDecoration(labelText: '邮箱'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _secret,
              enabled: !_busy,
              obscureText: !_useCode,
              keyboardType: _useCode
                  ? TextInputType.number
                  : TextInputType.visiblePassword,
              decoration: InputDecoration(
                labelText: _useCode ? '邮箱验证码' : '密码',
                suffixIcon: _useCode
                    ? TextButton(
                        onPressed: _busy ? null : _send,
                        child: const Text('发送验证码'),
                      )
                    : null,
              ),
            ),
            if (_register) ...[
              const SizedBox(height: 12),
              TextField(
                controller: _password,
                enabled: !_busy,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: '设置密码（可选，至少 12 位）',
                ),
              ),
            ],
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            if (_status != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(_status!),
              ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 4,
              children: [
                if (!_register)
                  TextButton(
                    onPressed: _busy ? null : () => _mode(false, !_useCode),
                    child: Text(_useCode ? '使用密码登录' : '使用验证码登录'),
                  ),
                TextButton(
                  onPressed: _busy ? null : () => _mode(!_register, true),
                  child: Text(_register ? '已有账号，去登录' : '注册新账号'),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: _busy ? null : () => Navigator.pop(context),
        child: const Text('取消'),
      ),
      FilledButton(
        onPressed: _busy ? null : _submit,
        child: Text(
          _busy
              ? '请稍候…'
              : _register
              ? '注册并登录'
              : '登录',
        ),
      ),
    ],
  );
}
