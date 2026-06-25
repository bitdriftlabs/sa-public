package ai.bitdrift.shop.shared

import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob

/**
 * Creates a MainScope for use from iOS (Swift cannot create Kotlin CoroutineScopes directly).
 */
fun createMainScope(): CoroutineScope = CoroutineScope(SupervisorJob() + Dispatchers.Main)
