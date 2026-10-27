package com.alexmercerind.media_kit_video;

import java.util.ArrayList;
import java.util.Arrays;
import java.util.List;

/** Run with javac/java; the production gate has no Android runtime dependency. */
public class SourceFrameGateTest {
    private static void equal(Object actual, Object expected) {
        if (!actual.equals(expected)) throw new AssertionError(actual + " != " + expected);
    }
    public static void main(String[] args) {
        final SourceFrameGate gate = new SourceFrameGate();
        final List<String> events = new ArrayList<>();
        gate.frame(); // Frames before arming cannot satisfy a future source.
        gate.arm(1, ready -> events.add("A:" + ready));
        gate.frame();
        equal(events.size(), 0);
        gate.frame();
        gate.frame();
        equal(events, Arrays.asList("A:true"));
        gate.arm(2, ready -> events.add("B:" + ready));
        gate.frame();
        equal(events.size(), 1); // Controller's earlier completion is not reused.
        gate.arm(3, ready -> events.add("C:" + ready));
        equal(events.get(1), "B:false");
        gate.cancel(2); // A stale timeout must not cancel C.
        gate.frame();
        equal(events.size(), 2);
        gate.frame();
        equal(events.get(2), "C:true");
        gate.arm(3, ready -> events.add("stale:" + ready));
        equal(events.get(3), "stale:false");
        gate.arm(4, ready -> events.add("timeout:" + ready));
        gate.cancel(4);
        gate.frame();
        gate.frame();
        equal(events.get(4), "timeout:false");
        gate.arm(5, ready -> events.add("dispose:" + ready));
        gate.close();
        gate.arm(6, ready -> events.add("closed:" + ready));
        equal(events, Arrays.asList("A:true", "B:false", "C:true", "stale:false", "timeout:false", "dispose:false", "closed:false"));
        System.out.println("SourceFrameGate: 7 lifecycle scenarios passed");
    }
}
