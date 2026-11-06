package org.zxor.oronbox;
import java.io.*;
import java.nio.file.*;
import java.nio.file.attribute.FileTime;
import java.util.*;

public final class WristLogLocatorTest {
    static File make(Path root, String name, long time, boolean empty) throws Exception {
        Path path = root.resolve(name); Files.createDirectories(path.getParent());
        Files.write(path, empty ? new byte[0] : new byte[]{1});
        Files.setLastModifiedTime(path, FileTime.fromMillis(time)); return path.toFile();
    }
    public static void main(String[] args) throws Exception {
        Path base = Path.of("dist/log-locator-test").toAbsolutePath().normalize();
        Files.createDirectories(base);
        Path fixture = Files.createTempDirectory(base, "fixture-").toRealPath();
        if (!fixture.startsWith(base.toRealPath())) throw new AssertionError("Invalid fixture root");
        try {
            Path a = Files.createDirectories(fixture.resolve("wearablelog"));
            Path b = Files.createDirectories(fixture.resolve("ResearchLog"));
            File old = make(a, "old.zip", 10000, false);
            File latest = make(b, "sub/new.ZIP", 20000, false);
            make(a, "unfinished.zip", 40000, true);
            make(a, "unrelated.txt", 50000, false);
            make(fixture, "private/newer.zip", 60000, false);
            File[] roots = {a.toFile(), b.toFile()};
            assert WristLogLocator.latest(roots, 0).equals(latest);
            assert WristLogLocator.latest(roots, 20001) == null;
            assert WristLogLocator.latest(new File[]{a.toFile()}, 0).equals(old);
            File rotated = make(a, "XiaomiFit.device.log.1", 30000, false);
            assert WristLogLocator.latest(roots, 0).equals(rotated);
            assert !WristLogLocator.supported("download.zip.part");
            assert WristLogLocator.supported("XiaomiFit.main.log");
            for (int i=0; i<2050; i++) make(a, "junk-"+i, 1, false);
            try { WristLogLocator.latest(roots, 0); throw new AssertionError("Unbounded scan accepted"); }
            catch (IOException expected) {}
            System.out.println("Log locator latest/age/scope/empty-file/rotation/budget checks passed");
        } finally {
            try (var paths=Files.walk(fixture)) {
                for (Path p : paths.sorted(Comparator.reverseOrder()).toList()) {
                    if (!p.toAbsolutePath().normalize().startsWith(fixture)) throw new AssertionError("Cleanup outside fixture");
                    Files.deleteIfExists(p);
                }
            }
        }
    }
}
