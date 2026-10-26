package ai.bitdrift.shop

import io.bitdrift.capture.commands.CommandAttachment
import io.bitdrift.capture.commands.CommandErrorCode
import io.bitdrift.capture.experimental.ExperimentalBitdriftApi

/**
 * Commands an SE (or an agent) can run on a live device with `bd command send` or from the live
 * debugger, to pull state without reproducing the problem. Registered once at startup.
 *
 *  - `dump_cart_state`: the cart as JSON (attachment) plus item count and total.
 *  - `flip_flag` {flag}: flips one of the install-persistent feature flags and returns from/to.
 */
@OptIn(ExperimentalBitdriftApi::class)
object AppCommands {
    const val DUMP_CART_STATE = "dump_cart_state"
    const val FLIP_FLAG = "flip_flag"

    fun register() {
        RecordingLogger.registerCommand(DUMP_CART_STATE) {
            val cart = try {
                ApiClient.getCart()
            } catch (e: Exception) {
                return@registerCommand error(
                    title = "Cart unavailable",
                    description = e.message,
                    code = CommandErrorCode.HandlerFailed,
                )
            }
            val items = cart.optJSONArray("items")?.length() ?: 0
            success(
                attachment = CommandAttachment(cart.toString(2).toByteArray(), "application/json"),
                context = mapOf("items" to items.toString(), "total" to cart.optDouble("total", 0.0).toString()),
            )
        }

        RecordingLogger.registerCommand(FLIP_FLAG) {
            val flag = argument("flag")
            val flipped = PersistentFeatureFlags.flip(ShoppingDemoApp.appContext, flag)
                ?: return@registerCommand error(
                    title = "Unknown flag",
                    description = "'$flag' is not one of ${PersistentFeatureFlags.flagKeys}",
                    code = CommandErrorCode.InvalidArguments,
                )
            success(context = mapOf("flag" to flag, "from" to flipped.first, "to" to flipped.second))
        }
    }
}
