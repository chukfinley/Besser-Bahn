package dev.chuk.betterbahn.liveupdate

import android.app.Notification
import android.content.Context
import android.os.Build
import androidx.core.app.NotificationCompat
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.annotation.Config

/**
 * What can be checked without a device: the notification we hand the system.
 *
 * Whether it is then *promoted* is the system's call and cannot be asserted
 * here — but `hasPromotableCharacteristics` is exactly the precondition the
 * platform applies before it even considers promoting, so a Live Update that
 * fails it is broken no matter what the device does.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [36])
class TripLiveUpdateTest {

    private val context: Context get() = RuntimeEnvironment.getApplication()

    private val now = 1_700_000_000_000L

    private fun spec(
        chipText: String? = "+12",
        eta: Long? = now + 30 * 60_000L,
        metrics: List<TripLiveUpdate.Metric> = emptyList(),
        style: TripLiveUpdate.StyleMode = TripLiveUpdate.StyleMode.AUTO,
    ) = TripLiveUpdate.Spec(
        title = "RE 7 · +12 min",
        text = "Nächster Halt: Kiel Hbf · an 09:34",
        chipText = chipText,
        segments = listOf(
            TripLiveUpdate.Segment(minutes = 20, color = 0xFF2E7D32.toInt()),
            TripLiveUpdate.Segment(minutes = 40, color = 0xFFF29D38.toInt()),
        ),
        transferPoints = listOf(20),
        transferColor = 0xFFF29D38.toInt(),
        progressMinutes = 25,
        etaEpochMillis = eta,
        metrics = metrics,
        titleSemantic = SemanticStyle.CAUTION,
        style = style,
    )

    private fun build(
        spec: TripLiveUpdate.Spec = spec(),
        at: Long = now,
    ): TripLiveUpdate.Built = TripLiveUpdate.build(context, spec, at)

    private val delayMetrics = listOf(
        TripLiveUpdate.Metric(
            label = "Verspätung",
            kind = TripLiveUpdate.MetricKind.COUNT,
            number = 12,
            unit = "min",
            semanticStyle = SemanticStyle.CAUTION,
        ),
        TripLiveUpdate.Metric(
            label = "Nächster Halt",
            kind = TripLiveUpdate.MetricKind.TEXT,
            text = "Kiel Hbf",
        ),
        TripLiveUpdate.Metric(
            label = "Ankunft",
            kind = TripLiveUpdate.MetricKind.CLOCK,
            number = 9 * 60 + 34,
        ),
    )

    // --- what makes a notification promotable at all -----------------------

    /**
     * `Notification.hasPromotableCharacteristics()` as Android 16 QPR1 and up
     * define it, spelled out rather than called.
     *
     * The platform method is asserted directly in [Api37Test]; here it cannot
     * be, because Robolectric's API 36 image is stock Android 16.0, where the
     * rule is the *inverse* one (colorized required, promotion request ignored)
     * that QPR1 replaced along with shipping the Live Update UI. Mirroring the
     * criteria keeps the check honest on the runtime we have.
     */
    private fun meetsPromotionCriteria(n: android.app.Notification): Boolean =
        NotificationCompat.isRequestPromotedOngoing(n) &&
            (n.flags and Notification.FLAG_ONGOING_EVENT) != 0 &&
            !n.extras.getCharSequence(Notification.EXTRA_TITLE).isNullOrBlank() &&
            (n.flags and Notification.FLAG_GROUP_SUMMARY) == 0 &&
            n.contentView == null &&
            n.bigContentView == null &&
            n.headsUpContentView == null &&
            !n.extras.getBoolean(NotificationCompat.EXTRA_COLORIZED) &&
            n.extras.getString(Notification.EXTRA_TEMPLATE) in promotableTemplates

    private val promotableTemplates = setOf(
        "android.app.Notification\$ProgressStyle",
        "android.app.Notification\$BigTextStyle",
        "android.app.Notification\$CallStyle",
    )

    @Test
    fun `is promotable`() {
        val n = build().notification
        assertTrue(
            "the system refuses to promote anything that fails this",
            meetsPromotionCriteria(n),
        )
        assertTrue(NotificationCompat.isRequestPromotedOngoing(n))
        assertTrue(n.extras.getBoolean(NotificationCompat.EXTRA_REQUEST_PROMOTED_ONGOING))
        assertEquals(
            Notification.FLAG_ONGOING_EVENT,
            n.flags and Notification.FLAG_ONGOING_EVENT,
        )
        assertEquals("RE 7 · +12 min", n.extras.getCharSequence(Notification.EXTRA_TITLE).toString())
        assertFalse(n.extras.getBoolean(NotificationCompat.EXTRA_COLORIZED))
        // A custom view disqualifies the notification from promotion outright.
        assertNull(n.contentView)
        assertNull(n.bigContentView)
        assertNull(n.headsUpContentView)
    }

    @Test
    fun `journey survives into the notification as segments and points`() {
        val n = build().notification
        val style = NotificationCompat.Style.extractStyleFromNotification(n)
        assertTrue("expected ProgressStyle, got $style", style is NotificationCompat.ProgressStyle)
        val progress = style as NotificationCompat.ProgressStyle
        assertEquals(listOf(20, 40), progress.progressSegments.map { it.length })
        assertEquals(
            listOf(0xFF2E7D32.toInt(), 0xFFF29D38.toInt()),
            progress.progressSegments.map { it.color },
        )
        assertEquals(listOf(20), progress.progressPoints.map { it.position })
        assertEquals(25, progress.progress)
        assertFalse("segment colours must survive", progress.isStyledByProgress)
    }

    @Test
    fun `a zero-minute leg still gets a segment`() {
        val n = build(
            spec().copy(segments = listOf(TripLiveUpdate.Segment(minutes = 0, color = 1)))
        ).notification
        val style =
            NotificationCompat.Style.extractStyleFromNotification(n)
                as NotificationCompat.ProgressStyle
        assertEquals(listOf(1), style.progressSegments.map { it.length })
    }

    // --- the countdown -----------------------------------------------------

    @Test
    fun `a future eta becomes a counting-down chronometer`() {
        val eta = now + 30 * 60_000L
        val n = build(spec(eta = eta)).notification
        assertEquals(eta, n.`when`)
        assertTrue(n.extras.getBoolean(Notification.EXTRA_SHOW_CHRONOMETER))
        assertTrue(n.extras.getBoolean(Notification.EXTRA_CHRONOMETER_COUNT_DOWN))
    }

    @Test
    fun `an eta in the past is not a countdown`() {
        // The system drops an update whose `when` has already passed, so a train
        // that is late past its own arrival time must show no countdown at all.
        val n = build(spec(eta = now - 5 * 60_000L)).notification
        assertFalse(n.extras.getBoolean(Notification.EXTRA_SHOW_CHRONOMETER))
        assertFalse(n.extras.getBoolean(Notification.EXTRA_CHRONOMETER_COUNT_DOWN))
    }

    @Test
    fun `an eta inside the next minute is not a countdown either`() {
        val n = build(spec(eta = now + 30_000L)).notification
        assertFalse(n.extras.getBoolean(Notification.EXTRA_SHOW_CHRONOMETER))
    }

    @Test
    fun `no eta means no countdown`() {
        val n = build(spec(eta = null)).notification
        assertFalse(n.extras.getBoolean(Notification.EXTRA_SHOW_CHRONOMETER))
    }

    // --- the status-bar chip ----------------------------------------------

    @Test
    fun `short critical text is the delay`() {
        assertEquals("+12", NotificationCompat.getShortCriticalText(build().notification))
    }

    @Test
    fun `blank short critical text is left unset`() {
        // An empty chip string still claims the chip: the status bar shows a stub.
        assertNull(NotificationCompat.getShortCriticalText(build(spec(chipText = "   ")).notification))
        assertNull(NotificationCompat.getShortCriticalText(build(spec(chipText = null)).notification))
    }

    // --- tiers -------------------------------------------------------------

    @Test
    @Config(sdk = [24, 26, 33, 35])
    fun `below android 16 it degrades instead of crashing`() {
        val built = build(spec(metrics = delayMetrics))
        assertEquals("progress", built.style)
        // NotificationCompat.ProgressStyle has no platform counterpart here, so
        // it must come out as an ordinary determinate progress bar.
        val n = built.notification
        assertEquals(60, n.extras.getInt(NotificationCompat.EXTRA_PROGRESS_MAX))
        assertEquals(25, n.extras.getInt(NotificationCompat.EXTRA_PROGRESS))
        assertFalse(n.extras.getBoolean(NotificationCompat.EXTRA_PROGRESS_INDETERMINATE))
        assertFalse(Api37.available)
        // Channels only exist from 26 — and the call must be a no-op below it,
        // not a NoClassDefFoundError.
        TripLiveUpdate.ensureChannel(context)
        assertFalse(TripLiveUpdate.isSupported(context))
        assertFalse(TripLiveUpdate.isPromoted(context))
    }

    @Test
    fun `metrics are ignored where MetricStyle does not exist`() {
        assertEquals(Build.VERSION.SDK_INT >= Api37.SDK_METRIC_STYLE, Api37.available)
        val built = build(spec(metrics = delayMetrics))
        assertEquals("progress", built.style)
        assertTrue(
            NotificationCompat.Style.extractStyleFromNotification(built.notification)
                is NotificationCompat.ProgressStyle,
        )
    }

    @Test
    fun `an explicit metric request still falls back below android 17`() {
        val built = build(
            spec(metrics = delayMetrics, style = TripLiveUpdate.StyleMode.METRIC)
        )
        assertEquals("progress", built.style)
        assertTrue(meetsPromotionCriteria(built.notification))
    }

    @Test
    fun `semantic annotation leaves the words intact where it cannot apply`() {
        // Stripping the styling must never change the meaning of the text — the
        // documented contract of these spans, and what every device below 17 does.
        assertEquals("RE 7 · +12 min", Api37.annotate("RE 7 · +12 min", SemanticStyle.DANGER).toString())
        assertEquals("", Api37.annotate("", SemanticStyle.DANGER).toString())
        assertEquals("x", Api37.annotate("x", 99).toString())
    }

    @Test
    fun `progress style can be forced`() {
        val built = build(
            spec(metrics = delayMetrics, style = TripLiveUpdate.StyleMode.PROGRESS)
        )
        assertEquals("progress", built.style)
    }
}
