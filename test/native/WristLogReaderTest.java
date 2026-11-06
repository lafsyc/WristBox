package org.zxor.oronbox;

import java.io.*;
import java.nio.charset.StandardCharsets;
import java.util.*;
import java.util.zip.*;

/** Synthetic fixtures only: no account or device data. Run with assertions enabled. */
public final class WristLogReaderTest {
    static byte[] zip(String name, String body) throws IOException {
        ByteArrayOutputStream bytes = new ByteArrayOutputStream();
        try (ZipOutputStream out = new ZipOutputStream(bytes)) {
            out.putNextEntry(new ZipEntry(name));
            out.write(body.getBytes(StandardCharsets.UTF_8));
            out.closeEntry();
        }
        return bytes.toByteArray();
    }
    static List<Map<String, Object>> read(byte[] bytes, boolean zip) throws IOException {
        return new WristLogReader().read(new ByteArrayInputStream(bytes), zip);
    }
    static void rejects(byte[] bytes, boolean zip) throws IOException {
        try { read(bytes, zip); throw new AssertionError("Unsafe input accepted"); }
        catch (WristLogReader.LogReadException expected) {
            assert !expected.getMessage().contains("0123456789abcdef0123456789abcdef");
        }
    }
    public static void main(String[] args) throws Exception {
        String keyLine = "设备 encryptKey=0123456789abcdef0123456789abcdef";
        List<Map<String, Object>> rows = read(zip("logs/XiaomiFit.main.log", "普通日志\n" + keyLine), true);
        assert rows.size() == 1;
        assert rows.get(0).get("text").equals(keyLine);
        assert rows.get(0).get("line").equals(2);
        assert rows.get(0).get("source").equals("XiaomiFit.main.log");
        assert read(("ignored\r\n" + keyLine).getBytes(StandardCharsets.UTF_8), false).size() == 1;
        assert read(zip("XiaomiFit.device.log.1", keyLine), true).size() == 1;
        rejects(zip("unrelated.txt", keyLine), true);
        rejects(zip("../XiaomiFit.main.log", keyLine), true);
        rejects(zip("C:/XiaomiFit.main.log", keyLine), true);
        rejects("not a zip".getBytes(StandardCharsets.UTF_8), true);
        rejects(("x".repeat(128 * 1024 + 1)).getBytes(StandardCharsets.UTF_8), false);
        rejects((keyLine + "\n").repeat(513).getBytes(StandardCharsets.UTF_8), false);
        rejects((keyLine + "x".repeat(120000) + "\n").repeat(18).getBytes(StandardCharsets.UTF_8), false);
        ByteArrayOutputStream entries = new ByteArrayOutputStream();
        try (ZipOutputStream out = new ZipOutputStream(entries)) {
            for (int i = 0; i < 257; i++) {
                out.putNextEntry(new ZipEntry("entry-" + i)); out.closeEntry();
            }
        }
        rejects(entries.toByteArray(), true);
        // A skipped entry with an unknown size must still obey the inflation budget.
        ByteArrayOutputStream bomb = new ByteArrayOutputStream();
        try (ZipOutputStream out = new ZipOutputStream(bomb)) {
            out.putNextEntry(new ZipEntry("unrelated.bin"));
            byte[] block = new byte[1024 * 1024];
            for (int i = 0; i < 65; i++) out.write(block);
            out.closeEntry();
        }
        assert bomb.size() < 1024 * 1024;
        rejects(bomb.toByteArray(), true);
        System.out.println("WristLogReader: all synthetic boundary and archive checks passed");
    }
}
