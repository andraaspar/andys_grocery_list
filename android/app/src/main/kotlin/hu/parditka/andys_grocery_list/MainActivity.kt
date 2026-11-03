package hu.parditka.andys_grocery_list

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.provider.DocumentsContract
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executors

/**
 * Storage Access Framework channel (plan §8).
 *
 * File IO runs on a background thread; results are posted back to the main
 * thread, as MethodChannel requires.
 */
class MainActivity : FlutterActivity() {
    private val io = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())
    private var pendingPick: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler(::onMethodCall)
    }

    override fun onDestroy() {
        io.shutdown()
        super.onDestroy()
    }

    private fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "openDocument" -> pick(result, REQUEST_OPEN) {
                Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                    addCategory(Intent.CATEGORY_OPENABLE)
                    type = "*/*"
                    // Providers disagree on the type of .md files.
                    putExtra(Intent.EXTRA_MIME_TYPES, OPEN_MIME_TYPES)
                }
            }

            "createDocument" -> pick(result, REQUEST_CREATE) {
                Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
                    addCategory(Intent.CATEGORY_OPENABLE)
                    type = "text/markdown"
                    putExtra(Intent.EXTRA_TITLE, call.argument<String>("name") ?: "todo.md")
                }
            }

            "hasPermission" -> {
                val uri = Uri.parse(call.argument<String>("uri"))
                result.success(contentResolver.persistedUriPermissions.any {
                    it.uri == uri && it.isReadPermission && it.isWritePermission
                })
            }

            "read" -> background(result) {
                val uri = Uri.parse(call.argument<String>("uri"))
                contentResolver.openInputStream(uri)?.use {
                    it.readBytes().toString(Charsets.UTF_8)
                } ?: throw IllegalStateException("Cannot open $uri")
            }

            "write" -> background(result) {
                val uri = Uri.parse(call.argument<String>("uri"))
                val content = call.argument<String>("content") ?: ""
                // "w" does not truncate on some providers.
                contentResolver.openOutputStream(uri, "wt")?.use {
                    it.write(content.toByteArray(Charsets.UTF_8))
                } ?: throw IllegalStateException("Cannot open $uri")
                null
            }

            "lastModified" -> background(result) {
                val uri = Uri.parse(call.argument<String>("uri"))
                contentResolver.query(
                    uri,
                    arrayOf(DocumentsContract.Document.COLUMN_LAST_MODIFIED),
                    null,
                    null,
                    null,
                )?.use { c ->
                    if (c.moveToFirst() && !c.isNull(0)) c.getLong(0) else null
                }
            }

            else -> result.notImplemented()
        }
    }

    private fun pick(result: MethodChannel.Result, requestCode: Int, intent: () -> Intent) {
        if (pendingPick != null) {
            result.error("busy", "A file picker is already open", null)
            return
        }
        pendingPick = result
        try {
            @Suppress("DEPRECATION")
            startActivityForResult(intent(), requestCode)
        } catch (e: Exception) {
            pendingPick = null
            result.error("unavailable", e.message, null)
        }
    }

    @Deprecated("Deprecated in Java")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (requestCode != REQUEST_OPEN && requestCode != REQUEST_CREATE) {
            @Suppress("DEPRECATION")
            super.onActivityResult(requestCode, resultCode, data)
            return
        }
        val result = pendingPick ?: return
        pendingPick = null
        val uri = data?.data
        if (resultCode != Activity.RESULT_OK || uri == null) {
            result.success(null)
            return
        }
        try {
            contentResolver.takePersistableUriPermission(
                uri,
                Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION,
            )
            result.success(uri.toString())
        } catch (e: SecurityException) {
            result.error("permission", e.message, null)
        }
    }

    private fun background(result: MethodChannel.Result, work: () -> Any?) {
        io.execute {
            try {
                val value = work()
                main.post { result.success(value) }
            } catch (e: SecurityException) {
                main.post { result.error("permission", e.message, null) }
            } catch (e: Exception) {
                main.post { result.error("io", e.message, null) }
            }
        }
    }

    companion object {
        private const val CHANNEL = "hu.parditka.andys_grocery_list/saf"
        private const val REQUEST_OPEN = 7101
        private const val REQUEST_CREATE = 7102
        private val OPEN_MIME_TYPES = arrayOf(
            "text/markdown",
            "text/x-markdown",
            "text/plain",
            "text/*",
            "application/octet-stream",
        )
    }
}
