package org.zxor.oronbox;

/** Monotonic, bounded grace period for a user-visible Android pairing prompt. */
public final class SppConnectDeadline {
    private final long start;
    private long deadline;
    public SppConnectDeadline(long start, long normalTimeout) {
        this.start = start;
        deadline = start + normalTimeout;
    }
    public long remaining(long now, boolean pairing) {
        if (pairing) deadline = Math.max(deadline, start + 45_000);
        return Math.max(0, deadline - now);
    }
}
