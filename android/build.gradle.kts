import org.jetbrains.kotlin.gradle.tasks.KotlinCompile

allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}

// AGP 9's legacy Kotlin mode does not automatically create the Kotlin Android
// extension. Several Flutter plugins configure that extension in their own
// build scripts, so apply the compatibility plugin before those scripts run.
subprojects {
    if (providers.gradleProperty("android.builtInKotlin").orNull == "false") {
        plugins.withId("com.android.application") {
            pluginManager.apply("org.jetbrains.kotlin.android")
        }
        plugins.withId("com.android.library") {
            pluginManager.apply("org.jetbrains.kotlin.android")
        }
    }
}

subprojects {
    afterEvaluate {
        if (project.extensions.findByName("android") != null) {
            val androidExtension =
                project.extensions.getByName("android") as com.android.build.gradle.BaseExtension

            if (androidExtension.namespace == null) {
                androidExtension.namespace = project.group.toString()
            }

            androidExtension.compileOptions {
                sourceCompatibility = JavaVersion.VERSION_17
                targetCompatibility = JavaVersion.VERSION_17
            }

            if (project.name == "media_kit_video") {
                // Preserve Pub/SDK caches. Fail closed if the pinned plugin changes.
                val patchRoot = rootProject.file("third_party/media-kit-video")
                @Suppress("UNCHECKED_CAST")
                val manifest = groovy.json.JsonSlurper().parse(patchRoot.resolve("upstream.json")) as Map<String, Any>
                @Suppress("UNCHECKED_CAST")
                val files = manifest["files"] as Map<String, String>
                files.forEach { (path, expected) ->
                    val original = project.file(path)
                    val actual = java.security.MessageDigest.getInstance("SHA-256")
                        .digest(original.readBytes()).joinToString("") { "%02x".format(it) }
                    check(actual == expected) { "media_kit_video source changed: $path; review the repository overlay" }
                }
                androidExtension.sourceSets.getByName("main").java.setSrcDirs(
                    listOf(patchRoot.resolve("src/main/java"))
                )
            }

            project.tasks.withType<KotlinCompile>().configureEach {
                compilerOptions {
                    jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17)
                }
            }

            val pluginCompileSdkStr = androidExtension.compileSdkVersion
            val pluginCompileSdk = pluginCompileSdkStr
                ?.removePrefix("android-")
                ?.toIntOrNull()
            if (pluginCompileSdk != null && pluginCompileSdk < 36) {
                project.logger.error(
                    "Warning: Overriding compileSdk version in Flutter plugin: ${project.name} " +
                            "from $pluginCompileSdk to 36 (to work around https://issuetracker.google.com/issues/199180389).\n" +
                            "If there is not a new version of ${project.name}, consider filing an issue against ${project.name} " +
                            "to increase their compileSdk to the latest (otherwise try updating to the latest version)."
                )
                androidExtension.setCompileSdkVersion(36)
            }
        }

        project.buildDir = File(rootProject.buildDir, project.name)
    }
}

subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
