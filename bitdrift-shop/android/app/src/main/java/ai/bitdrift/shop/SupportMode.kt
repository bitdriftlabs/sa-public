package ai.bitdrift.shop

import ai.bitdrift.shop.generated.*

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import io.bitdrift.capture.Capture.Logger

/**
 * Customer-support session marker. While enabled, the global field `support=true` is attached
 * to every log, span, and network event so a bitdrift workflow can match and record support
 * sessions. Disabling removes the field.
 */
object SupportMode {
    const val FIELD = SpecFields.SUPPORT

    var enabled by mutableStateOf(false)
        private set

    fun toggle() {
        enabled = !enabled
        // bitdrift SDK: addField() sets a global field on every subsequent log/span; removeField()
        // stops tagging. POC: workflow that records sessions where support=true.
        if (enabled) {
            Logger.addField(FIELD, "true")
        } else {
            Logger.removeField(FIELD)
        }
        ScreenLogger.logInfo(if (enabled) SpecEvents.SUPPORT_MODE_ON else SpecEvents.SUPPORT_MODE_OFF)
    }
}
