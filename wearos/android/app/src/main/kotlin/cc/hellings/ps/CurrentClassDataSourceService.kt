package cc.hellings.ps

import android.app.PendingIntent
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import androidx.wear.watchface.complications.data.ComplicationData
import androidx.wear.watchface.complications.data.ComplicationType
import androidx.wear.watchface.complications.data.NoDataComplicationData
import androidx.wear.watchface.complications.data.PlainComplicationText
import androidx.wear.watchface.complications.data.RangedValueComplicationData
import androidx.wear.watchface.complications.data.ShortTextComplicationData
import androidx.wear.watchface.complications.datasource.ComplicationRequest
import androidx.wear.watchface.complications.datasource.SuspendingComplicationDataSourceService

class CurrentClassDataSourceService : SuspendingComplicationDataSourceService() {

    override suspend fun onComplicationRequest(request: ComplicationRequest): ComplicationData? {
        val prefs = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
        val className = prefs.getString("flutter.class_name", null)
        val room = prefs.getString("flutter.room", null)
        val classEndsIn = prefs.getLong("flutter.class_ends_in", -1L).toInt()
        val classTotalDuration = prefs.getLong("flutter.class_total_duration", -1L).toInt()
        val nextClassName = prefs.getString("flutter.next_class_name", null)
        val nextClassStartsIn = prefs.getLong("flutter.next_class_starts_in", -1L).toInt()

        return if (!className.isNullOrEmpty() && !room.isNullOrEmpty() && classEndsIn >= 0 && classTotalDuration > 0) {
            // Active class with duration info - use ranged value for progress
            val remaining = classEndsIn.toFloat()
            val total = classTotalDuration.toFloat()
            
            RangedValueComplicationData.Builder(
                value = remaining,
                min = 0f,
                max = total,
                contentDescription = PlainComplicationText.Builder("$className in $room").build()
            )
                .setText(PlainComplicationText.Builder(room).build())
                .setTitle(PlainComplicationText.Builder(className).build())
                .setTapAction(createTapIntent())
                .build()
        } else if (!className.isNullOrEmpty()) {
            // Active class - show end time
            val builder = ShortTextComplicationData.Builder(
                text = PlainComplicationText.Builder(className).build(),
                contentDescription = PlainComplicationText.Builder("$className ($room)").build()
            )
            
            if (classEndsIn >= 0) {
                val endText = if (classEndsIn == 0) "now" else "${classEndsIn}m"
                builder.setTitle(PlainComplicationText.Builder(endText).build())
            } else if (!room.isNullOrEmpty()) {
                builder.setTitle(PlainComplicationText.Builder(room).build())
            }

            builder.setTapAction(createTapIntent())
            builder.build()
        } else if (!nextClassName.isNullOrEmpty()) {
            // No active class - show next class
            val builder = ShortTextComplicationData.Builder(
                text = PlainComplicationText.Builder(nextClassName).build(),
                contentDescription = PlainComplicationText.Builder(nextClassName).build()
            )
            
            if (nextClassStartsIn >= 0) {
                val startText = if (nextClassStartsIn == 0) "now" else "${nextClassStartsIn}m"
                builder.setTitle(PlainComplicationText.Builder(startText).build())
            }

            builder.setTapAction(createTapIntent())
            builder.build()
        } else {
            NoDataComplicationData()
        }
    }

    private fun createTapIntent(): PendingIntent {
        val intent = Intent().apply {
            setComponent(ComponentName(this@CurrentClassDataSourceService, MainActivity::class.java))
            flags = Intent.FLAG_ACTIVITY_NEW_TASK
        }
        return PendingIntent.getActivity(
            this,
            0,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
    }

    override fun getPreviewData(type: ComplicationType): ComplicationData? {
        return when (type) {
            ComplicationType.RANGED_VALUE -> {
                RangedValueComplicationData.Builder(
                    value = 30f,
                    min = 0f,
                    max = 60f,
                    contentDescription = PlainComplicationText.Builder("Math 101 in Room 204").build()
                )
                    .setText(PlainComplicationText.Builder("204").build())
                    .setTitle(PlainComplicationText.Builder("Math 101").build())
                    .build()
            }
            ComplicationType.SHORT_TEXT -> {
                ShortTextComplicationData.Builder(
                    text = PlainComplicationText.Builder("Math 101").build(),
                    contentDescription = PlainComplicationText.Builder("Math 101 in Room 204").build()
                )
                    .setTitle(PlainComplicationText.Builder("Room 204").build())
                    .build()
            }
            else -> null
        }
    }
}