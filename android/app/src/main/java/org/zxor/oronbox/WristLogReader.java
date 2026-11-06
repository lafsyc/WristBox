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
    // Keep Key fields that cross a window boundary without retaining a whole
    // physical line. Oversized lines are fragments, never device metadata.
    static final int OVERLAP = 1024;
    private long expanded, retained;
    private final long deadline = System.nanoTime() + 30_000_000_000L;
    private final List<Map<String, Object>> matches = new ArrayList<>();
    private final Set<String> addresses = new LinkedHashSet<>();
    private boolean addressPoolComplete = true;
    private static final java.util.regex.Pattern MAC = java.util.regex.Pattern.compile(
        "(?<![0-9a-fA-F])(?:[0-9a-fA-F]{2}[:-]){5}[0-9a-fA-F]{2}(?![0-9a-fA-F])");
    private void collectAddresses(CharSequence text) {
        java.util.regex.Matcher matcher = MAC.matcher(text);
        while (matcher.find()) {
            String address = matcher.group().replace('-', ':').toUpperCase(Locale.ROOT);
            if (address.equals("00:00:00:00:00:00") || address.equals("FF:FF:FF:FF:FF:FF") || address.equals("02:00:00:00:00:00")) continue;
            if (addresses.size() < 512 || addresses.contains(address)) addresses.add(address);
            else addressPoolComplete = false;
        }
    }
    private List<Map<String, Object>> finish() {
        if (!matches.isEmpty()) {
            matches.get(0).put("addressCandidates", new ArrayList<>(addresses));
            matches.get(0).put("addressPoolComplete", addressPoolComplete);
        }
        return matches;
    }

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
            return finish();
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
                if (!entry.isDirectory() && name.matches("(?i)XiaomiFit\\.(main|device)\\.log(?:\\.(?:bak\\.)?[0-9]+)?")) {
                    found = true;
                    lines(content, name);
                } else if (!entry.isDirectory() && name.matches("(?i).+\\.log(?:\\.(?:bak\\.)?[0-9]+)?")) {
                    // Other diagnostic logs supply only address candidates, never Keys.
                    lines(content, name, false);
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
        return finish();
    }

    private void lines(InputStream stream, String name) throws IOException { lines(stream, name, true); }
    private void lines(InputStream stream, String name, boolean parseKeys) throws IOException {
        InputStreamReader reader = new InputStreamReader(stream, StandardCharsets.UTF_8);
        char[] buffer = new char[4096];
        StringBuilder line = new StringBuilder();
        boolean continued = false;
        int number = 1, size;
        JsonRecords objects = new JsonRecords(name);
        while ((size = reader.read(buffer)) != -1) {
            check();
            for (int i = 0; i < size; i++) {
                char c = buffer[i];
                if (parseKeys) objects.accept(c, number);
                if (c == '\n') {
                    collectAddresses(line);
                    if (parseKeys && !objects.coversLine(line, number)) retain(line, name, number, continued, false);
                    number++;
                    line.setLength(0);
                    continued = false;
                }
                else {
                    if (line.length() >= MAX_LINE) {
                        collectAddresses(line);
                        if (parseKeys) retain(line, name, number, continued, true);
                        line.delete(0, line.length() - OVERLAP);
                        continued = true;
                    }
                    line.append(c);
                }
            }
        }
        collectAddresses(line);
        if (parseKeys && line.length() > 0 && !objects.coversLine(line, number)) retain(line, name, number, continued, false);
    }

    /** Follow string/escape context across windows, so braces inside strings are
     * never interpreted as device records. Each frame and the output are bounded.
     * Oversized outer objects can still contain small complete device objects. */
    private static final int KEY_OR_END = 0, KEY = 1, COLON = 2,
        VALUE = 3, VALUE_OR_END = 4, AFTER_VALUE = 5;
    private static boolean whitespace(char c) {
        return c == ' ' || c == 9 || c == 10 || c == 13;
    }
    private final class JsonRecords {
        final String source;
        final Deque<Frame> stack = new ArrayDeque<>();
        boolean quoted, escaped, stringIsKey, discardLine;
        int unicodeRemaining, skippedDepth;
        StringBuilder primitive;
        String completedRoot;
        int completedRootLine = -1;
        boolean coversLine(StringBuilder raw, int line) {
            return completedRootLine == line && completedRoot != null && completedRoot.equals(raw.toString().trim());
        }
        JsonRecords(String source) { this.source = source; }

        void reset() {
            stack.clear(); quoted = false; escaped = false;
            unicodeRemaining = 0; skippedDepth = 0; primitive = null; discardLine = false;
        }
        void restart(char c, int line) {
            reset();
            if (c == '{' || c == '[') stack.push(new Frame(line, c));
        }
        void accept(char c, int line) throws IOException {
            if (discardLine) {
                if (c == 10 || c == 13) reset();
                return;
            }
            // Skip an over-deep subtree using a counter, without allocating
            // frames or parsing apparent objects inside its quoted strings.
            if (skippedDepth > 0) {
                // A fresh physical line is a recovery boundary. The discarded
                // parents cannot supply metadata to any subsequently found object.
                if (c == 10 || c == 13) { reset(); return; }
                if (quoted) {
                    if (escaped) escaped = false;
                    else if (c == '\\') escaped = true;
                    else if (c == '"') quoted = false;
                } else if (c == '"') quoted = true;
                else if (c == '{' || c == '[') skippedDepth++;
                else if (c == '}' || c == ']') {
                    if (--skippedDepth == 0 && !stack.isEmpty()) stack.peek().stage = AFTER_VALUE;
                }
                return;
            }
            if (stack.isEmpty()) {
                if (c == 10 || c == 13) { reset(); return; }
                if (quoted) {
                    if (escaped) escaped = false;
                    else if (c == '\\') escaped = true;
                    else if (c == '"') quoted = false;
                } else if (c == '"') quoted = true;
                else if (c == '{' || c == '[') stack.push(new Frame(line, c));
                return;
            }
            Frame top = stack.peek();
            if (quoted) {
                // Reject malformed string syntax instead of carrying its state
                // into unrelated log lines. Completed objects are validated again in Dart.
                if (c < 0x20) { reset(); discardLine = c != 10 && c != 13; return; }
                top.append(c);
                if (unicodeRemaining > 0) {
                    if (Character.digit(c, 16) < 0) { reset(); discardLine = true; return; }
                    unicodeRemaining--;
                } else if (escaped) {
                    escaped = false;
                    if (c == 'u') unicodeRemaining = 4;
                    else if ("\"\\/bfnrt".indexOf(c) < 0) { reset(); discardLine = true; }
                } else if (c == '\\') escaped = true;
                else if (c == '"') {
                    quoted = false;
                    top.stage = stringIsKey ? COLON : AFTER_VALUE;
                }
                return;
            }
            if (primitive != null) {
                if (whitespace(c) || c == ',' || c == ']' || c == '}') {
                    String token = primitive.toString();
                    primitive = null;
                    if (!(token.equals("true") || token.equals("false") || token.equals("null") ||
                            token.matches("-?(0|[1-9][0-9]*)(\\.[0-9]+)?([eE][+-]?[0-9]+)?"))) {
                        restart(c, line); return;
                    }
                    top.stage = AFTER_VALUE;
                } else {
                    if (primitive.length() >= 128 || !(Character.isLetterOrDigit(c) || c == '.' || c == '+' || c == '-')) {
                        restart(c, line); return;
                    }
                    primitive.append(c); top.append(c); return;
                }
            }
            if (whitespace(c)) { top.append(c); return; }
            if (c == '}' || c == ']') {
                boolean endAllowed = top.stage == AFTER_VALUE || top.stage == KEY_OR_END || top.stage == VALUE_OR_END;
                if (!endAllowed || top.opening != (c == '}' ? '{' : '[')) { reset(); return; }
                top.append(c); stack.pop();
                if (top.text != null) {
                    retain(top.text, source, top.line, false, false, true);
                    if (stack.isEmpty() && top.line == line) {
                        completedRoot = top.text.toString();
                        completedRootLine = line;
                    }
                }
                if (!stack.isEmpty()) {
                    Frame parent = stack.peek();
                    parent.stage = AFTER_VALUE;
                    if (top.text == null) parent.text = null;
                    else parent.append(top.text);
                }
                return;
            }
            if (top.stage == KEY_OR_END || top.stage == KEY) {
                if (c != '"') { restart(c, line); return; }
                quoted = true; stringIsKey = true; top.append(c); return;
            }
            if (top.stage == COLON) {
                if (c != ':') { restart(c, line); return; }
                top.stage = VALUE; top.append(c); return;
            }
            if (top.stage == AFTER_VALUE) {
                if (c != ',') { restart(c, line); return; }
                top.stage = top.opening == '{' ? KEY : VALUE;
                top.append(c); return;
            }
            if (c == '"') {
                quoted = true; stringIsKey = false; top.append(c);
            } else if (c == '{' || c == '[') {
                if (stack.size() >= 32) {
                    for (Frame frame : stack) frame.text = null;
                    skippedDepth = 1;
                } else stack.push(new Frame(line, c));
            } else if (c == '-' || (c >= '0' && c <= '9') || c == 't' || c == 'f' || c == 'n') {
                primitive = new StringBuilder().append(c); top.append(c);
            } else restart(c, line);
        }
    }
    private static final class Frame {
        StringBuilder text;
        final int line;
        final char opening;
        int stage;
        Frame(int line, char opening) {
            this.line = line; this.opening = opening;
            stage = opening == '{' ? KEY_OR_END : VALUE_OR_END;
            text = new StringBuilder().append(opening);
        }
        void append(char c) {
            if (text != null) {
                if (text.length() >= MAX_LINE) text = null;
                else text.append(c);
            }
        }
        void append(StringBuilder child) {
            if (text != null) {
                if (text.length() + child.length() > MAX_LINE) text = null;
                else text.append(child);
            }
        }
    }

    private void retain(StringBuilder text, String source, int number,
                        boolean truncatedStart, boolean truncatedEnd) throws IOException {
        retain(text, source, number, truncatedStart, truncatedEnd, false);
    }

    private void retain(StringBuilder text, String source, int number,
                        boolean truncatedStart, boolean truncatedEnd, boolean structured) throws IOException {
        String line = text.toString();
        String lower = line.toLowerCase(Locale.ROOT);
        boolean key = lower.contains("encryptkey") || lower.contains("devicekey") || lower.contains("encrypt_key") || lower.contains("authkey") || lower.contains("auth_key");
        boolean identity = structured && (lower.contains("\"mac\"") || lower.contains("\"macaddress\"") || lower.contains("\"mac_address\"") || lower.contains("\"bluetoothaddress\"") || lower.contains("\"devicemac\"") || lower.contains("\"btmac\"") || lower.contains("\"address\""));
        if (!key && !identity) return;
        // Only the grammar-aware collector may establish device metadata.
        // Raw windows are retained for Key-only fallback and deduplicated in Dart.

        retained += line.length();
        if (matches.size() >= 512 || retained > 2 * 1024 * 1024)
            throw new LogReadException("日志中的候选记录过多，请重新导出最近的日志");
        Map<String, Object> record = new HashMap<>();
        record.put("text", line); record.put("source", source); record.put("line", number);
        record.put("metadataAllowed", structured);
        record.put("truncatedStart", truncatedStart);
        record.put("truncatedEnd", truncatedEnd);
        matches.add(record);
    }
}
