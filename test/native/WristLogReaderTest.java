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
        // Unrelated long lines must not abort a later useful record.
        rows = read(zip("XiaomiFit.main.log", "x".repeat(1024 * 1024) + "\n" + keyLine), true);
        assert rows.size() == 1;
        assert rows.get(0).get("line").equals(2);
        assert rows.get(0).get("truncatedStart").equals(false);
        // Scan beginning, middle, end and every split within a Key field.
        String field = " encryptKey=0123456789abcdef0123456789abcdef ";
        for (int cut = 0; cut <= field.length(); cut++) {
            String body = "x".repeat(WristLogReader.MAX_LINE - cut) + field + "x".repeat(200000);
            rows = read(body.getBytes(StandardCharsets.UTF_8), false);
            assert rows.stream().anyMatch(r -> ((String) r.get("text")).contains(field));
            assert rows.stream().allMatch(r -> ((String) r.get("text")).length() <= WristLogReader.MAX_LINE);
            assert rows.stream().allMatch(r -> r.get("line").equals(1));
            assert rows.stream().allMatch(r -> r.get("truncatedStart").equals(true) || r.get("truncatedEnd").equals(true));
        }
        for (String body : List.of(field + "x".repeat(300000), "x".repeat(300000) + field)) {
            rows = read(body.getBytes(StandardCharsets.UTF_8), false);
            assert rows.stream().anyMatch(r -> ((String) r.get("text")).contains(field));
        }
        assert read("x".repeat(300000).getBytes(StandardCharsets.UTF_8), false).isEmpty();
        rejects((keyLine + "\n").repeat(513).getBytes(StandardCharsets.UTF_8), false);
        rejects((keyLine + "x".repeat(120000) + "\n").repeat(18).getBytes(StandardCharsets.UTF_8), false);
        // Complete device objects survive oversized outer arrays and windows.
        String device = "{\"did\":\"d1\",\"mac\":\"AA:BB:CC:DD:EE:01\",\"encryptKey\":\"0123456789abcdef0123456789abcdef\",\"model\":\"n67\"}";
        rows = read(device.getBytes(StandardCharsets.UTF_8), false);
        assert rows.size() == 1 && Boolean.TRUE.equals(rows.get(0).get("metadataAllowed"));
        String longArray = "[\"" + "x".repeat(300000) + "\"," + device + "]";
        rows = read(longArray.getBytes(StandardCharsets.UTF_8), false);
        assert rows.stream().anyMatch(r -> r.get("text").equals(device) && r.get("truncatedStart").equals(false) && r.get("truncatedEnd").equals(false));
        // A quoted fake object in a huge string must not establish identity.
        String escapedDevice = device.replace("\"", "\\\"");
        String quotedFake = "[\"" + "x".repeat(131050) + escapedDevice + "x".repeat(150000) + "\"]";
        rows = read(quotedFake.getBytes(StandardCharsets.UTF_8), false);
        assert rows.stream().noneMatch(r -> r.get("text").equals(device));
        String multi = device.replace(",", ",\n");
        rows = read(multi.getBytes(StandardCharsets.UTF_8), false);
        assert rows.stream().anyMatch(r -> r.get("text").equals(multi));
        String info = "{\"did\":\"d1\",\"mac\":\"AA:BB:CC:DD:EE:01\"}";
        assert read(info.getBytes(StandardCharsets.UTF_8), false).stream().anyMatch(r -> r.get("text").equals(info));
        // Logcat tags and incomplete non-JSON diagnostics are not JSON nesting.
        rows = read(("[INFO unfinished message\n".repeat(80) + device).getBytes(StandardCharsets.UTF_8), false);
        assert rows.stream().anyMatch(r -> r.get("text").equals(device) && Boolean.TRUE.equals(r.get("metadataAllowed")));
        // A genuinely over-deep subtree must not abort unrelated records.
        rows = read(("[".repeat(80) + device + "]".repeat(80) + "\n" + device).getBytes(StandardCharsets.UTF_8), false);
        assert rows.stream().anyMatch(r -> r.get("text").equals(device) && Boolean.TRUE.equals(r.get("metadataAllowed")));
        // Skip deep siblings without losing the following device on the same line.
        String deepSibling = "[".repeat(80) + "0" + "]".repeat(80);
        rows = read(("[" + deepSibling + "," + device + "]").getBytes(StandardCharsets.UTF_8), false);
        assert rows.stream().anyMatch(r -> r.get("text").equals(device) && Boolean.TRUE.equals(r.get("metadataAllowed")));
        // All JSON scalar forms and escaped text preserve the enclosing device.
        String scalarDevice = device.replace("{", "{\"flags\":[true,false,null,0,-1,1.25,2e-3],\"label\":\"quote\\\" bracket[] unicode\\u4e2d\",");
        rows = read(scalarDevice.getBytes(StandardCharsets.UTF_8), false);
        assert rows.stream().anyMatch(r -> r.get("text").equals(scalarDevice) && Boolean.TRUE.equals(r.get("metadataAllowed")));
        // Invalid strings must not expose apparent objects inside their remainder.
        String malformedString = "{\"message\":\"\\q " + device + "\"}\n" + device;
        rows = read(malformedString.getBytes(StandardCharsets.UTF_8), false);
        assert rows.stream().noneMatch(r -> r.get("line").equals(1) && Boolean.TRUE.equals(r.get("metadataAllowed")));
        assert rows.stream().anyMatch(r -> r.get("line").equals(2) && r.get("text").equals(device) && Boolean.TRUE.equals(r.get("metadataAllowed")));
        // A malformed/truncated record recovers before subsequent valid records.
        for (String noise : List.of("[INFO] [Bluetooth Connected]\n", "{unfinished\n", "[123broken\n", "{\"a\":\"unclosed\n")) {
            rows = read((noise.repeat(80) + multi).getBytes(StandardCharsets.UTF_8), false);
            assert rows.stream().anyMatch(r -> r.get("text").equals(multi) && Boolean.TRUE.equals(r.get("metadataAllowed")));
        }
        // Literal/escaped braces inside a skipped deep string are never devices.
        rows = read(("[".repeat(80) + "\"" + escapedDevice + "\"" + "]".repeat(80)).getBytes(StandardCharsets.UTF_8), false);
        assert rows.stream().noneMatch(r -> Boolean.TRUE.equals(r.get("metadataAllowed")));
        // MAC-only records are retained as a bounded candidate pool, not Key associations.
        rows = read(("Bluetooth connected AA:BB:CC:DD:EE:01\n" + device).getBytes(StandardCharsets.UTF_8), false);
        assert ((List<?>) rows.get(0).get("addressCandidates")).contains("AA:BB:CC:DD:EE:01");
        assert read(zip("XiaomiFit.device.log.bak.1", device), true).stream().anyMatch(r -> r.get("text").equals(device));
        ByteArrayOutputStream mixed = new ByteArrayOutputStream();
        try (ZipOutputStream out = new ZipOutputStream(mixed)) {
            out.putNextEntry(new ZipEntry("bluetooth.log"));
            out.write(("connected 11:22:33:44:EE:01\n" + keyLine.replace("0123456789abcdef0123456789abcdef", "ffffffffffffffffffffffffffffffff")).getBytes(StandardCharsets.UTF_8));
            out.closeEntry();
            out.putNextEntry(new ZipEntry("XiaomiFit.device.log.bak.1"));
            out.write(device.getBytes(StandardCharsets.UTF_8)); out.closeEntry();
        }
        rows = read(mixed.toByteArray(), true);
        assert ((List<?>) rows.get(0).get("addressCandidates")).contains("11:22:33:44:EE:01");
        assert rows.stream().noneMatch(r -> ((String) r.get("text")).contains("ffffffffffffffffffffffffffffffff"));
        StringBuilder manyAddresses = new StringBuilder();
        for (int i = 0; i < 520; i++) manyAddresses.append(String.format("11:22:33:44:%02X:%02X\n", i / 256, i % 256));
        rows = read((manyAddresses + device).getBytes(StandardCharsets.UTF_8), false);
        assert ((List<?>) rows.get(0).get("addressCandidates")).size() == 512;
        assert Boolean.FALSE.equals(rows.get(0).get("addressPoolComplete"));
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
