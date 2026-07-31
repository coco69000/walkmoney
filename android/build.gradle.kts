buildscript {
    val kotlinVersion = "2.2.20"

    repositories {
        google()
        mavenCentral()
    }
    dependencies {
        // Utilise la version stable si disponible, sinon garde la RC
        classpath("com.android.tools.build:gradle:8.11.1")
        classpath("org.jetbrains.kotlin:kotlin-gradle-plugin:$kotlinVersion")
    }

}

allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

// Configuration de votre répertoire de build personnalisé
val newBuildDir: Directory = rootProject.layout.buildDirectory.dir("../../build").get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}

subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}