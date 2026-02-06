package cc.hellings.ps

import android.content.ComponentName
import android.content.SharedPreferences
import androidx.wear.watchface.complications.data.*
import androidx.wear.watchface.complications.datasource.ComplicationDataSourceService
import androidx.wear.watchface.complications.datasource.ComplicationRequest

class CurrentClassDataSourceService : ComplicationDataSourceService() {

    override fun onComplicationRequest(
        request: ComplicationRequest,
        listener: ComplicationRequestListener
    ) {
        android.util.Log.d("ComplicationService", "onComplicationRequest called for type: ${request.complicationType}")
        val prefs: SharedPreferences = getSharedPreferences("FlutterSharedPreferences", MODE_PRIVATE)
        val className = prefs.getString("flutter.class_name", null)
        val room = prefs.getString("flutter.room", null)
        val minutesRemaining = prefs.getLong("flutter.minutes_remaining", -1L).toInt()
        val totalMinutes = prefs.getLong("flutter.total_minutes", -1L).toInt()
        
        android.util.Log.d("ComplicationService", "Data - className: $className, room: $room, minutesRemaining: $minutesRemaining, totalMinutes: $totalMinutes")

        val complicationData = when (request.complicationType) {
            ComplicationType.SHORT_TEXT -> {
                if (className != null && minutesRemaining >= 0) {
                    ShortTextComplicationData.Builder(
                        text = PlainComplicationText.Builder(className).build(),
                        contentDescription = PlainComplicationText.Builder("Current class: $className").build()
                    )
                    .setTitle(PlainComplicationText.Builder("$minutesRemaining min").build())
                    .build()
                } else {
                    ShortTextComplicationData.Builder(
                        text = PlainComplicationText.Builder("--").build(),
                        contentDescription = PlainComplicationText.Builder("No class").build()
                    ).build()
                }
            }
            ComplicationType.LONG_TEXT -> {
                if (className != null && room != null && minutesRemaining >= 0) {
                    LongTextComplicationData.Builder(
                        text = PlainComplicationText.Builder("$className in $room").build(),
                        contentDescription = PlainComplicationText.Builder("$className in room $room, $minutesRemaining minutes remaining").build()
                    )
                    .setTitle(PlainComplicationText.Builder("$minutesRemaining min left").build())
                    .build()
                } else {
                    LongTextComplicationData.Builder(
                        text = PlainComplicationText.Builder("No class").build(),
                        contentDescription = PlainComplicationText.Builder("No class currently").build()
                    ).build()
                }
            }
            ComplicationType.RANGED_VALUE -> {
                if (className != null && minutesRemaining >= 0 && totalMinutes > 0) {
                    val progress = ((totalMinutes - minutesRemaining).toFloat() / totalMinutes.toFloat()) * 100f
                    RangedValueComplicationData.Builder(
                        value = progress,
                        min = 0f,
                        max = 100f,
                        contentDescription = PlainComplicationText.Builder("Class progress: ${progress.toInt()}%").build()
                    )
                    .setText(PlainComplicationText.Builder(className).build())
                    .setTitle(PlainComplicationText.Builder("$minutesRemaining min").build())
                    .build()
                } else {
                    RangedValueComplicationData.Builder(
                        value = 0f,
                        min = 0f,
                        max = 100f,
                        contentDescription = PlainComplicationText.Builder("No class").build()
                    )
                    .setText(PlainComplicationText.Builder("--").build())
                    .build()
                }
            }
            else -> {
                NoDataComplicationData()
            }
        }

        listener.onComplicationData(complicationData)
    }

    override fun getPreviewData(type: ComplicationType): ComplicationData {
        return when (type) {
            ComplicationType.SHORT_TEXT -> {
                ShortTextComplicationData.Builder(
                    text = PlainComplicationText.Builder("Math").build(),
                    contentDescription = PlainComplicationText.Builder("Current class: Math").build()
                )
                .setTitle(PlainComplicationText.Builder("25 min").build())
                .build()
            }
            ComplicationType.LONG_TEXT -> {
                LongTextComplicationData.Builder(
                    text = PlainComplicationText.Builder("Math in Room 101").build(),
                    contentDescription = PlainComplicationText.Builder("Math in room 101, 25 minutes remaining").build()
                )
                .setTitle(PlainComplicationText.Builder("25 min left").build())
                .build()
            }
            ComplicationType.RANGED_VALUE -> {
                RangedValueComplicationData.Builder(
                    value = 50f,
                    min = 0f,
                    max = 100f,
                    contentDescription = PlainComplicationText.Builder("Class progress: 50%").build()
                )
                .setText(PlainComplicationText.Builder("Math").build())
                .setTitle(PlainComplicationText.Builder("25 min").build())
                .build()
            }
            else -> {
                NoDataComplicationData()
            }
        }
    }
}
