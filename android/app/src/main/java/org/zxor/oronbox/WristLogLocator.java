package org.zxor.oronbox;
import java.io.*;
import java.nio.file.*;
import java.util.*;

/** Searches only supplied log folders, without reading log contents. */
public final class WristLogLocator {
    public static boolean supported(String name) {
        String n = name.toLowerCase(Locale.ROOT);
        return n.endsWith(".zip") || n.matches("xiaomifit\\.(main|device)\\.log(?:\\.(?:bak\\.)?[0-9]+)?");
    }
    public static File latest(File[] roots, long notBefore) throws IOException {
        File newest = null;
        int visited = 0;
        for (File root : roots) {
            if (!root.isDirectory() || Files.isSymbolicLink(root.toPath())) continue;
            Path base = root.getCanonicalFile().toPath();
            ArrayDeque<Path> pending = new ArrayDeque<>(); pending.add(base);
            while (!pending.isEmpty()) {
                try (DirectoryStream<Path> children = Files.newDirectoryStream(pending.removeFirst())) {
                    for (Path child : children) {
                        if (Thread.currentThread().isInterrupted()) throw new IOException("读取已取消");
                        if (++visited > 2048) throw new IOException("日志文件数量过多");
                        if (Files.isSymbolicLink(child)) continue;
                        Path path = child.toFile().getCanonicalFile().toPath();
                        if (!path.startsWith(base)) continue;
                        if (Files.isDirectory(path)) {
                            if (base.relativize(path).getNameCount() <= 3) pending.add(path);
                            continue;
                        }
                        File file = path.toFile();
                        if (file.isFile() && supported(file.getName()) && file.length() > 0 && file.lastModified() >= notBefore &&
                            (newest == null || file.lastModified() > newest.lastModified() ||
                            (file.lastModified() == newest.lastModified() && file.getName().compareTo(newest.getName()) > 0))) newest = file;
                    }
                }
            }
        }
        return newest;
    }
}
