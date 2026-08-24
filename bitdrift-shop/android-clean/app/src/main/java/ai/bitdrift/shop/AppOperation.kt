package ai.bitdrift.shop

import java.util.UUID

enum class AppOperationLevel { INFO }
enum class AppOperationResult { SUCCESS, FAILURE, CANCELED }

class AppOperation(val id: UUID = UUID.randomUUID()) {
    fun end(result: AppOperationResult, fields: Map<String, String> = emptyMap()) = Unit

    companion object {
        fun start(
            name: String,
            level: AppOperationLevel = AppOperationLevel.INFO,
            fields: Map<String, String> = emptyMap(),
            startTimeMs: Long? = null,
            parentSpanId: UUID? = null,
        ): AppOperation = AppOperation()
    }
}

