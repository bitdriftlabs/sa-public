@_spi(ExperimentalAPI) import Capture
import Foundation

/// Commands an SE (or an agent) can run on a live device with `bd command send` or from the live
/// debugger, to pull state without reproducing the problem. Passed to `Logger.start`.
///
///  - `dump_cart_state`: the cart as JSON (attachment) plus item count and total.
///  - `flip_flag` {flag}: flips one of the install-persistent feature flags and returns from/to.
enum AppCommands {
    static let dumpCartState = "dump_cart_state"
    static let flipFlag = "flip_flag"

    static var all: [Command] {
        [
            Command(key: dumpCartState) { _ in
                guard let cart = try? await ApiClient.getCart() else {
                    return .failure(CommandError(title: "Cart unavailable", description: "GET /api/cart failed"))
                }
                let data = (try? JSONSerialization.data(
                    withJSONObject: cart.raw ?? [:], options: [.prettyPrinted, .sortedKeys])) ?? Data()
                return .success(CommandResult(
                    attachment: CommandAttachment(data: data, mimeType: "application/json"),
                    context: ["items": String(cart["items"].array.count), "total": String(cart.num("total"))]
                ))
            },
            Command(key: flipFlag) { args in
                let flag = args.string(for: "flag") ?? ""
                guard let flipped = PersistentFeatureFlags.flip(flag) else {
                    return .failure(.invalidArguments(
                        description: "'\(flag)' is not one of \(PersistentFeatureFlags.flagKeys)"))
                }
                return .success(CommandResult(context: ["flag": flag, "from": flipped.from, "to": flipped.to]))
            },
        ]
    }
}
