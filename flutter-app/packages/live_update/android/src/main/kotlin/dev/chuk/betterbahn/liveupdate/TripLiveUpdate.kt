package dev.chuk.betterbahn.liveupdate

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.os.Build
import android.util.Log
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.graphics.drawable.IconCompat

/**
 * The running trip as a **Live Update** — the promoted ongoing notification
 * Android 16 shows as a status-bar chip and keeps expanded on the lock screen,
 * the same treatment navigation and rideshare apps get.
 *
 * Why native: `flutter_local_notifications` cannot build one. It owns its
 * `NotificationCompat.Builder` and exposes neither `setStyle` nor the extras, so
 * `ProgressStyle` and the promotion request are out of reach (upstream #2773,
 * open). Everything else in the app keeps using the plugin; this is the one
 * notification that has to be built here.
 *
 * Three tiers, one code path:
 *  - **Android 17+** — `MetricStyle` (delay / next stop / arrival) with semantic
 *    colouring, reached by reflection from [Api37] because compileSdk stays 36.
 *  - **Android 16 (QPR1)** — `ProgressStyle`: the bar *is* the journey, one
 *    segment per leg, its length the planned minutes, a point at every change,
 *    promoted to a chip.
 *  - **below 16** — `NotificationCompat.ProgressStyle` degrades to a plain
 *    `setProgress` bar and the promotion request is an extra nobody reads. The
 *    Dart side keeps posting its ordinary event notifications regardless.
 */
object TripLiveUpdate {

    private const val TAG = "TripLiveUpdate"
    private const val CHANNEL_ID = "trip_live_update"

    /** Outside the ranges [NotificationService] uses (1001 / 2000-3999 / 100000+). */
    const val NOTIFICATION_ID = 7801

    /** Action fired when the rider swipes the Live Update away. */
    const val ACTION_DISMISSED = "dev.chuk.betterbahn.LIVE_UPDATE_DISMISSED"

    /** Android 16.0 — the release the ProgressStyle/promotion APIs shipped in. */
    private const val SDK_LIVE_UPDATES = 36

    /**
     * A `when` closer than this is not worth a countdown: the system drops an
     * update whose `when` has already passed, so a train that is late past its
     * own arrival time has to fall back to no countdown rather than a stale one.
     */
    private const val MIN_COUNTDOWN_MS = 60_000L

    /** One leg of the journey, as one segment of the bar. */
    data class Segment(val minutes: Int, val color: Int)

    /** Which `Notification.Metric.*` value class a [Metric] maps to on API 37. */
    enum class MetricKind { COUNT, TEXT, CLOCK }

    /**
     * One of the (at most three) figures the Android 17 template shows.
     * [number] is the value for [MetricKind.COUNT] and the minute of the day for
     * [MetricKind.CLOCK]; [text] is the value for [MetricKind.TEXT].
     */
    data class Metric(
        val label: String,
        val kind: MetricKind,
        val number: Int = 0,
        val text: String? = null,
        val unit: String? = null,
        val semanticStyle: Int = SemanticStyle.UNSPECIFIED,
    )

    /** Which template to build. [AUTO] takes the richest one the device has. */
    enum class StyleMode { AUTO, PROGRESS, METRIC }

    data class Spec(
        val title: String,
        val text: String,
        val chipText: String? = null,
        val subText: String? = null,
        val segments: List<Segment> = emptyList(),
        val transferPoints: List<Int> = emptyList(),
        val transferColor: Int = 0xFFF29D38.toInt(),
        val progressMinutes: Int = 0,
        val etaEpochMillis: Long? = null,
        val smallIconRes: Int = android.R.drawable.stat_notify_chat,
        val contentIntent: PendingIntent? = null,
        val deleteIntent: PendingIntent? = null,
        val metrics: List<Metric> = emptyList(),
        /** Index into [metrics] of the one the system may show alone, or -1. */
        val criticalMetric: Int = -1,
        val titleSemantic: Int = SemanticStyle.UNSPECIFIED,
        val style: StyleMode = StyleMode.AUTO,
    )

    /** [style] is the template actually built: `metric` or `progress`. */
    data class Built(val notification: Notification, val style: String)

    data class Posted(val promoted: Boolean, val style: String)

    fun ensureChannel(context: Context) {
        // NotificationChannel is API 26 and the plugin's minSdk is 24; loading
        // the class on 24/25 is a NoClassDefFoundError, not a silent no-op.
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = context.getSystemService(NotificationManager::class.java) ?: return
        // Never IMPORTANCE_MIN: the system refuses to promote a notification on
        // a min-importance channel, and it would fail silently.
        val channel = NotificationChannel(
            CHANNEL_ID,
            "Laufende Reise",
            NotificationManager.IMPORTANCE_DEFAULT,
        ).apply {
            description = "Live-Status der laufenden Reise (Verspätung, Umstieg, Ankunft)"
            setShowBadge(false)
        }
        manager.createNotificationChannel(channel)
    }

    /**
     * Whether this device will actually promote our notification.
     *
     * Deliberately not `SDK_INT >= 36` alone: the APIs shipped in Android 16.0
     * but the system UI only arrived with 16 QPR1, and the rider can switch the
     * promotion off per app. Both have to hold, or we are building a Live Update
     * that renders as an ordinary notification and the caller should just use the
     * ordinary one.
     */
    fun isSupported(context: Context): Boolean {
        if (Build.VERSION.SDK_INT < SDK_LIVE_UPDATES) return false
        return try {
            NotificationManagerCompat.from(context).canPostPromotedNotifications()
        } catch (e: Throwable) {
            Log.w(TAG, "canPostPromotedNotifications failed: $e")
            false
        }
    }

    /**
     * Builds the notification without posting it — the seam the unit tests use,
     * and the only place any of this branches.
     *
     * [now] is injected for the same reason: whether the ETA becomes a countdown
     * depends on the clock, and a test must not depend on the wall clock.
     */
    fun build(context: Context, spec: Spec, now: Long = System.currentTimeMillis()): Built {
        val wantsMetric = when (spec.style) {
            StyleMode.METRIC -> true
            StyleMode.PROGRESS -> false
            StyleMode.AUTO -> Api37.available && spec.metrics.isNotEmpty()
        }
        if (wantsMetric) {
            // MetricStyle replaces the style outright, so the progress bar is not
            // built at all here — it would only be dead extras on the way out.
            val base = builder(context, spec, now, withProgressStyle = false).build()
            Api37.withMetricStyle(context, base, spec.metrics, spec.criticalMetric)
                ?.let { return Built(it, "metric") }
        }
        return Built(builder(context, spec, now, withProgressStyle = true).build(), "progress")
    }

    private fun builder(
        context: Context,
        spec: Spec,
        now: Long,
        withProgressStyle: Boolean,
    ): NotificationCompat.Builder {
        val builder = NotificationCompat.Builder(context, CHANNEL_ID)
            .setSmallIcon(spec.smallIconRes)
            .setContentTitle(Api37.annotate(spec.title, spec.titleSemantic))
            .setContentText(spec.text)
            .setOngoing(true)
        if (!spec.subText.isNullOrBlank()) builder.setSubText(spec.subText)
        builder
            .setRequestPromotedOngoing(true)
            .setOnlyAlertOnce(true)
            // Colorized *disqualifies* a notification from promotion, as would a
            // custom view — hence neither, ever. The rule is the other way round
            // in stock Android 16.0, where colorized was required and the
            // promotion request ignored; that is moot because 16.0 has no Live
            // Update surface at all and `isSupported` already fails there.
            .setColorized(false)

        if (withProgressStyle) builder.setStyle(progressStyle(context, spec))
        // Blank is not "no text": an empty chip string still claims the chip and
        // the status bar shows a stub.
        if (!spec.chipText.isNullOrBlank()) builder.setShortCriticalText(spec.chipText)
        spec.contentIntent?.let { builder.setContentIntent(it) }
        spec.deleteIntent?.let { builder.setDeleteIntent(it) }

        // A countdown only where there is one to count.
        val eta = spec.etaEpochMillis
        if (eta != null && eta > now + MIN_COUNTDOWN_MS) {
            builder.setWhen(eta)
                .setShowWhen(true)
                .setUsesChronometer(true)
                .setChronometerCountDown(true)
        } else {
            builder.setShowWhen(false)
                .setUsesChronometer(false)
                .setChronometerCountDown(false)
        }
        return builder
    }

    private fun progressStyle(context: Context, spec: Spec): NotificationCompat.ProgressStyle {
        val style = NotificationCompat.ProgressStyle()
            // The segments carry the colours (done / running / late); letting the
            // bar recolour itself by progress would overwrite exactly that.
            .setStyledByProgress(false)
            .setProgress(spec.progressMinutes.coerceAtLeast(0))
        // The little train that rides the bar at the live position — the thing
        // that tells the rider "you are HERE", not "the whole leg is behind you".
        // Without it the current leg is one flat colour and reads as done.
        try {
            style.setProgressTrackerIcon(
                IconCompat.createWithResource(context, R.drawable.ic_live_train)
            )
        } catch (e: Throwable) {
            Log.w(TAG, "tracker icon failed: $e")
        }
        for (s in spec.segments) {
            style.addProgressSegment(
                // A zero-length segment breaks the bar's arithmetic; as far as
                // the bar is concerned a leg lasts at least a minute.
                NotificationCompat.ProgressStyle.Segment(s.minutes.coerceAtLeast(1))
                    .setColor(s.color)
            )
        }
        for (p in spec.transferPoints) {
            style.addProgressPoint(
                NotificationCompat.ProgressStyle.Point(p).setColor(spec.transferColor)
            )
        }
        return style
    }

    /** Post or update the trip's Live Update. */
    fun post(context: Context, spec: Spec): Posted {
        ensureChannel(context)
        val built = build(context, spec)
        val manager = NotificationManagerCompat.from(context)
        if (!manager.areNotificationsEnabled()) {
            Log.i(TAG, "notifications disabled — nothing posted")
            return Posted(promoted = false, style = built.style)
        }
        try {
            manager.notify(NOTIFICATION_ID, built.notification)
        } catch (e: Throwable) {
            // A SecurityException here is POST_NOTIFICATIONS revoked between the
            // check and the call; the trip must not die with the notification.
            Log.w(TAG, "notify failed: $e")
            return Posted(promoted = false, style = built.style)
        }

        // Whether it really got promoted is only knowable after the fact, and it
        // is what decides if the caller still needs an ordinary notification.
        val promoted = isPromoted(context)
        Log.i(
            TAG,
            "posted style=${built.style} " +
                "(promotable=${NotificationCompat.hasPromotableCharacteristics(built.notification)}, " +
                "allowed=${isSupported(context)}, promoted=$promoted)",
        )
        return Posted(promoted = promoted, style = built.style)
    }

    /** Whether the notification we posted is actually being promoted right now. */
    fun isPromoted(context: Context): Boolean {
        if (Build.VERSION.SDK_INT < SDK_LIVE_UPDATES) return false
        val manager = context.getSystemService(NotificationManager::class.java) ?: return false
        return try {
            manager.activeNotifications
                .firstOrNull { it.id == NOTIFICATION_ID }
                ?.notification
                ?.let { (it.flags and Notification.FLAG_PROMOTED_ONGOING) != 0 }
                ?: false
        } catch (e: Throwable) {
            Log.w(TAG, "activeNotifications failed: $e")
            false
        }
    }

    fun cancel(context: Context) {
        NotificationManagerCompat.from(context).cancel(NOTIFICATION_ID)
    }
}
