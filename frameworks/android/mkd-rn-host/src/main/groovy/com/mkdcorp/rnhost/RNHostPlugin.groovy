package com.mkdcorp.rnhost

import org.gradle.api.Plugin
import org.gradle.api.Project

class RNHostPlugin implements Plugin<Project> {
    @Override
    void apply(Project project) {
        project.android.packagingOptions {
            pickFirst '**/*.so'
        }

        project.dependencies {
            implementation "com.facebook.react:react-android:0.81.5"
            implementation "com.facebook.react:hermes-android:0.81.5"
            implementation "com.facebook.fbjni:fbjni:0.7.0"
            implementation "com.facebook.soloader:soloader:0.12.1"
            implementation "com.facebook.infer.annotation:infer-annotation:0.18.0"
            implementation "com.facebook.fresco:fresco:3.1.3"
            implementation "com.facebook.fresco:imagepipeline-okhttp3:3.1.3"
            implementation "com.squareup.okhttp3:okhttp:4.12.0"
            implementation "com.squareup.okio:okio:3.6.0"
        }
    }
}
