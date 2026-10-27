package com.alexmercerind.media_kit_video;

/** Per-output, per-open gate. Never reuses the controller's one-shot first frame. */
public final class SourceFrameGate {
    public interface Completion { void complete(boolean ready); }
    private long generation = -1;
    private int remaining;
    private Completion completion;
    private boolean closed;

    public synchronized void arm(long value, Completion next) {
        if (closed || value <= generation) {
            next.complete(false);
            return;
        }
        finish(false);
        generation = value;
        remaining = 2;
        completion = next;
    }

    public synchronized void frame() {
        if (completion != null && --remaining == 0) finish(true);
    }

    public synchronized void cancel(long value) {
        if (value == generation) finish(false);
    }

    public synchronized void close() {
        closed = true;
        finish(false);
    }

    private void finish(boolean ready) {
        final Completion previous = completion;
        completion = null;
        if (previous != null) previous.complete(ready);
    }
}
