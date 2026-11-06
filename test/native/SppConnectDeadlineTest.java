package org.zxor.oronbox;

public final class SppConnectDeadlineTest {
    public static void main(String[] args) {
        SppConnectDeadline normal = new SppConnectDeadline(1000, 8000);
        assert normal.remaining(8999, false) == 1;
        assert normal.remaining(9000, false) == 0;
        SppConnectDeadline prompt = new SppConnectDeadline(1000, 8000);
        assert prompt.remaining(2000, true) == 44000;
        // A prompt that finishes must retain time for the socket to finish.
        assert prompt.remaining(12000, false) == 34000;
        // Repeated pairing notifications must never extend the absolute cap.
        assert prompt.remaining(45999, true) == 1;
        assert prompt.remaining(46000, true) == 0;
        assert prompt.remaining(80000, true) == 0;
        System.out.println("SPP pairing deadline boundary checks passed");
    }
}
