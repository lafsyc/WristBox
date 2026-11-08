import 'package:oronbox/src/features/devices/controllers/device_manager.dart';

String mobileConnectionStatus(DeviceConnectionPhase? phase) => switch (phase) {
  DeviceConnectionPhase.preparing => '准备连接',
  DeviceConnectionPhase.pairing => '等待确认配对',
  DeviceConnectionPhase.connectingTransport => '连接蓝牙通道',
  DeviceConnectionPhase.compatibility => '尝试兼容连接',
  DeviceConnectionPhase.waitingToRetry => '稍后重新连接',
  DeviceConnectionPhase.initializingProtocol => '协商通信协议',
  DeviceConnectionPhase.authenticating => '验证设备 Key',
  DeviceConnectionPhase.fetchingDeviceStatus => '读取设备信息',
  null => '连接中',
};

String mobileConnectionHint(DeviceConnectionPhase? phase) => switch (phase) {
  DeviceConnectionPhase.pairing => '请查看手机和手环上的配对提示并确认',
  DeviceConnectionPhase.waitingToRetry => '连接暂未成功，保持手环靠近；可随时取消',
  DeviceConnectionPhase.compatibility => '正在尝试其他连接通道，请保持手环唤醒',
  DeviceConnectionPhase.authenticating => '正在校验设备身份，请稍候',
  _ => '保持手环在附近，正在建立可用连接',
};
