package ai.bitdrift.shop

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import ai.bitdrift.shop.ui.theme.ShoppingDemoKMPTheme

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        setContent {
            ShoppingDemoKMPTheme {
                ShoppingDemoContent()
            }
        }
    }
}
