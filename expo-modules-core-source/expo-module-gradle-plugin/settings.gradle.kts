pluginManagement {
    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

dependencyResolutionManagement {
    repositoriesMode.set(RepositoriesMode.PREFER_SETTINGS)
    repositories {
        google()
        mavenCentral()
    }
}

rootProject.name = "expo-module-gradle-plugin"

// Include React Native Gradle plugin as composite build (from node_modules)
includeBuild("../../node_modules/@react-native/gradle-plugin")

