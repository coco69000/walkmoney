package com.parrel.walkmoney

import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.content.Intent
import android.os.Bundle

class MainActivity: FlutterFragmentActivity() {
    private val CHANNEL = "com.parrel.walkmoney/widget"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "getWidgetData" -> {
                    result.success(getIntentData())
                }
                "updateWidget" -> {
                    // Force la mise à jour de tous les widgets actifs
                    val appWidgetManager = AppWidgetManager.getInstance(this)
                    val componentName = ComponentName(this, FavoriteRoutesWidgetProvider::class.java)
                    val appWidgetIds = appWidgetManager.getAppWidgetIds(componentName)
                    for (appWidgetId in appWidgetIds) {
                        FavoriteRoutesWidgetProvider.updateAppWidget(this, appWidgetManager, appWidgetId)
                    }
                    result.success(true)
                }
                else -> {
                    result.notImplemented()
                }
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        handleWidgetIntent(intent)
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        handleWidgetIntent(intent)
    }

    private fun handleWidgetIntent(intent: Intent?) {
        if (intent?.action == "START_FAVORITE_ROUTE") {
            // Les données sont disponibles via getIntentData()
            // Flutter récupérera ces données via le MethodChannel
        } else if (intent?.action == "SHOW_ROUTE_OPTIONS") {
            // Pour l'action SHOW_ROUTE_OPTIONS, on ouvre simplement l'app
            // L'utilisateur pourra voir ses trajets favoris et choisir le mode de transport
        }
    }

    private fun getIntentData(): Map<String, Any>? {
        val intent = getIntent()
        if (intent?.action == "START_FAVORITE_ROUTE") {
            return mapOf(
                "action" to "START_FAVORITE_ROUTE",
                "route_index" to (intent.getIntExtra("route_index", -1)),
                "route_name" to (intent.getStringExtra("route_name") ?: ""),
                "route_destination" to (intent.getStringExtra("route_destination") ?: ""),
                "travel_mode" to (intent.getStringExtra("travel_mode") ?: "walk"),
                "lat" to intent.getDoubleExtra("lat", 0.0),
                "lng" to intent.getDoubleExtra("lng", 0.0)
            )
        } else if (intent?.action == "SHOW_ROUTE_OPTIONS") {
            return mapOf(
                "action" to "SHOW_ROUTE_OPTIONS",
                "route_index" to (intent.getIntExtra("route_index", -1)),
                "route_name" to (intent.getStringExtra("route_name") ?: ""),
                "route_destination" to (intent.getStringExtra("route_destination") ?: "")
            )
        }
        return null
    }
}