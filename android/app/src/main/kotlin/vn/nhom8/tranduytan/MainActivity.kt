package vn.nhom8.tranduytan

import android.hardware.biometrics.BiometricManager
import android.hardware.biometrics.BiometricPrompt
import android.os.Build
import android.os.CancellationSignal
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var biometricCancellation: CancellationSignal? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "vn.nhom8.tranduytan/biometrics")
            .setMethodCallHandler { call, result ->
                if (call.method == "available") {
                    val available = Build.VERSION.SDK_INT >= Build.VERSION_CODES.R &&
                        getSystemService(BiometricManager::class.java)
                            .canAuthenticate(BiometricManager.Authenticators.BIOMETRIC_STRONG) == BiometricManager.BIOMETRIC_SUCCESS
                    result.success(available)
                } else if (call.method != "authenticateStrong") {
                    result.notImplemented()
                } else if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) {
                    result.error("UNSUPPORTED", "Sinh trắc học cần Android 11 trở lên.", null)
                } else if (biometricCancellation != null) {
                    result.error("BUSY", "Đang xác thực sinh trắc học.", null)
                } else {
                    val cancellation = CancellationSignal()
                    biometricCancellation = cancellation
                    var completed = false
                    fun finish(success: Boolean) {
                        if (!completed) {
                            completed = true
                            biometricCancellation = null
                            result.success(success)
                        }
                    }
                    val prompt = BiometricPrompt.Builder(this)
                        .setTitle("Mở khóa TRANDUYTAN")
                        .setSubtitle("Xác thực bằng sinh trắc học đã đăng ký trên điện thoại")
                        .setAllowedAuthenticators(BiometricManager.Authenticators.BIOMETRIC_STRONG)
                        .setNegativeButton("Hủy", mainExecutor) { _, _ ->
                            finish(false)
                            cancellation.cancel()
                        }
                        .build()
                    prompt.authenticate(cancellation, mainExecutor, object : BiometricPrompt.AuthenticationCallback() {
                        override fun onAuthenticationSucceeded(authentication: BiometricPrompt.AuthenticationResult) {
                            finish(true)
                        }

                        override fun onAuthenticationError(errorCode: Int, errString: CharSequence) {
                            finish(false)
                        }
                    })
                }
            }
    }

    override fun onDestroy() {
        biometricCancellation?.cancel()
        super.onDestroy()
    }
}
