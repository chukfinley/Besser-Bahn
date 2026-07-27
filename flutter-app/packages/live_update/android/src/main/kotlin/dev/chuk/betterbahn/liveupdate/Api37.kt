package dev.chuk.betterbahn.liveupdate

import android.app.Notification
import android.content.Context
import android.os.Build
import android.text.SpannableString
import android.text.Spanned
import android.util.Log

/**
 * The Android 17 (API 37) half of the Live Update, reached by reflection.
 *
 * Reflection and not real symbols because the app module's `compileSdk` is
 * pinned to 36: IzzyOnDroid rebuilds this app from source with an exact
 * toolchain (see BUILDING.md), so a build that needs `android-37` installed
 * would break the reproducible build for a cosmetic tier. `androidx.core` has no
 * compat wrapper for `MetricStyle` either — as of 1.18 it is platform-only — so
 * there is nothing to compile against in the first place.
 *
 * Every entry point degrades: below 37, or if a signature ever moves, the caller
 * gets `null`/the untouched input back and keeps the Android 16 ProgressStyle
 * Live Update. Nothing here may throw into the notification path.
 */
internal object Api37 {

    private const val TAG = "LiveUpdate37"

    /** Android 17. Not in `Build.VERSION_CODES` at compileSdk 36. */
    const val SDK_METRIC_STYLE = 37

    private class Refs {
        val notification: Class<*> = Notification::class.java
        val metricStyle: Class<*> = Class.forName("android.app.Notification\$MetricStyle")
        val metric: Class<*> = Class.forName("android.app.Notification\$Metric")
        val metricValue: Class<*> = Class.forName("android.app.Notification\$Metric\$MetricValue")
        val fixedInt: Class<*> = Class.forName("android.app.Notification\$Metric\$FixedInt")
        val fixedText: Class<*> = Class.forName("android.app.Notification\$Metric\$FixedText")
        val fixedTime: Class<*> = Class.forName("android.app.Notification\$Metric\$FixedTime")
        val localTime: Class<*> = Class.forName("java.time.LocalTime")

        val newMetricStyle = metricStyle.getConstructor()
        val addMetric = metricStyle.getMethod("addMetric", metric)
        val setCriticalMetric = metricStyle.getMethod("setCriticalMetric", Int::class.javaPrimitiveType)
        val newMetric = metric.getConstructor(
            metricValue,
            CharSequence::class.java,
            Int::class.javaPrimitiveType,
        )
        val newFixedInt =
            fixedInt.getConstructor(Int::class.javaPrimitiveType, CharSequence::class.java)
        val newFixedText =
            fixedText.getConstructor(CharSequence::class.java, CharSequence::class.java)
        val newFixedTime = fixedTime.getConstructor(localTime)
        val localTimeOf = localTime.getMethod(
            "of",
            Int::class.javaPrimitiveType,
            Int::class.javaPrimitiveType,
        )
        val semanticAnnotation = notification.getMethod(
            "createSemanticStyleAnnotation",
            Int::class.javaPrimitiveType,
        )
    }

    /**
     * Resolved once. A failure is cached as `null` too — a device whose platform
     * does not have these classes will never grow them, and re-probing on every
     * poll would cost a `ClassNotFoundException` per minute for the whole trip.
     */
    private val refs: Refs? by lazy {
        if (Build.VERSION.SDK_INT < SDK_METRIC_STYLE) return@lazy null
        try {
            Refs()
        } catch (e: Throwable) {
            Log.w(TAG, "API 37 notification symbols missing: $e")
            null
        }
    }

    val available: Boolean get() = refs != null

    /**
     * [text] spanned so the system colours it — amber for a delay, red for a
     * cancellation.
     *
     * Returns [text] unchanged where the annotation does not exist, which is the
     * documented contract of these spans anyway: stripping the styling must
     * never change the meaning of the words.
     */
    fun annotate(text: CharSequence, semanticStyle: Int): CharSequence {
        if (text.isEmpty() || semanticStyle == SemanticStyle.UNSPECIFIED) return text
        if (!SemanticStyle.isValid(semanticStyle)) return text
        val r = refs ?: return text
        return try {
            val annotation = r.semanticAnnotation.invoke(null, semanticStyle) ?: return text
            SpannableString(text).apply {
                setSpan(annotation, 0, text.length, Spanned.SPAN_INCLUSIVE_EXCLUSIVE)
            }
        } catch (e: Throwable) {
            Log.w(TAG, "semantic annotation failed: $e")
            text
        }
    }

    /**
     * Re-styles an already built [notification] as a `MetricStyle` — the
     * template Android 17 added for exactly this shape of Live Update (travel,
     * timers), showing up to three figures on the always-on display.
     *
     * Goes through `Notification.Builder.recoverBuilder` (API 24+) so everything
     * `NotificationCompat` put together — extras, promotion request, intents,
     * chronometer — is kept and only the style is swapped. Returns `null` when
     * the swap is not possible, and the caller falls back to ProgressStyle.
     */
    fun withMetricStyle(
        context: Context,
        notification: Notification,
        metrics: List<TripLiveUpdate.Metric>,
        criticalMetric: Int,
    ): Notification? {
        val r = refs ?: return null
        if (metrics.isEmpty()) return null
        return try {
            val style = r.newMetricStyle.newInstance()
            // The template renders at most three; sending more is a silent drop.
            for (metric in metrics.take(3)) {
                r.addMetric.invoke(style, toPlatformMetric(r, metric))
            }
            if (criticalMetric in 0 until minOf(metrics.size, 3)) {
                r.setCriticalMetric.invoke(style, criticalMetric)
            }
            Notification.Builder.recoverBuilder(context, notification)
                .setStyle(style as Notification.Style)
                .build()
        } catch (e: Throwable) {
            Log.w(TAG, "MetricStyle failed, staying on ProgressStyle: $e")
            null
        }
    }

    private fun toPlatformMetric(r: Refs, metric: TripLiveUpdate.Metric): Any {
        val value: Any = when (metric.kind) {
            TripLiveUpdate.MetricKind.COUNT ->
                r.newFixedInt.newInstance(metric.number, metric.unit)

            TripLiveUpdate.MetricKind.TEXT ->
                r.newFixedText.newInstance(metric.text ?: "", metric.unit)

            TripLiveUpdate.MetricKind.CLOCK -> {
                val minuteOfDay = ((metric.number % 1440) + 1440) % 1440
                val localTime = r.localTimeOf.invoke(null, minuteOfDay / 60, minuteOfDay % 60)
                r.newFixedTime.newInstance(localTime)
            }
        }
        val semantic =
            if (SemanticStyle.isValid(metric.semanticStyle)) metric.semanticStyle
            else SemanticStyle.UNSPECIFIED
        return r.newMetric.newInstance(value, metric.label, semantic)
    }
}
