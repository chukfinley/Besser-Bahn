package dev.chuk.betterbahn.liveupdate

import android.app.Notification
import android.content.Context
import android.text.Annotation
import android.text.Spanned
import androidx.core.app.NotificationCompat
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.annotation.Config

/**
 * The Android 17 tier, on the only Android 17 available without the device:
 * Robolectric's API 37 runtime.
 *
 * This is the tier that is reached by reflection, so the thing actually under
 * test is whether those signatures still exist — a rename upstream shows up here
 * as a failure instead of as a silently degraded Live Update on the phone.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [37])
class Api37Test {

    private val context: Context get() = RuntimeEnvironment.getApplication()

    private val metrics = listOf(
        TripLiveUpdate.Metric(
            label = "Verspätung",
            kind = TripLiveUpdate.MetricKind.COUNT,
            number = 12,
            unit = "min",
            semanticStyle = SemanticStyle.CAUTION,
        ),
        TripLiveUpdate.Metric(
            label = "Nächster",
            kind = TripLiveUpdate.MetricKind.TEXT,
            text = "Kiel Hbf",
        ),
        TripLiveUpdate.Metric(
            label = "Ankunft",
            kind = TripLiveUpdate.MetricKind.CLOCK,
            number = 9 * 60 + 34,
        ),
    )

    private fun spec(
        metrics: List<TripLiveUpdate.Metric> = this.metrics,
        style: TripLiveUpdate.StyleMode = TripLiveUpdate.StyleMode.AUTO,
        criticalMetric: Int = 0,
    ) = TripLiveUpdate.Spec(
        title = "RE 7 · +12 min",
        text = "Nächster Halt: Kiel Hbf · an 09:34",
        chipText = "+12",
        segments = listOf(TripLiveUpdate.Segment(20, 0xFF2E7D32.toInt())),
        progressMinutes = 5,
        metrics = metrics,
        criticalMetric = criticalMetric,
        titleSemantic = SemanticStyle.CAUTION,
        style = style,
    )

    @Test
    fun `metric style is reachable on android 17`() {
        assertTrue(Api37.available)
        val built = TripLiveUpdate.build(context, spec())
        assertEquals("metric", built.style)
        assertEquals(
            "android.app.Notification\$MetricStyle",
            built.notification.extras.getString(Notification.EXTRA_TEMPLATE),
        )
    }

    @Test
    fun `the three metrics arrive with their labels, values and semantics`() {
        val notification = TripLiveUpdate.build(context, spec()).notification
        val style = Notification.Builder.recoverBuilder(context, notification).style!!
        val metrics = style.javaClass.getMethod("getMetrics").invoke(style) as List<*>
        assertEquals(3, metrics.size)

        val labels = metrics.map { label(it!!) }
        assertEquals(listOf("Verspätung", "Nächster", "Ankunft"), labels)
        assertEquals(SemanticStyle.CAUTION, semantic(metrics[0]!!))

        val delay = value(metrics[0]!!)
        assertEquals(12, delay.javaClass.getMethod("getValue").invoke(delay))
        assertEquals("min", delay.javaClass.getMethod("getUnit").invoke(delay).toString())
        assertEquals("Kiel Hbf", value(metrics[1]!!).let {
            it.javaClass.getMethod("getValue").invoke(it).toString()
        })
        // 09:34 travels as a minute of the day and has to come back as a LocalTime.
        val arrival = value(metrics[2]!!)
        assertEquals(
            "09:34",
            arrival.javaClass.getMethod("getValue").invoke(arrival).toString(),
        )
    }

    @Test
    fun `more than three metrics are cut rather than dropped whole`() {
        val four = metrics + TripLiveUpdate.Metric(
            label = "Gleis",
            kind = TripLiveUpdate.MetricKind.TEXT,
            text = "7",
        )
        val notification = TripLiveUpdate.build(context, spec(metrics = four)).notification
        val style = Notification.Builder.recoverBuilder(context, notification).style!!
        assertEquals(3, (style.javaClass.getMethod("getMetrics").invoke(style) as List<*>).size)
    }

    @Test
    fun `no metrics means the journey bar, not an empty template`() {
        val built = TripLiveUpdate.build(context, spec(metrics = emptyList()))
        assertEquals("progress", built.style)
    }

    @Test
    fun `the metric notification keeps everything that makes it promotable`() {
        val notification = TripLiveUpdate.build(context, spec()).notification
        assertEquals(
            Notification.FLAG_ONGOING_EVENT,
            notification.flags and Notification.FLAG_ONGOING_EVENT,
        )
        assertTrue(NotificationCompat.isRequestPromotedOngoing(notification))
        assertEquals("+12", NotificationCompat.getShortCriticalText(notification))
        // The platform's own gate — recoverBuilder must not have dropped a thing.
        val gate = Notification::class.java.getMethod("hasPromotableCharacteristics")
        assertEquals(true, gate.invoke(notification))
    }

    @Test
    fun `the title carries a semantic span the system can colour`() {
        val annotated = Api37.annotate("RE 7 · +12 min", SemanticStyle.DANGER)
        assertTrue("expected a Spanned, got ${annotated.javaClass}", annotated is Spanned)
        val spans = (annotated as Spanned)
            .getSpans(0, annotated.length, Annotation::class.java)
        assertEquals(1, spans.size)
        // Stripping the span must leave the words untouched.
        assertEquals("RE 7 · +12 min", annotated.toString())
    }

    @Test
    fun `the span reaches the notification, not just the string`() {
        val title = TripLiveUpdate.build(context, spec()).notification
            .extras.getCharSequence(Notification.EXTRA_TITLE)
        assertTrue("NotificationCompat must not flatten the title", title is Spanned)
        assertEquals(
            1,
            (title as Spanned).getSpans(0, title.length, Annotation::class.java).size,
        )
    }

    @Test
    fun `an unspecified semantic style is left unspanned`() {
        val plain = Api37.annotate("RE 7", SemanticStyle.UNSPECIFIED)
        assertEquals("RE 7", plain.toString())
        assertTrue(plain !is Spanned)
    }

    @Test
    fun `progress style can still be forced on android 17`() {
        val built = TripLiveUpdate.build(
            context,
            spec(style = TripLiveUpdate.StyleMode.PROGRESS),
        )
        assertEquals("progress", built.style)
        assertTrue(
            NotificationCompat.Style.extractStyleFromNotification(built.notification)
                is NotificationCompat.ProgressStyle,
        )
    }

    private fun label(metric: Any): String =
        metric.javaClass.getMethod("getLabel").invoke(metric).toString()

    private fun semantic(metric: Any): Int =
        metric.javaClass.getMethod("getSemanticStyle").invoke(metric) as Int

    private fun value(metric: Any): Any =
        metric.javaClass.getMethod("getValue").invoke(metric)!!
}
