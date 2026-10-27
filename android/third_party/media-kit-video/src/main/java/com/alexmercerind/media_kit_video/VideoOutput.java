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
        sourceFrames.arm(generation, ready -> mainHandler.post(() -> {
            VideoDiagnostics.record(this, ready ? "frame:candidate" : "frame:cancel-or-timeout", generation);
            result.success(ready);
        }));
        mainHandler.postDelayed(() -> sourceFrames.cancel(generation), 3000);
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

    VideoOutput(long handle, MethodChannel channelReference, TextureRegistry textureRegistryReference) {
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
        if (flutterJNIAPIAvailable) {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
                surfaceTextureEntry.surfaceTexture().setOnFrameAvailableListener((texture) -> {
                    synchronized (lock) {
                        try {
                            if (!disposed && outputWidth > 1 && outputHeight > 1) {
                                VideoDiagnostics.record(this, "surface:frame-callback", 0);
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
