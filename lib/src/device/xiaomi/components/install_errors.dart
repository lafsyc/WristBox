/// Map numeric wire codes, including builds that omit protobuf enum names.
String xiaomiInstallPrepareError(int code) => switch (code) {
  1 => '手环正在处理上一项任务，请等待片刻后重新连接再安装',
  2 => '手环提示此应用版本已存在，请刷新应用列表确认',
  3 => '手环存储空间不足，请先卸载不需要的应用',
  4 => '手环电量不足，请充电后再安装',
  5 => '手环拒绝安装更低的版本，请选择更新版本',
  6 => '手环当前固件不支持此安装操作',
  7 => '已达到手环应用数量上限，请先卸载部分应用',
  8 => '手环报告网络异常，请检查连接后重试',
  _ => '手环尚未准备好接收安装包（状态 $code），请重新连接后重试',
};

String xiaomiInstallResultError(int code) => switch (code) {
  2 => '手环未通过安装包校验，请检查版本适配和应用签名',
  _ => '手环返回安装失败（结果 $code），请刷新应用列表确认，并检查存储空间和版本适配',
};
