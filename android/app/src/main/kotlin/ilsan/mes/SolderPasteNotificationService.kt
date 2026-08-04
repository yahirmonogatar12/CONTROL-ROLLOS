package ilsan.mes

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.app.ServiceCompat
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.Response
import okhttp3.WebSocket
import okhttp3.WebSocketListener
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URI
import java.net.URL
import java.security.MessageDigest
import java.util.concurrent.Executors
import java.util.concurrent.ScheduledFuture
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean
import kotlin.math.min

/**
 * Mantiene un WebSocket con el backend de la LAN. El backend envía una señal
 * solo cuando cambia Control de pasta; entonces se descarga el evento usando
 * el cursor local. No requiere Firebase ni Internet.
 */
class SolderPasteNotificationService : Service() {
    companion object {
        const val ACTION_CONFIGURE = "ilsan.mes.action.CONFIGURE_SOLDER_PASTE_NOTIFICATIONS"
        const val ACTION_STOP = "ilsan.mes.action.STOP_SOLDER_PASTE_NOTIFICATIONS"
        const val EXTRA_BASE_URL = "base_url"

        private const val PREFS = "solder_paste_local_notifications"
        private const val PREF_BASE_URL = "base_url"
        private const val MONITOR_CHANNEL = "solder_paste_local_monitor"
        private const val EVENTS_CHANNEL = "solder_paste_process"
        private const val MONITOR_NOTIFICATION_ID = 41000
        private const val SOCKET_PATH = "/ws/solder-paste"
        private const val SIGNAL_TYPE = "solder_paste_events_available"
    }

    private val executor = Executors.newSingleThreadScheduledExecutor()
    private val fetchRunning = AtomicBoolean(false)
    private val fetchRequested = AtomicBoolean(false)
    private val stopped = AtomicBoolean(false)
    private val httpClient = OkHttpClient.Builder()
        .connectTimeout(5, TimeUnit.SECONDS)
        .retryOnConnectionFailure(true)
        .build()

    @Volatile
    private var baseUrl: String = ""

    @Volatile
    private var webSocket: WebSocket? = null

    @Volatile
    private var reconnectAttempt = 0

    private var reconnectFuture: ScheduledFuture<*>? = null

    override fun onCreate() {
        super.onCreate()
        createNotificationChannels()
        baseUrl = preferences().getString(PREF_BASE_URL, "").orEmpty()
        promoteToForeground(connected = false)
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_STOP) {
            stopForeground(STOP_FOREGROUND_REMOVE)
            stopSelf()
            return START_NOT_STICKY
        }

        val configuredUrl = intent?.getStringExtra(EXTRA_BASE_URL)
            ?.trim()
            ?.trimEnd('/')
            .orEmpty()
        if (configuredUrl.isNotEmpty() && configuredUrl != baseUrl) {
            baseUrl = configuredUrl
            preferences().edit().putString(PREF_BASE_URL, baseUrl).apply()
            reconnectAttempt = 0
            reconnectFuture?.cancel(false)
            reconnectFuture = null
            webSocket?.close(1000, "Cambio de servidor")
            webSocket = null
        }

        promoteToForeground(connected = webSocket != null)
        connectWebSocket()
        return START_STICKY
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onDestroy() {
        stopped.set(true)
        reconnectFuture?.cancel(true)
        webSocket?.close(1000, "Servicio detenido")
        webSocket = null
        executor.shutdownNow()
        httpClient.dispatcher.executorService.shutdown()
        httpClient.connectionPool.evictAll()
        super.onDestroy()
    }

    private fun preferences() = getSharedPreferences(PREFS, MODE_PRIVATE)

    private fun createNotificationChannels() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = getSystemService(NotificationManager::class.java)
        manager.createNotificationChannel(
            NotificationChannel(
                MONITOR_CHANNEL,
                "Conexión local de Control de pasta",
                NotificationManager.IMPORTANCE_LOW,
            ).apply {
                description = "Mantiene activos los avisos desde el servidor de la red local"
                setSound(null, null)
            },
        )
        manager.createNotificationChannel(
            NotificationChannel(
                EVENTS_CHANNEL,
                "Control de pasta",
                NotificationManager.IMPORTANCE_HIGH,
            ).apply {
                description = "Avisos al terminar cada etapa del proceso de pasta"
            },
        )
    }

    private fun promoteToForeground(connected: Boolean) {
        val host = try {
            if (baseUrl.isBlank()) "esperando servidor" else URI(baseUrl).host ?: baseUrl
        } catch (_: Exception) {
            baseUrl
        }
        val state = if (connected) "Conectado" else "Conectando"
        val notification = NotificationCompat.Builder(this, MONITOR_CHANNEL)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle("Control de pasta local activo")
            .setContentText("$state: $host")
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setContentIntent(openAppIntent())
            .build()

        val serviceType = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            ServiceInfo.FOREGROUND_SERVICE_TYPE_REMOTE_MESSAGING
        } else {
            0
        }
        ServiceCompat.startForeground(
            this,
            MONITOR_NOTIFICATION_ID,
            notification,
            serviceType,
        )
    }

    @Synchronized
    private fun connectWebSocket() {
        if (stopped.get() || baseUrl.isBlank() || webSocket != null) return
        reconnectFuture?.cancel(false)
        reconnectFuture = null

        val request = try {
            Request.Builder().url(webSocketUrl()).build()
        } catch (_: Exception) {
            scheduleReconnect()
            return
        }

        webSocket = httpClient.newWebSocket(request, object : WebSocketListener() {
            override fun onOpen(socket: WebSocket, response: Response) {
                if (stopped.get()) {
                    socket.close(1000, "Servicio detenido")
                    return
                }
                webSocket = socket
                reconnectAttempt = 0
                promoteToForeground(connected = true)
                requestFeedFetch()
            }

            override fun onMessage(socket: WebSocket, text: String) {
                try {
                    val type = JSONObject(text).optString("type")
                    if (type == SIGNAL_TYPE || type == "connected") requestFeedFetch()
                } catch (_: Exception) {
                    // Ignorar mensajes que no pertenezcan al protocolo local.
                }
            }

            override fun onClosed(socket: WebSocket, code: Int, reason: String) {
                handleSocketClosed(socket)
            }

            override fun onFailure(socket: WebSocket, error: Throwable, response: Response?) {
                handleSocketClosed(socket)
            }
        })
    }

    @Synchronized
    private fun handleSocketClosed(socket: WebSocket) {
        if (webSocket !== socket) return
        webSocket = null
        if (stopped.get()) return
        promoteToForeground(connected = false)
        scheduleReconnect()
    }

    @Synchronized
    private fun scheduleReconnect() {
        if (stopped.get() || baseUrl.isBlank() || reconnectFuture?.isDone == false) return
        val delaySeconds = min(30L, 2L shl min(reconnectAttempt, 4))
        reconnectAttempt += 1
        reconnectFuture = executor.schedule(
            { connectWebSocket() },
            delaySeconds,
            TimeUnit.SECONDS,
        )
    }

    private fun webSocketUrl(): String {
        val uri = URI(baseUrl)
        val scheme = if (uri.scheme.equals("https", ignoreCase = true)) "wss" else "ws"
        return "$scheme://${uri.rawAuthority}$SOCKET_PATH"
    }

    private fun requestFeedFetch() {
        fetchRequested.set(true)
        if (!fetchRunning.compareAndSet(false, true)) return

        executor.execute {
            try {
                do {
                    fetchRequested.set(false)
                    try {
                        fetchFeed()
                    } catch (_: Exception) {
                        // Se recuperará el cursor al reconectar o recibir la siguiente señal.
                    }
                } while (fetchRequested.get())
            } finally {
                fetchRunning.set(false)
                if (fetchRequested.get()) requestFeedFetch()
            }
        }
    }

    private fun fetchFeed() {
        val cursorKey = "cursor_${serverKey(baseUrl)}"
        val prefs = preferences()
        val hasCursor = prefs.contains(cursorKey)
        val cursor = prefs.getLong(cursorKey, 0L)
        val endpoint = buildString {
            append(baseUrl)
            append("/solder-paste/local-notifications?limit=100")
            if (hasCursor) append("&after_id=").append(cursor)
        }

        val connection = URL(endpoint).openConnection() as HttpURLConnection
        try {
            connection.requestMethod = "GET"
            connection.connectTimeout = 3500
            connection.readTimeout = 5000
            connection.setRequestProperty("Accept", "application/json")
            if (connection.responseCode !in 200..299) return

            val response = connection.inputStream.bufferedReader().use { it.readText() }
            val root = JSONObject(response)
            if (!root.optBoolean("success", false)) return

            val events = root.optJSONArray("events")
            if (events != null) {
                for (index in 0 until events.length()) {
                    val event = events.optJSONObject(index) ?: continue
                    showEvent(event)
                    prefs.edit().putLong(cursorKey, event.optLong("id", cursor)).apply()
                }
            }

            prefs.edit().putLong(cursorKey, root.optLong("cursor", cursor)).apply()
            if (root.optBoolean("hasMore", false)) requestFeedFetch()
        } finally {
            connection.disconnect()
        }
    }

    private fun showEvent(event: JSONObject) {
        val eventId = event.optLong("id", System.currentTimeMillis())
        val notification = NotificationCompat.Builder(this, EVENTS_CHANNEL)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle(event.optString("title", "Control de pasta"))
            .setContentText(event.optString("body", "Una etapa del proceso terminó"))
            .setStyle(
                NotificationCompat.BigTextStyle().bigText(
                    event.optString("body", "Una etapa del proceso terminó"),
                ),
            )
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setAutoCancel(true)
            .setContentIntent(openAppIntent())
            .build()

        try {
            NotificationManagerCompat.from(this).notify(
                42000 + (eventId % 1_000_000L).toInt(),
                notification,
            )
        } catch (_: SecurityException) {
            // Android 13+: el usuario puede negar el permiso de notificaciones.
        }
    }

    private fun openAppIntent(): PendingIntent {
        val intent = packageManager.getLaunchIntentForPackage(packageName)?.apply {
            addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP)
        } ?: Intent(this, MainActivity::class.java)
        return PendingIntent.getActivity(
            this,
            0,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }

    private fun serverKey(value: String): String {
        val digest = MessageDigest.getInstance("SHA-256")
            .digest(value.toByteArray(Charsets.UTF_8))
        return digest.take(8).joinToString("") { "%02x".format(it) }
    }
}
