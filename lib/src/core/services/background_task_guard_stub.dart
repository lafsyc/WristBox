class BackgroundTaskHandle {
  const BackgroundTaskHandle();
  Future<void> end() async {}
}

Future<BackgroundTaskHandle> beginBackgroundTask(String label) async =>
    const BackgroundTaskHandle();
