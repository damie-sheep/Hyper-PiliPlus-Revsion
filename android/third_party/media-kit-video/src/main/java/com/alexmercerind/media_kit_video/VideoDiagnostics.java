package com.alexmercerind.media_kit_video;

import android.os.SystemClock;
import java.util.ArrayDeque;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.Map;

/** Opt-in bounded anonymous events; serialization is requested after navigation. */
final class VideoDiagnostics {
    private static volatile boolean enabled;
    private static final ArrayDeque<Map<String, Object>> events = new ArrayDeque<>();
    private static int dropped;

    static synchronized void record(Object owner, String event, long value) {
        if (!enabled) return;
        if (events.size() == 1024) { events.removeFirst(); dropped++; }
        final HashMap<String, Object> row = new HashMap<>();
        row.put("nativeUs", SystemClock.elapsedRealtimeNanos() / 1000);
        row.put("owner", System.identityHashCode(owner));
        row.put("event", event);
        row.put("value", value);
        events.addLast(row);
    }

    static synchronized Map<String, Object> collect(boolean enable, boolean drain) {
        enabled = enable;
        final HashMap<String, Object> result = new HashMap<>();
        result.put("nativeUs", SystemClock.elapsedRealtimeNanos() / 1000);
        result.put("dropped", dropped);
        result.put("events", drain ? new ArrayList<>(events) : new ArrayList<>());
        if (drain) { events.clear(); dropped = 0; }
        return result;
    }
}
