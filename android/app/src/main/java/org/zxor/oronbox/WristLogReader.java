package org.zxor.oronbox;

import java.io.*;
import java.nio.charset.StandardCharsets;
import java.util.*;
import java.util.zip.*;

/** Bounded local log reader. Never extracts an archive or writes log content. */
public final class WristLogReader {
    public static final class LogReadException extends IOException {
        LogReadException(String message) { super(message); }
    }
    static final long MAX_INPUT = 32L * 1024 * 1024;
    static final long MAX_TOTAL = 128L * 1024 * 1024;
    static final long MAX_ENTRY = 64L * 1024 * 1024;
    static final int MAX_LINE = 128 * 1024;
    private long expanded, retained;
    private final long deadline = System.nanoTime() + 30_000_000_000L;
    private final List<Map<String, Object>> matches = new ArrayList<>();

    private void check() throws IOException {
        if (Thread.currentThread().isInterrupted() || System.nanoTime() > deadline)
            throw new LogReadException("日志读取超时，请选择较小的本地日志后重试");
    }
    private final class BudgetInput extends FilterInputStream {
        private long count;
        private final long limit;
        private final boolean expansion;
        BudgetInput(InputStream in, long limit, boolean expansion) { super(in); this.limit = limit; this.expansion = expansion; }
        private void add(int n) throws IOException {
            check();
            if (n <= 0) return;
            count += n;
            if (expansion) expanded += n;
            if (count > limit || expanded > MAX_TOTAL) throw new LogReadException("日志超过安全读取大小限制，请重新导出较小的日志");
        }
        @Override public int read() throws IOException { int v = in.read(); add(v < 0 ? 0 : 1); return v; }
        @Override public int read(byte[] b, int off, int len) throws IOException { int n = in.read(b, off, len); add(n); return n; }
        @Override public void close() {} // The owning reader closes the entire source.
    }

    public List<Map<String, Object>> read(InputStream source, boolean zip) throws IOException {
        BudgetInput input = new BudgetInput(source, MAX_INPUT, false);
        if (!zip) {
            lines(new BudgetInput(input, MAX_ENTRY, true), "所选日志");
            return matches;
        }
        try (ZipInputStream archive = new ZipInputStream(input, StandardCharsets.UTF_8)) {
            int count = 0;
            boolean found = false;
            ZipEntry entry;
            while ((entry = archive.getNextEntry()) != null) {
                check();
                if (++count > 256) throw new LogReadException("压缩包文件数量过多，请选择运动健康导出的日志 ZIP");
                String path = entry.getName().replace('\\', '/');
                if (path.length() > 1024 || path.startsWith("/") || path.contains(":") ||
                        Arrays.asList(path.split("/", -1)).contains("..")) throw new LogReadException("压缩包含异常文件路径，已停止读取");
                if (entry.getSize() > MAX_ENTRY) throw new LogReadException("日志解压后过大，已停止读取");
                String name = path.substring(path.lastIndexOf('/') + 1);
                BudgetInput content = new BudgetInput(archive, MAX_ENTRY, true);
                if (!entry.isDirectory() && name.matches("(?i)XiaomiFit\\.(main|device)\\.log(?:\\.[0-9]+)?")) {
                    found = true;
                    lines(content, name);
                } else {
                    // closeEntry() alone would inflate skipped ZIP entries without a budget.
                    byte[] buffer = new byte[8192];
                    while (content.read(buffer) != -1) { check(); }
                }
                archive.closeEntry();
            }
            if (count == 0 || !found) throw new LogReadException("未找到运动健康日志，请选择导出的 ZIP，或直接选择 main/device 日志文件");
        } catch (ZipException e) {
            throw new LogReadException("ZIP 已损坏、加密或格式不支持，请重新导出日志");
        }
        return matches;
    }

    private void lines(InputStream stream, String name) throws IOException {
        InputStreamReader reader = new InputStreamReader(stream, StandardCharsets.UTF_8);
        char[] buffer = new char[4096];
        StringBuilder line = new StringBuilder();
        int number = 1, size;
        while ((size = reader.read(buffer)) != -1) {
            check();
            for (int i = 0; i < size; i++) {
                char c = buffer[i];
                if (c == '\n') { retain(line, name, number++); line.setLength(0); }
                else {
                    if (line.length() >= MAX_LINE) throw new LogReadException("日志单行过长，已停止读取，请重新导出日志");
                    line.append(c);
                }
            }
        }
        if (line.length() > 0) retain(line, name, number);
    }

    private void retain(StringBuilder text, String source, int number) throws IOException {
        String line = text.toString();
        String lower = line.toLowerCase(Locale.ROOT);
        if (!lower.contains("encryptkey") && !lower.contains("devicekey")) return;
        retained += line.length();
        if (matches.size() >= 512 || retained > 2 * 1024 * 1024)
            throw new LogReadException("日志中的候选记录过多，请重新导出最近的日志");
        Map<String, Object> record = new HashMap<>();
        record.put("text", line); record.put("source", source); record.put("line", number);
        matches.add(record);
    }
}
