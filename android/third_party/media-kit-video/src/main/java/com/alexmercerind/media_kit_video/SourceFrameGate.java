package com.alexmercerind.media_kit_video;

/** Per-output, per-open gate. Never reuses the controller's one-shot first frame. */
public final class SourceFrameGate {
    public interface Completion { void complete(boolean ready); }
    public interface OutcomeCompletion { void complete(String reason); }
    private long generation = -1;
    private int remaining;
    private OutcomeCompletion completion;
    private boolean closed;

    public synchronized void arm(long value, Completion next) {
        armWithReason(value, reason -> next.complete(reason.equals("candidate")));
    }

    public synchronized boolean armWithReason(long value, OutcomeCompletion next) {
        if (closed || value <= generation) {
            next.complete(closed ? "disposed" : "rejected");
            return false;
        }
        finish("superseded");
        generation = value;
        remaining = 2;
        completion = next;
        return true;
    }

    public synchronized void frame() {
        frame(generation);
    }

    public synchronized void frame(long observedGeneration) {
        if (observedGeneration != generation) return;
        if (completion != null && --remaining == 0) finish("candidate");
    }

    /** A replacement Surface starts fresh within the original timeout. */
    public synchronized void resetObservations() {
        if (completion != null) remaining = 2;
    }

    public synchronized void cancel(long value) {
        if (value == generation) finish("cancelled");
    }

    public synchronized void timeout(long value) {
        if (value == generation) finish("timeout");
    }

    public synchronized void close() {
        closed = true;
        finish("disposed");
    }

    private void finish(String reason) {
        final OutcomeCompletion previous = completion;
        completion = null;
        if (previous != null) previous.complete(reason);
    }
}
