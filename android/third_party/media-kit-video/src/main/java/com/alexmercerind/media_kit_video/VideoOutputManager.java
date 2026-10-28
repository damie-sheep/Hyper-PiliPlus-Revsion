/**
 * This file is a part of media_kit (https://github.com/media-kit/media-kit).
 * <p>
 * Copyright © 2021 & onwards, Hitesh Kumar Saini <saini123hitesh@gmail.com>.
 * All rights reserved.
 * Use of this source code is governed by MIT license that can be found in the LICENSE file.
 */
package com.alexmercerind.media_kit_video;

import android.util.Log;

import java.util.HashMap;
import java.util.Locale;
import java.util.Objects;

import io.flutter.plugin.common.MethodChannel;
import io.flutter.view.TextureRegistry;

public class VideoOutputManager {
    private final HashMap<Long, VideoOutput> videoOutputs = new HashMap<>();
    private final MethodChannel channelReference;
    private final TextureRegistry textureRegistryReference;
    private final Object lock = new Object();
    private String experiment = "";

    public HashMap<String, Object> configureExperiment(String variant) {
        synchronized (lock) {
            if (!("X0".equals(variant) || "X1".equals(variant) ||
                    "X2".equals(variant) || "X3".equals(variant))) {
                throw new IllegalArgumentException("Unknown stage A experiment");
            }
            if (!videoOutputs.isEmpty() && !experiment.equals(variant)) {
                throw new IllegalStateException("Configure experiment before output creation");
            }
            experiment = variant;
            final HashMap<String, Object> result = new HashMap<>();
            result.put("version", 2);
            result.put("variant", variant);
            result.put("defaultListener", "X2".equals(variant) || "X3".equals(variant));
            result.put("sourceIdentityProven", false);
            return result;
        }
    }

    VideoOutputManager(MethodChannel channelReference, TextureRegistry textureRegistryReference) {
        this.channelReference = channelReference;
        this.textureRegistryReference = textureRegistryReference;
    }

    public VideoOutput create(long handle) {
        synchronized (lock) {
            Log.i("media_kit", String.format(Locale.ENGLISH, "com.alexmercerind.media_kit_video.VideoOutputManager.create: %d", handle));
            if (!videoOutputs.containsKey(handle)) {
                final VideoOutput videoOutput = new VideoOutput(handle, channelReference, textureRegistryReference, experiment);
                videoOutputs.put(handle, videoOutput);
            }
            return videoOutputs.get(handle);
        }
    }

    public VideoOutput find(long handle) {
        synchronized (lock) {
            return videoOutputs.get(handle);
        }
    }

    public void dispose(long handle) {
        synchronized (lock) {
            Log.i("media_kit", String.format(Locale.ENGLISH, "com.alexmercerind.media_kit_video.VideoOutputManager.dispose: %d", handle));
            if (videoOutputs.containsKey(handle)) {
                Objects.requireNonNull(videoOutputs.get(handle)).dispose();
                videoOutputs.remove(handle);
            }
        }
    }

    public long createSurface(long handle) {
        synchronized (lock) {
            Log.i("media_kit", String.format(Locale.ENGLISH, "com.alexmercerind.media_kit_video.VideoOutputManager.createSurface: %d", handle));
            if (videoOutputs.containsKey(handle)) {
                return Objects.requireNonNull(videoOutputs.get(handle)).createSurface();
            }
            return 0;
        }
    }

    public void setSurfaceTextureSize(long handle, int width, int height) {
        synchronized (lock) {
            Log.i("media_kit", String.format(Locale.ENGLISH, "com.alexmercerind.media_kit_video.VideoOutputManager.setSurfaceTextureSize: %d %d %d", handle, width, height));
            if (videoOutputs.containsKey(handle)) {
                Objects.requireNonNull(videoOutputs.get(handle)).setSurfaceTextureSize(width, height);
            }
        }
    }
}
