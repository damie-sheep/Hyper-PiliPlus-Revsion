/**
 * This file is a part of media_kit (https://github.com/media-kit/media-kit).
 * <p>
 * Copyright © 2021 & onwards, Hitesh Kumar Saini <saini123hitesh@gmail.com>.
 * All rights reserved.
 * Use of this source code is governed by MIT license that can be found in the LICENSE file.
 */
package com.alexmercerind.media_kit_video;

import android.graphics.Canvas;
import android.graphics.Bitmap;
import android.graphics.Color;
import android.graphics.PorterDuff;
import android.os.Build;
import android.os.Handler;
import android.os.HandlerThread;
import android.os.Looper;
import android.util.Log;
import android.view.Surface;
import android.view.PixelCopy;
import android.view.View;
import android.widget.FrameLayout;

import java.lang.reflect.Field;
import java.lang.reflect.Method;
import java.util.HashMap;
import java.util.Locale;
import java.io.ByteArrayOutputStream;
import java.util.concurrent.atomic.AtomicBoolean;
import java.util.concurrent.atomic.AtomicLong;

import io.flutter.embedding.android.FlutterActivity;
import io.flutter.embedding.android.FlutterFragmentActivity;
import io.flutter.embedding.android.FlutterView;
import io.flutter.embedding.engine.FlutterEngine;
import io.flutter.embedding.engine.FlutterJNI;
import io.flutter.plugin.common.MethodChannel;
import io.flutter.view.TextureRegistry;


public class VideoOutput {
    public long id = 0;
    public long wid = 0;

    private Surface surface;
    private final TextureRegistry.SurfaceTextureEntry surfaceTextureEntry;

    private boolean flutterJNIAPIAvailable;
    private final Method newGlobalObjectRef;
    private final Method deleteGlobalObjectRef;
    private boolean waitUntilFirstFrameRenderedNotify;

    private long handle;
    private MethodChannel channelReference;
    private TextureRegistry textureRegistryReference;

    private final Object lock = new Object();
    private final SourceFrameGate sourceFrames = new SourceFrameGate();
    private final Handler mainHandler = new Handler(Looper.getMainLooper());
    private int outputWidth = 1;
    private int outputHeight = 1;
    private boolean disposed;
    private final boolean defaultListener;
    private final String experiment;
    private static final AtomicLong nextOutputEpoch = new AtomicLong();
    private final long outputEpoch = nextOutputEpoch.incrementAndGet();
    private long surfaceEpoch;
    private long availableCount;
    private long consumedCount;
    private Runnable frameTimeout;
    private static final Handler copyHandler;
    static {
        final HandlerThread thread = new HandlerThread("PiliVideoFrameCopy");
        thread.start();
        copyHandler = new Handler(thread.getLooper());
    }

    public void awaitSourceFrame(long generation, MethodChannel.Result result) {
        VideoDiagnostics.record(this, "frame:arm", generation);
        if (disposed || !flutterJNIAPIAvailable) {
            result.success(null);
            return;
        }
        if (sourceFrames.armWithReason(generation, reason -> mainHandler.post(() -> {
            VideoDiagnostics.record(this, "frame:" + reason, generation);
            result.success(reason.equals("candidate"));
        }))) scheduleFrameTimeout(generation);
    }

    public void awaitSourceFrame2(long generation, MethodChannel.Result result) {
        VideoDiagnostics.record(this, "frame:arm", generation);
        if (disposed || (!defaultListener && !flutterJNIAPIAvailable)) {
            result.success(frameOutcome(generation, disposed ? "disposed" : "unavailable"));
            return;
        }
        if (sourceFrames.armWithReason(generation, reason -> mainHandler.post(() -> {
            VideoDiagnostics.record(this, "frame:" + reason, generation);
            result.success(frameOutcome(generation, reason));
        }))) scheduleFrameTimeout(generation);
    }

    private HashMap<String, Object> frameOutcome(long generation, String status) {
        final HashMap<String, Object> result = new HashMap<>();
        result.put("version", 2);
        result.put("generation", generation);
        result.put("outputEpoch", outputEpoch);
        result.put("surfaceEpoch", surfaceEpoch);
        result.put("signal", defaultListener ? "diagnostic-consumed-proxy" : "available-proxy");
        result.put("sourceIdentityProven", false);
        result.put("variant", experiment);
        result.put("defaultListener", defaultListener);
        result.put("availableObserved", !defaultListener);
        result.put("consumedObserver", !experiment.isEmpty());
        result.put("status", status);
        result.put("availableCount", availableCount);
        result.put("consumedCount", consumedCount);
        return result;
    }

    private void scheduleFrameTimeout(long generation) {
        if (frameTimeout != null) mainHandler.removeCallbacks(frameTimeout);
        frameTimeout = () -> sourceFrames.timeout(generation);
        mainHandler.postDelayed(frameTimeout, 3000);
    }

    private void notifyFirstFrame() {
        if (disposed || waitUntilFirstFrameRenderedNotify) return;
        waitUntilFirstFrameRenderedNotify = true;
        final HashMap<String, Object> data = new HashMap<>();
        data.put("handle", handle);
        channelReference.invokeMethod("VideoOutput.WaitUntilFirstFrameRenderedNotify", data);
    }

    public void cancelSourceFrame(long generation) {
        VideoDiagnostics.record(this, "frame:cancel", generation);
        sourceFrames.cancel(generation);
    }

    /** PixelCopy scales on the native side; no mpv readback or PNG loop on Dart UI. */
    public void captureFrame(MethodChannel.Result result) {
        VideoDiagnostics.record(this, "capture:start", 0);
        if (disposed || surface == null || !surface.isValid() || outputWidth <= 1 || outputHeight <= 1) {
            result.success(null);
            return;
        }
        final double scale = Math.min(1.0, 640.0 / Math.max(outputWidth, outputHeight));
        final Bitmap bitmap = Bitmap.createBitmap(
                Math.max(1, (int) (outputWidth * scale)),
                Math.max(1, (int) (outputHeight * scale)), Bitmap.Config.ARGB_8888);
        final AtomicBoolean completed = new AtomicBoolean(false);
        mainHandler.postDelayed(() -> {
            if (completed.compareAndSet(false, true)) {
                VideoDiagnostics.record(this, "capture:timeout", 0);
                result.success(null);
            }
        }, 180);
        try {
            PixelCopy.request(surface, bitmap, status -> {
                VideoDiagnostics.record(this, "capture:pixel-copy", status);
                byte[] bytes = null;
                try {
                    if (status == PixelCopy.SUCCESS) {
                        final ByteArrayOutputStream output = new ByteArrayOutputStream();
                        bitmap.compress(Bitmap.CompressFormat.PNG, 100, output);
                        bytes = output.toByteArray();
                        VideoDiagnostics.record(this, "capture:png-encoded", bytes.length);
                    }
                } catch (Throwable error) {
                    bytes = null;
                } finally {
                    bitmap.recycle();
                }
                final byte[] data = bytes;
                mainHandler.post(() -> {
                    VideoDiagnostics.record(this, "capture:reply", data == null ? 0 : data.length);
                    if (completed.compareAndSet(false, true)) result.success(disposed ? null : data);
                });
            }, copyHandler);
        } catch (Throwable error) {
            bitmap.recycle();
            if (completed.compareAndSet(false, true)) result.success(null);
        }
    }

    VideoOutput(long handle, MethodChannel channelReference, TextureRegistry textureRegistryReference, String experiment) {
        this.experiment = experiment;
        defaultListener = "X2".equals(experiment) || "X3".equals(experiment);
        VideoDiagnostics.record(this, "surface:output-create", 0);
        this.handle = handle;
        this.channelReference = channelReference;
        this.textureRegistryReference = textureRegistryReference;
        try {
            flutterJNIAPIAvailable = false;
            waitUntilFirstFrameRenderedNotify = false;
            // com.alexmercerind.mediakitandroidhelper.MediaKitAndroidHelper is part of package:media_kit_libs_android_video & package:media_kit_libs_android_audio packages.
            // Use reflection to invoke methods of com.alexmercerind.mediakitandroidhelper.MediaKitAndroidHelper.
            Class<?> mediaKitAndroidHelperClass = Class.forName("com.alexmercerind.mediakitandroidhelper.MediaKitAndroidHelper");
            newGlobalObjectRef = mediaKitAndroidHelperClass.getDeclaredMethod("newGlobalObjectRef", Object.class);
            deleteGlobalObjectRef = mediaKitAndroidHelperClass.getDeclaredMethod("deleteGlobalObjectRef", long.class);
            newGlobalObjectRef.setAccessible(true);
            deleteGlobalObjectRef.setAccessible(true);
        } catch (Throwable e) {
            Log.i("media_kit", "package:media_kit_libs_android_video missing. Make sure you have added it to pubspec.yaml.");
            throw new RuntimeException("Failed to initialize com.alexmercerind.media_kit_video.VideoOutput.");
        }

        surfaceTextureEntry = textureRegistryReference.createSurfaceTexture();
        VideoDiagnostics.record(this, "surface:output-epoch", outputEpoch);
        VideoDiagnostics.record(this, defaultListener ? "surface:engine-listener-preserved" : "surface:legacy-listener", outputEpoch);
        // Independent public observation slot. Do not overwrite the engine's
        // available listener or reflectively mutate SurfaceTextureWrapper.
        // The callback is on the raster thread; channel/gate work stays on main.
        if (!experiment.isEmpty()) surfaceTextureEntry.setOnFrameConsumedListener(() -> mainHandler.post(() -> {
            if (disposed) return;
            consumedCount++;
            if (consumedCount <= 8 || consumedCount % 60 == 0) {
                VideoDiagnostics.record(this, "surface:consumed", consumedCount);
            }
            if (defaultListener && outputWidth > 1 && outputHeight > 1) {
                // Deliberately a stage A proxy, NOT new-source proof for B1.
                sourceFrames.frame();
                notifyFirstFrame();
            }
        }));

        // If we call setOnFrameAvailableListener after creating SurfaceTextureEntry, the texture won't be displayed inside Flutter UI, because callback set by us will override the Flutter engine's own registered callback:
        // https://github.com/flutter/engine/blob/f47e864f2dcb9c299a3a3ed22300a1dcacbdf1fe/shell/platform/android/io/flutter/view/FlutterView.java#L942-L958
        try {
            if (!flutterJNIAPIAvailable) {
                flutterJNIAPIAvailable = getFlutterJNIReference() != null;
            }
        } catch (Throwable e) {
            e.printStackTrace();
        }
        Log.i("media_kit", String.format(Locale.ENGLISH, "flutterJNIAPIAvailable = %b", flutterJNIAPIAvailable));
        if (defaultListener) {
            // Engine owns dirty + schedule. The consume observer above supplies
            // the stage A experiment signal; no unconditional first-frame ready.
        } else if (flutterJNIAPIAvailable) {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
                surfaceTextureEntry.surfaceTexture().setOnFrameAvailableListener((texture) -> {
                    synchronized (lock) {
                        try {
                            if (!disposed && outputWidth > 1 && outputHeight > 1) {
                                availableCount++;
                                if (availableCount <= 8 || availableCount % 60 == 0) {
                                    VideoDiagnostics.record(this, "surface:frame-callback", availableCount);
                                }
                                sourceFrames.frame();
                            }
                            if (!waitUntilFirstFrameRenderedNotify) {
                                waitUntilFirstFrameRenderedNotify = true;
                                final HashMap<String, Object> data = new HashMap<>();
                                data.put("handle", handle);
                                channelReference.invokeMethod("VideoOutput.WaitUntilFirstFrameRenderedNotify", data);
                                Log.i("media_kit", String.format(Locale.ENGLISH, "VideoOutput.WaitUntilFirstFrameRenderedNotify = %d", handle));
                            }

                            FlutterJNI flutterJNI = null;
                            while (flutterJNI == null) {
                                flutterJNI = getFlutterJNIReference();
                                flutterJNI.markTextureFrameAvailable(id);
                            }
                        } catch (Throwable e) {
                            e.printStackTrace();
                        }
                    }
                }, new Handler());
            } else {
                surfaceTextureEntry.surfaceTexture().setOnFrameAvailableListener((texture) -> {
                    synchronized (lock) {
                        try {
                            if (!waitUntilFirstFrameRenderedNotify) {
                                waitUntilFirstFrameRenderedNotify = true;
                                final HashMap<String, Object> data = new HashMap<>();
                                data.put("handle", handle);
                                channelReference.invokeMethod("VideoOutput.WaitUntilFirstFrameRenderedNotify", data);
                                Log.i("media_kit", String.format(Locale.ENGLISH, "VideoOutput.WaitUntilFirstFrameRenderedNotify = %d", handle));
                            }

                            FlutterJNI flutterJNI = null;
                            while (flutterJNI == null) {
                                flutterJNI = getFlutterJNIReference();
                                flutterJNI.markTextureFrameAvailable(id);
                            }
                        } catch (Throwable e) {
                            e.printStackTrace();
                        }
                    }
                });
            }
        } else {
            if (!waitUntilFirstFrameRenderedNotify) {
                waitUntilFirstFrameRenderedNotify = true;
                final HashMap<String, Object> data = new HashMap<>();
                data.put("id", id);
                data.put("wid", wid);
                data.put("handle", handle);
                channelReference.invokeMethod("VideoOutput.WaitUntilFirstFrameRenderedNotify", data);
            }
        }

        try {
            id = surfaceTextureEntry.id();
            Log.i("media_kit", String.format(Locale.ENGLISH, "com.alexmercerind.media_kit_video.VideoOutput: id = %d", id));
        } catch (Throwable e) {
            e.printStackTrace();
        }
    }

    public void dispose() {
        disposed = true;
        if (frameTimeout != null) mainHandler.removeCallbacks(frameTimeout);
        if (!experiment.isEmpty()) surfaceTextureEntry.setOnFrameConsumedListener(null);
        VideoDiagnostics.record(this, "surface:dispose-output-epoch", outputEpoch);
        sourceFrames.close();
        try {
            surfaceTextureEntry.release();
        } catch (Throwable e) {
            e.printStackTrace();
        }
        try {
            surface.release();
        } catch (Throwable e) {
            e.printStackTrace();
        }
        try {
            final Handler handler = new Handler(Looper.getMainLooper());
            handler.postDelayed(() -> {
                try {
                    // Invoke DeleteGlobalRef after a voluntary delay to eliminate possibility of libmpv referencing it sometime in the near future.
                    deleteGlobalObjectRef.invoke(null, wid);
                    Log.i("media_kit", String.format(Locale.ENGLISH, "com.alexmercerind.mediakitandroidhelper.MediaKitAndroidHelper.deleteGlobalObjectRef: %d", wid));
                } catch (Throwable e) {
                    e.printStackTrace();
                }
            }, 5000);
        } catch (Throwable e) {
            e.printStackTrace();
        }
    }

    public long createSurface() {
        VideoDiagnostics.record(this, "surface:create-start", 0);
        VideoDiagnostics.record(this, "surface:epoch", ++surfaceEpoch);
        synchronized (lock) {
            // Delete previous android.view.Surface & object reference.
            try {
                if (surface != null) {
                    // This runs on the plugin's main thread. lockCanvas on a
                    // decoder-owned Surface can stall the whole route. Keep
                    // the last pixels until replacement frames arrive; Dart
                    // retains the old page and gates the new source's pixels.
                    VideoDiagnostics.record(this, "surface:release", 0);
                    surface.release();
                    surface = null;
                }
                if (wid != 0) {
                    deleteGlobalObjectRef.invoke(null, wid);
                    wid = 0;
                }
            } catch (Throwable e) {
                e.printStackTrace();
            }
            // Create new android.view.Surface & object reference.
            try {
                surface = new Surface(surfaceTextureEntry.surfaceTexture());
                wid = (long) newGlobalObjectRef.invoke(null, surface);
            } catch (Throwable e) {
                e.printStackTrace();
            }
            VideoDiagnostics.record(this, "surface:create-end", 0);
            return wid;
        }
    }

    public void setSurfaceTextureSize(int width, int height) {
        try {
            VideoDiagnostics.record(this, "surface:width", width);
            VideoDiagnostics.record(this, "surface:height", height);
            outputWidth = width;
            outputHeight = height;
            surfaceTextureEntry.surfaceTexture().setDefaultBufferSize(width, height);
        } catch (Throwable e) {
            e.printStackTrace();
        }
    }

    private void clearSurface() {
        try {
            final Canvas canvas = surface.lockCanvas(null);
            canvas.drawColor(Color.TRANSPARENT, PorterDuff.Mode.CLEAR);
            surface.unlockCanvasAndPost(canvas);
        } catch (Throwable e) {
            e.printStackTrace();
        }
    }

    private FlutterJNI getFlutterJNIReference() {
        try {
            FlutterView view = null;
            // io.flutter.embedding.android.FlutterActivity
            if (view == null) {
                view = MediaKitVideoPlugin.activity.findViewById(FlutterActivity.FLUTTER_VIEW_ID);
            }
            // io.flutter.embedding.android.FlutterFragmentActivity
            if (view == null) {
                final FrameLayout layout = (FrameLayout) MediaKitVideoPlugin.activity.findViewById(FlutterFragmentActivity.FRAGMENT_CONTAINER_ID);
                for (int i = 0; i < layout.getChildCount(); i++) {
                    final View child = layout.getChildAt(i);
                    if (child instanceof FlutterView) {
                        view = (FlutterView) child;
                        break;
                    }
                }
            }
            final FlutterEngine engine = view.getAttachedFlutterEngine();
            final Field field = engine.getClass().getDeclaredField("flutterJNI");
            field.setAccessible(true);
            return (FlutterJNI) field.get(engine);
        } catch (Throwable e) {
            e.printStackTrace();
            return null;
        }
    }
}
