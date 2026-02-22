package com.parrel.walkmoney

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.content.Intent
import android.util.Log
import android.view.View
import android.widget.RemoteViews
import org.json.JSONArray
import org.json.JSONObject

class FavoriteRoutesWidgetProvider : AppWidgetProvider() {

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray
    ) {
        Log.d("WalkMoneyWidget", "onUpdate appelé pour ${appWidgetIds.size} widget(s)")
        for (appWidgetId in appWidgetIds) {
            updateAppWidget(context, appWidgetManager, appWidgetId)
        }
    }

    override fun onEnabled(context: Context) {
        Log.d("WalkMoneyWidget", "Premier widget ajouté")
    }

    override fun onDisabled(context: Context) {
        Log.d("WalkMoneyWidget", "Dernier widget supprimé")
    }

    companion object {

        // IDs des lignes statiques dans le layout
        private val ROW_IDS = intArrayOf(R.id.route_row_1, R.id.route_row_2, R.id.route_row_3)
        private val NAME_IDS = intArrayOf(R.id.route_name_1, R.id.route_name_2, R.id.route_name_3)
        private val DEST_IDS = intArrayOf(R.id.route_dest_1, R.id.route_dest_2, R.id.route_dest_3)
        private val ICON_IDS = intArrayOf(R.id.route_icon_1, R.id.route_icon_2, R.id.route_icon_3)

        internal fun updateAppWidget(
            context: Context,
            appWidgetManager: AppWidgetManager,
            appWidgetId: Int
        ) {
            Log.d("WalkMoneyWidget", "Mise à jour widget ID=$appWidgetId")

            val favoriteRoutes = getFavoriteRoutes(context)
            val count = minOf(favoriteRoutes.length(), 3)
            Log.d("WalkMoneyWidget", "Nombre de trajets favoris: $count")

            val views = RemoteViews(context.packageName, R.layout.favorite_routes_widget)

            // Intent pour ouvrir l'app (fallback)
            val openIntent = Intent(context, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
            }
            val openPendingIntent = PendingIntent.getActivity(
                context, 0, openIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )

            if (count == 0) {
                // Afficher la ligne 1 avec message vide
                views.setViewVisibility(ROW_IDS[0], View.VISIBLE)
                views.setTextViewText(NAME_IDS[0], "Aucun trajet favori")
                views.setTextViewText(DEST_IDS[0], "Ajoutez des favoris dans l'app")
                views.setImageViewResource(ICON_IDS[0], R.drawable.ic_directions_walk)
                views.setOnClickPendingIntent(ROW_IDS[0], openPendingIntent)
                // Cacher les autres lignes
                views.setViewVisibility(ROW_IDS[1], View.GONE)
                views.setViewVisibility(ROW_IDS[2], View.GONE)
            } else {
                for (i in 0 until 3) {
                    if (i < count) {
                        try {
                            val route = favoriteRoutes.getJSONObject(i)
                            val routeName = route.optString("name", "Trajet ${i+1}")
                            val destination = route.optString("destination", "Destination inconnue")
                            val travelMode = route.optString("travelMode", route.optString("travel_mode", "walk"))

                            views.setViewVisibility(ROW_IDS[i], View.VISIBLE)
                            views.setTextViewText(NAME_IDS[i], routeName)
                            views.setTextViewText(DEST_IDS[i], "→ $destination")

                            val iconRes = when (travelMode) {
                                "bike" -> R.drawable.ic_directions_bike
                                "transit" -> R.drawable.ic_directions_bus
                                else -> R.drawable.ic_directions_walk
                            }
                            views.setImageViewResource(ICON_IDS[i], iconRes)

                            val intent = Intent(context, MainActivity::class.java).apply {
                                action = "SHOW_ROUTE_OPTIONS"
                                putExtra("route_index", i)
                                putExtra("route_name", routeName)
                                putExtra("route_destination", destination)
                                putExtra("travel_mode", travelMode)
                                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
                            }
                            val pendingIntent = PendingIntent.getActivity(
                                context,
                                i * 10 + 100,
                                intent,
                                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
                            )
                            views.setOnClickPendingIntent(ROW_IDS[i], pendingIntent)
                        } catch (e: Exception) {
                            Log.e("WalkMoneyWidget", "Erreur trajet $i: ${e.message}")
                            views.setViewVisibility(ROW_IDS[i], View.GONE)
                        }
                    } else {
                        views.setViewVisibility(ROW_IDS[i], View.GONE)
                    }
                }
            }

            appWidgetManager.updateAppWidget(appWidgetId, views)
            Log.d("WalkMoneyWidget", "Widget $appWidgetId mis à jour avec succès")
        }

        private fun getFavoriteRoutes(context: Context): JSONArray {
            return try {
                val prefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
                val routesJson = prefs.getString("flutter.favorite_routes", null)
                    ?: prefs.getString("flutter.walkmoney_favorite_routes", null)
                    ?: run {
                        val legacyPrefs = context.getSharedPreferences("walkmoney_prefs", Context.MODE_PRIVATE)
                        legacyPrefs.getString("favorite_routes", null)
                    }
                    ?: "[]"
                Log.d("WalkMoneyWidget", "Routes JSON: $routesJson")
                JSONArray(routesJson)
            } catch (e: Exception) {
                Log.e("WalkMoneyWidget", "Erreur lecture trajets: ${e.message}")
                JSONArray()
            }
        }
    }
}
