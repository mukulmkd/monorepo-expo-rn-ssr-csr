package org.reactnative.facedetector;

// Auto-generated stub for optional dependency
// Detected missing class: org.reactnative.facedetector.FaceDetectorModule

import com.facebook.react.bridge.ReactContext;
import com.facebook.react.bridge.ReactApplicationContext;
import com.facebook.react.bridge.NativeModule;

public class FaceDetectorModule implements NativeModule {

    public static final int FAST_MODE = 1;
    public static final int ACCURATE_MODE = 2;
    public static final int NO_LANDMARKS = 1;
    public static final int ALL_LANDMARKS = 2;
    public static final int NO_CLASSIFICATIONS = 1;
    public static final int ALL_CLASSIFICATIONS = 2;

    public FaceDetectorModule(Object... params) {
        // Auto-generated stub constructor
    }

    public boolean isOperational() { return false; }
    public void setMode(int mode) {
        // Auto-generated stub method
    }
    public void setLandmarkType(int landmarkType) {
        // Auto-generated stub method
    }
    public void setClassificationType(int classificationType) {
        // Auto-generated stub method
    }
    public void setTracking(boolean tracking) {
        // Auto-generated stub method
    }
    public void release() {
        // Auto-generated stub method
    }

    public String getName() { return "FaceDetectorModule"; }

    public void initialize() {
        // Auto-generated stub implementation
    }

    public boolean canOverrideExistingModule() { return false; }

    public void onCatalystInstanceDestroy() {
        // Auto-generated stub implementation
    }

    public void invalidate() {
        // Auto-generated stub implementation
    }

    // Auto-generated stub for optional dependency
}
