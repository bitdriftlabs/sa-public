package ai.bitdrift.shop

import androidx.navigation.NavController
import ai.bitdrift.shop.shared.Navigator
import ai.bitdrift.shop.shared.AppScreen

/**
 * Android implementation of the shared Navigator interface.
 * Bridges SimulationEngine navigation calls to Jetpack Compose NavController.
 */
class AndroidNavigator(private val navController: NavController) : Navigator {
    override fun navigate(route: String) {
        navController.navigate(route)
    }

    override fun navigateAndClear(route: String) {
        navController.navigate(route) {
            popUpTo(AppScreen.Welcome.route) { inclusive = true }
        }
    }
}
