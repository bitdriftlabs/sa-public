package ai.bitdrift.shop

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import androidx.navigation.NavController
import ai.bitdrift.shop.shared.SimulationEngine
import kotlinx.coroutines.flow.StateFlow

/**
 * Android ViewModel wrapping the shared SimulationEngine.
 */
class SimulationViewModel : ViewModel() {

    private val engine = SimulationEngine()

    val isSimulating: StateFlow<Boolean> = engine.isSimulating
    val currentRun: StateFlow<Int> = engine.currentRun
    val totalRuns: StateFlow<Int> = engine.totalRuns
    val isInfiniteMode: Boolean get() = engine.isInfiniteMode

    fun simulate(runs: Int, navController: NavController) {
        engine.simulate(runs, AndroidNavigator(navController), viewModelScope)
    }

    fun infiniteSimulate(navController: NavController) {
        engine.infiniteSimulate(AndroidNavigator(navController), viewModelScope)
    }

    fun cancel() {
        engine.cancel()
    }
}
