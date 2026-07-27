package dev.chuk.betterbahn.liveupdate

/**
 * Mirror of `Notification.SEMANTIC_STYLE_*` (API 37).
 *
 * Hard-coded rather than read off the platform class because the values travel
 * over the method channel from Dart, where nothing can look them up, and a
 * platform constant is frozen once shipped. Everything that consumes them is
 * guarded by [Api37]; below Android 17 they are inert numbers.
 */
object SemanticStyle {
    const val UNSPECIFIED = 0
    const val INFO = 1
    const val SAFE = 2
    const val CAUTION = 3
    const val DANGER = 4

    fun isValid(value: Int): Boolean = value in UNSPECIFIED..DANGER
}
