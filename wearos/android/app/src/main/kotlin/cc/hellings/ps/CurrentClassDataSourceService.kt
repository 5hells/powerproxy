package cc.hellings.ps

import android.app.PendingIntent
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import androidx.wear.watchface.complications.data.ComplicationData
import androidx.wear.watchface.complications.data.ComplicationType
import androidx.wear.watchface.complications.data.NoDataComplicationData
import androidx.wear.watchface.complications.data.PlainComplicationText
import androidx.wear.watchface.complications.data.ShortTextComplicationData
import androidx.wear.watchface.complications.datasource.ComplicationRequest
import androidx.wear.watchface.complications.datasource.SuspendingComplicationDataSourceService

class CurrentClassDataSourceService : SuspendingComplicationDataSourceService() {

    override suspend fun onComplicationRequest(request: ComplicationRequest): ComplicationData? {
        val prefs = getSharedPreferences("current_class", Context.MODE_PRIVATE)
        val className = prefs.getString("class_name", null)
        val room = prefs.getString("room", null)

        return if (className.isNullOrEmpty()) {
            NoDataComplicationData()
        } else {
            val builder = ShortTextComplicationData.Builder(
                text = PlainComplicationText.Builder(className).build(),
                contentDescription = PlainComplicationText.Builder("$className in $room").build()
            )
            if (!room.isNullOrEmpty()) {
                builder.setTitle(PlainComplicationText.Builder(room).build())
            }

            // Tap action to open the app
            val intent = Intent().apply {
                setComponent(ComponentName(this@CurrentClassDataSourceService, MainActivity::class.java))
                flags = Intent.FLAG_ACTIVITY_NEW_TASK
            }
            val pendingIntent = PendingIntent.getActivity(
                this,
                0,
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
            builder.setTapAction(pendingIntent)

            builder.build()
        }
    }

    override fun getPreviewData(type: ComplicationType): ComplicationData? {
        return ShortTextComplicationData.Builder(
            text = PlainComplicationText.Builder("Math 101").build(),
            contentDescription = PlainComplicationText.Builder("Math 101 in Room 204").build()
        )
            .setTitle(PlainComplicationText.Builder("Room 204").build())
            .build()
    }
}