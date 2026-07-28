package com.parrel.walkmoney

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.util.Log
import android.view.View
import android.widget.RemoteViews
import org.json.JSONArray
import org.json.JSONObject

class FavoriteRoutesWidgetProvider : AppWidgetProvider() {

    override fun onUpdate(context: Context, appWidgetManager: AppWidgetManager, appWidgetIds: IntArray) {
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

    override fun onReceive(context: Context, intent: Intent) {
        super.onReceive(context, intent)
        // Permet de forcer la mise à jour si l'app envoie un broadcast
        if (intent.action == "com.parrel.walkmoney.UPDATE_WIDGET") {
            val appWidgetManager = AppWidgetManager.getInstance(context)
            val ids = appWidgetManager.getAppWidgetIds(ComponentName(context, FavoriteRoutesWidgetProvider::class.java))
            for (id in ids) {
                updateAppWidget(context, appWidgetManager, id)
            }
        }
    }

    companion object {
        // IDs des éléments du layout XML
        private val ROW_IDS = intArrayOf(R.id.route_row_1, R.id.route_row_2, R.id.route_row_3)
        private val NAME_IDS = intArrayOf(R.id.route_name_1, R.id.route_name_2, R.id.route_name_3)
        private val DEST_IDS = intArrayOf(R.id.route_dest_1, R.id.route_dest_2, R.id.route_dest_3)
        private val ICON_IDS = intArrayOf(R.id.route_icon_1, R.id.route_icon_2, R.id.route_icon_3)

        // IDs des boutons de transport par ligne (pour le clic direct)
        private val WALK_BTN_IDS = intArrayOf(R.id.transport_walk_1, R.id.transport_walk_2, R.id.transport_walk_3)
        private val BIKE_BTN_IDS = intArrayOf(R.id.transport_bike_1, R.id.transport_bike_2, R.id.transport_bike_3)
        private val TRANSIT_BTN_IDS = intArrayOf(R.id.transport_transit_1, R.id.transport_transit_2, R.id.transport_transit_3)

        internal fun updateAppWidget(context: Context, appWidgetManager: AppWidgetManager, appWidgetId: Int) {
            val views = RemoteViews(context.packageName, R.layout.favorite_routes_widget)
            val favoriteRoutes = getFavoriteRoutes(context)
            val count = minOf(favoriteRoutes.length(), 3)

            if (count == 0) {
                views.setViewVisibility(ROW_IDS[0], View.VISIBLE)
                views.setTextViewText(NAME_IDS[0], "Aucun trajet favori")
                views.setTextViewText(DEST_IDS[0], "Ajoutez-en dans l'app")
                
                // Clic par défaut sur toute la ligne pour ouvrir l'app
                val openIntent = Intent(context, MainActivity::class.java).apply {
                    flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
                }
                views.setOnClickPendingIntent(ROW_IDS[0], PendingIntent.getActivity(
                    context, 0, openIntent, PendingIntent.FLAG_IMMUTABLE
                ))

                views.setViewVisibility(ROW_IDS[1], View.GONE)
                views.setViewVisibility(ROW_IDS[2], View.GONE)
            } else {
                for (i in 0 until 3) {
                    if (i < count) {
                        try {
                            val route = favoriteRoutes.getJSONObject(i)
                            val name = route.optString("name", "Trajet ${i+1}")
                            val address = route.optString("address", route.optString("destination", "Destination"))
                            
                            views.setViewVisibility(ROW_IDS[i], View.VISIBLE)
                            views.setTextViewText(NAME_IDS[i], name)
                            views.setTextViewText(DEST_IDS[i], address)

                            // Configurer les 3 modes de transport pour ce trajet précis
                            setupTransportButton(context, views, route, "walk", WALK_BTN_IDS[i], i)
                            setupTransportButton(context, views, route, "bike", BIKE_BTN_IDS[i], i)
                            setupTransportButton(context, views, route, "transit", TRANSIT_BTN_IDS[i], i)

                        } catch (e: Exception) {
                            Log.e("WalkMoneyWidget", "Erreur JSON trajet $i: ${e.message}")
                        }
                    } else {
                        views.setViewVisibility(ROW_IDS[i], View.GONE)
                    }
                }
            }

            appWidgetManager.updateAppWidget(appWidgetId, views)
        }

        private fun setupTransportButton(context: Context, views: RemoteViews, route: JSONObject, mode: String, viewId: Int, index: Int) {
        val intent = Intent(context, MainActivity::class.java).apply {
            action = "START_FAVORITE_ROUTE"
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
            putExtra("travel_mode", mode)
            
            // CORRECTION : Ajouter 0.0 comme valeur par défaut au lieu de laisser optDouble renvoyer NaN
            putExtra("lat", route.optDouble("lat", 0.0))
            putExtra("lng", route.optDouble("lng", 0.0))
            
            putExtra("route_name", route.optString("name"))
            putExtra("route_destination", route.optString("address", route.optString("destination")))
        }

        val requestCode = index * 10 + mode.hashCode()
        
        val pendingIntent = PendingIntent.getActivity(
            context, 
            requestCode, 
            intent, 
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        views.setOnClickPendingIntent(viewId, pendingIntent)
    }

        private fun getFavoriteRoutes(context: Context): JSONArray {
            return try {
                val prefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
                // On cherche d'abord la clé Flutter, sinon les clés alternatives
                val json = prefs.getString("flutter.favorite_trips_data", null)
                        ?: prefs.getString("flutter.favorite_routes", null)
                        ?: "[]"
                JSONArray(json)
            } catch (e: Exception) {
                JSONArray()
            }
        }
    }
}