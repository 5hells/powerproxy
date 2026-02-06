package cc.hellings.ps

import android.content.ComponentName
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import androidx.wear.watchface.complications.datasource.ComplicationDataSourceUpdateRequester

class MainActivity : FlutterActivity() {
    private val CHANNEL = "cc.hellings.ps/complication"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        android.util.Log.d("MainActivity", "configureFlutterEngine called")
        
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            android.util.Log.d("MainActivity", "Method call received: ${call.method}")
            if (call.method == "requestUpdate") {
                android.util.Log.d("MainActivity", "requestUpdate called")
                try {
                    val requester = ComplicationDataSourceUpdateRequester.create(
                        this,
                        ComponentName(this, CurrentClassDataSourceService::class.java)
                    )
                    requester.requestUpdateAll()
                    android.util.Log.d("MainActivity", "Complication update requested")
                    result.success(true)
                } catch (e: Exception) {
                    android.util.Log.e("MainActivity", "Failed to update complication", e)
                    result.error("UPDATE_FAILED", "Failed to update complication", e.message)
                }
            } else {
                result.notImplemented()
            }
        }
    }
}
