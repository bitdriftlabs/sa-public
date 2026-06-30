package ai.bitdrift.manualtracing

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import io.bitdrift.capture.Capture.Logger
import io.bitdrift.capture.LogLevel
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

data class JourneyProgress(val stepIdx: Int, val screenName: String, val total: Int)

private data class JourneyStep(
    val screenName: String,
    val event: String,
    val fields: Map<String, String>,
    val url: String,
    val delayMs: Long,
)

// 10-step shopping journey. Each step logs a screen/action event then fires one
// network request to a public placeholder endpoint — no backend required.
private val SHOPPING_JOURNEY = listOf(
    JourneyStep(
        screenName = "Welcome",
        event = "screen_view",
        fields = mapOf("_screen_name" to "Welcome"),
        url = "https://jsonplaceholder.typicode.com/posts/1",
        delayMs = 500,
    ),
    JourneyStep(
        screenName = "Browse",
        event = "screen_view",
        fields = mapOf("_screen_name" to "Browse"),
        url = "https://jsonplaceholder.typicode.com/users/1",
        delayMs = 900,
    ),
    JourneyStep(
        screenName = "Search",
        event = "screen_view",
        fields = mapOf("_screen_name" to "Search", "query" to "headphones"),
        url = "https://jsonplaceholder.typicode.com/todos/1",
        delayMs = 700,
    ),
    JourneyStep(
        screenName = "Featured",
        event = "screen_view",
        fields = mapOf("_screen_name" to "Featured"),
        url = "https://jsonplaceholder.typicode.com/albums/1",
        delayMs = 700,
    ),
    JourneyStep(
        screenName = "ProductDetail",
        event = "screen_view",
        fields = mapOf("_screen_name" to "ProductDetail", "product_id" to "p42", "source_screen" to "Featured"),
        url = "https://jsonplaceholder.typicode.com/photos/1",
        delayMs = 1500,
    ),
    JourneyStep(
        screenName = "Reviews",
        event = "screen_view",
        fields = mapOf("_screen_name" to "Reviews", "product_id" to "p42"),
        url = "https://jsonplaceholder.typicode.com/comments/1",
        delayMs = 1200,
    ),
    JourneyStep(
        screenName = "Cart",
        event = "add_to_cart",
        fields = mapOf("_screen_name" to "Cart", "product_id" to "p42", "source_screen" to "Reviews"),
        url = "https://jsonplaceholder.typicode.com/posts/2",
        delayMs = 800,
    ),
    JourneyStep(
        screenName = "CheckoutGuest",
        event = "checkout_started",
        fields = mapOf("_screen_name" to "CheckoutGuest", "checkout_type" to "guest"),
        url = "https://jsonplaceholder.typicode.com/users/1",
        delayMs = 1200,
    ),
    JourneyStep(
        screenName = "PaymentCard",
        event = "screen_view",
        fields = mapOf("_screen_name" to "PaymentCard", "payment_method" to "card"),
        url = "https://jsonplaceholder.typicode.com/todos/1",
        delayMs = 1500,
    ),
    JourneyStep(
        screenName = "Confirmation",
        event = "payment_completed",
        fields = mapOf("_screen_name" to "Confirmation", "payment_method" to "card", "order_id" to "ord-demo"),
        url = "https://jsonplaceholder.typicode.com/albums/1",
        delayMs = 600,
    ),
)

// OkHttp loop uses a simple rotating target list.
private val OKHTTP_TARGETS = listOf(
    "https://jsonplaceholder.typicode.com/posts/1",
    "https://jsonplaceholder.typicode.com/users/1",
    "https://jsonplaceholder.typicode.com/todos/1",
    "https://jsonplaceholder.typicode.com/comments/1",
    "https://jsonplaceholder.typicode.com/posts/2",
    "https://jsonplaceholder.typicode.com/albums/1",
    "https://jsonplaceholder.typicode.com/photos/1",
)

class NetworkViewModel : ViewModel() {

    private val _results = MutableStateFlow<List<RequestResult>>(emptyList())
    val results: StateFlow<List<RequestResult>> = _results.asStateFlow()

    private val _isSimulatingManual = MutableStateFlow(false)
    val isSimulatingManual: StateFlow<Boolean> = _isSimulatingManual.asStateFlow()

    private val _isSimulatingOkHttp = MutableStateFlow(false)
    val isSimulatingOkHttp: StateFlow<Boolean> = _isSimulatingOkHttp.asStateFlow()

    private val _isRunning10xManual = MutableStateFlow(false)
    val isRunning10xManual: StateFlow<Boolean> = _isRunning10xManual.asStateFlow()

    private val _isRunning10xOkHttp = MutableStateFlow(false)
    val isRunning10xOkHttp: StateFlow<Boolean> = _isRunning10xOkHttp.asStateFlow()

    // Step progress — null when idle, populated while a journey is executing.
    private val _manualLoopProgress = MutableStateFlow<JourneyProgress?>(null)
    val manualLoopProgress: StateFlow<JourneyProgress?> = _manualLoopProgress.asStateFlow()

    private val _manual10xProgress = MutableStateFlow<JourneyProgress?>(null)
    val manual10xProgress: StateFlow<JourneyProgress?> = _manual10xProgress.asStateFlow()

    private val _okHttpLoopCount = MutableStateFlow(0)
    val okHttpLoopCount: StateFlow<Int> = _okHttpLoopCount.asStateFlow()

    private val _isTracingActive = MutableStateFlow(false)
    val isTracingActive: StateFlow<Boolean> = _isTracingActive.asStateFlow()

    private var manualJob: Job? = null
    private var okHttpJob: Job? = null
    private var manual5xJob: Job? = null
    private var okHttp5xJob: Job? = null

    init {
        viewModelScope.launch {
            while (true) {
                _isTracingActive.value = Logger.isTracingActive == true
                delay(500)
            }
        }
    }

    // Polls until isTracingActive is true or the timeout elapses.
    // Returns true if tracing became active, false if it timed out.
    private suspend fun awaitTracingActive(timeoutMs: Long = 8_000L): Boolean {
        val deadline = System.currentTimeMillis() + timeoutMs
        while (System.currentTimeMillis() < deadline) {
            if (Logger.isTracingActive == true) return true
            delay(300)
        }
        return false
    }

    fun startManualSim() {
        if (_isSimulatingManual.value) return
        manualJob = viewModelScope.launch {
            _isSimulatingManual.value = true
            try {
                while (true) {
                    Logger.startNewSession()
                    Logger.log(LogLevel.INFO, mapOf("manual_tracing" to "true")) { "manual_tracing_started" }
                    _manualLoopProgress.value = JourneyProgress(-1, "Awaiting trace…", SHOPPING_JOURNEY.size)
                    awaitTracingActive()
                    for ((idx, step) in SHOPPING_JOURNEY.withIndex()) {
                        _manualLoopProgress.value = JourneyProgress(idx, step.screenName, SHOPPING_JOURNEY.size)
                        delay(step.delayMs)
                        Logger.log(LogLevel.INFO, step.fields) { step.event }
                        val result = withContext(Dispatchers.IO) {
                            ManualHttpClient.execute(step.url)
                        }.copy(stepName = step.screenName)
                        _results.value = listOf(result) + _results.value
                    }
                }
            } finally {
                _isSimulatingManual.value = false
                _manualLoopProgress.value = null
            }
        }
    }

    fun cancelManualSim() {
        manualJob?.cancel()
        _isSimulatingManual.value = false
        _manualLoopProgress.value = null
    }

    fun startOkHttpSim() {
        if (_isSimulatingOkHttp.value) return
        okHttpJob = viewModelScope.launch {
            _isSimulatingOkHttp.value = true
            try {
                var idx = 0
                while (true) {
                    if (idx % OKHTTP_TARGETS.size == 0) {
                        Logger.startNewSession()
                        Logger.log(LogLevel.INFO, mapOf("auto_tracing" to "true")) { "auto_tracing_started" }
                    }
                    val url = OKHTTP_TARGETS[idx % OKHTTP_TARGETS.size]
                    val result = withContext(Dispatchers.IO) { OkHttpNetworkClient.execute(url) }
                    _results.value = listOf(result) + _results.value
                    _okHttpLoopCount.value = idx + 1
                    idx++
                    delay(800)
                }
            } finally {
                _isSimulatingOkHttp.value = false
                _okHttpLoopCount.value = 0
            }
        }
    }

    fun cancelOkHttpSim() {
        okHttpJob?.cancel()
        _isSimulatingOkHttp.value = false
        _okHttpLoopCount.value = 0
    }

    // Runs 5 complete shopping journeys back-to-back, each in its own bitdrift session.
    fun runManual5x() {
        if (_isRunning10xManual.value) return
        manual5xJob = viewModelScope.launch {
            _isRunning10xManual.value = true
            try {
                repeat(5) { run ->
                    Logger.startNewSession()
                    Logger.log(LogLevel.INFO, mapOf("manual_tracing" to "true")) { "manual_tracing_started" }
                    _manual10xProgress.value = JourneyProgress(-1, "Awaiting trace… (${run + 1}/5)", SHOPPING_JOURNEY.size)
                    awaitTracingActive()
                    for ((idx, step) in SHOPPING_JOURNEY.withIndex()) {
                        _manual10xProgress.value = JourneyProgress(idx, "${step.screenName} (${run + 1}/5)", SHOPPING_JOURNEY.size)
                        delay(step.delayMs)
                        Logger.log(LogLevel.INFO, step.fields) { step.event }
                        val result = withContext(Dispatchers.IO) {
                            ManualHttpClient.execute(step.url)
                        }.copy(stepName = step.screenName)
                        _results.value = listOf(result) + _results.value
                    }
                }
            } finally {
                _isRunning10xManual.value = false
                _manual10xProgress.value = null
            }
        }
    }

    fun cancelManual5x() {
        manual5xJob?.cancel()
        _isRunning10xManual.value = false
        _manual10xProgress.value = null
    }

    fun runOkHttp5x() {
        if (_isRunning10xOkHttp.value) return
        okHttp5xJob = viewModelScope.launch {
            _isRunning10xOkHttp.value = true
            try {
                repeat(5) { run ->
                    Logger.startNewSession()
                    Logger.log(LogLevel.INFO, mapOf("auto_tracing" to "true")) { "auto_tracing_started" }
                    for ((idx, url) in OKHTTP_TARGETS.withIndex()) {
                        val result = withContext(Dispatchers.IO) { OkHttpNetworkClient.execute(url) }
                        _results.value = listOf(result) + _results.value
                        delay(200)
                    }
                }
            } finally {
                _isRunning10xOkHttp.value = false
            }
        }
    }

    fun cancelOkHttp5x() {
        okHttp5xJob?.cancel()
        _isRunning10xOkHttp.value = false
    }

    fun clearResults() {
        _results.value = emptyList()
    }
}
