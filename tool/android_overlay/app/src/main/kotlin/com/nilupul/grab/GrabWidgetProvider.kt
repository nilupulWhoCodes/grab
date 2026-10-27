package com.nilupul.grab

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.view.KeyEvent
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetProvider
import java.io.File

/**
 * Home-screen player widget. The Flutter side writes title/artist/art/playing
 * through home_widget; the buttons send media-button events to the app's
 * audio service, the same way headphone buttons do.
 */
class GrabWidgetProvider : HomeWidgetProvider() {

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences,
    ) {
        val title = widgetData.getString("title", null) ?: "Not playing"
        val artist = widgetData.getString("artist", null) ?: "Tap to open Grab"
        val playing = widgetData.getBoolean("playing", false)
        val art = loadArt(widgetData.getString("art", null))

        for (id in appWidgetIds) {
            val views = RemoteViews(context.packageName, R.layout.grab_widget).apply {
                setTextViewText(R.id.widget_title, title)
                setTextViewText(R.id.widget_artist, artist)
                if (art != null) {
                    setImageViewBitmap(R.id.widget_art, art)
                } else {
                    setImageViewResource(R.id.widget_art, R.drawable.ic_widget_note)
                }
                setImageViewResource(
                    R.id.widget_play,
                    if (playing) R.drawable.ic_widget_pause else R.drawable.ic_widget_play,
                )
                setContentDescription(R.id.widget_play, if (playing) "Pause" else "Play")

                setOnClickPendingIntent(
                    R.id.widget_root,
                    HomeWidgetLaunchIntent.getActivity(context, MainActivity::class.java),
                )
                setOnClickPendingIntent(
                    R.id.widget_prev,
                    mediaButton(context, KeyEvent.KEYCODE_MEDIA_PREVIOUS, 101),
                )
                setOnClickPendingIntent(
                    R.id.widget_play,
                    mediaButton(context, KeyEvent.KEYCODE_MEDIA_PLAY_PAUSE, 102),
                )
                setOnClickPendingIntent(
                    R.id.widget_next,
                    mediaButton(context, KeyEvent.KEYCODE_MEDIA_NEXT, 103),
                )
            }
            appWidgetManager.updateAppWidget(id, views)
        }
    }

    private fun mediaButton(context: Context, keyCode: Int, requestCode: Int): PendingIntent {
        val intent = Intent(Intent.ACTION_MEDIA_BUTTON).apply {
            component = ComponentName(
                context,
                "com.ryanheise.audioservice.MediaButtonReceiver",
            )
            putExtra(Intent.EXTRA_KEY_EVENT, KeyEvent(KeyEvent.ACTION_DOWN, keyCode))
        }
        return PendingIntent.getBroadcast(
            context,
            requestCode,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }

    /** Decodes cover art scaled down (widgets have a small bitmap budget). */
    private fun loadArt(path: String?): Bitmap? {
        if (path.isNullOrEmpty()) return null
        val file = File(path)
        if (!file.exists()) return null
        return try {
            val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
            BitmapFactory.decodeFile(path, bounds)
            var sample = 1
            while (bounds.outWidth / (sample * 2) >= 200 && bounds.outHeight / (sample * 2) >= 200) {
                sample *= 2
            }
            val opts = BitmapFactory.Options().apply { inSampleSize = sample }
            BitmapFactory.decodeFile(path, opts)
        } catch (e: Exception) {
            null
        }
    }
}
