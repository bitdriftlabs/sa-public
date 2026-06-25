package ai.bitdrift.shop

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import androidx.navigation.NavController
import ai.bitdrift.shop.shared.SimulationEngine
import ai.bitdrift.shop.shared.SimVariant
import kotlinx.coroutines.flow.StateFlow

class SimulationViewModel : ViewModel() {

    private val engine = SimulationEngine()

    val isSimulating: StateFlow<Boolean> = engine.isSimulating
    val currentRun: StateFlow<Int> = engine.currentRun
    val totalRuns: StateFlow<Int> = engine.totalRuns
    val isInfiniteMode: Boolean get() = engine.isInfiniteMode

    val activeVariant: StateFlow<SimVariant> = engine.activeVariant
    val crashLoopEnabled: StateFlow<Boolean> = engine.crashLoopEnabled
    val anrAEnabled: StateFlow<Boolean> = engine.anrAEnabled
    val forceQuitEnabled: StateFlow<Boolean> = engine.forceQuitEnabled
    val slowModeEnabled: StateFlow<Boolean> = engine.slowModeEnabled

    fun setVariant(v: SimVariant) = engine.setVariant(v)
    fun toggleCrashLoop() = engine.setCrashLoop(!engine.crashLoopEnabled.value)
    fun toggleAnrA() = engine.setAnrA(!engine.anrAEnabled.value)
    fun toggleForceQuit() = engine.setForceQuit(!engine.forceQuitEnabled.value)
    fun toggleSlowMode() = engine.setSlowMode(!engine.slowModeEnabled.value)

    fun simulate(runs: Int, navController: NavController) {
        engine.simulate(runs, AndroidNavigator(navController), viewModelScope)
    }

    fun infiniteSimulate(navController: NavController) {
        engine.infiniteSimulate(AndroidNavigator(navController), viewModelScope)
    }

    fun startAbSimulation(navController: NavController) {
        engine.startAbSimulation(AndroidNavigator(navController), viewModelScope)
    }

    fun startCardinalitySimulation(navController: NavController) {
        engine.startCardinalitySimulation(AndroidNavigator(navController), viewModelScope)
    }

    fun cancel() {
        engine.cancel()
    }
}
