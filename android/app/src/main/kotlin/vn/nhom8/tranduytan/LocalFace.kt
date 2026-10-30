package vn.nhom8.tranduytan

import android.content.Context
import android.graphics.Bitmap
import android.os.Handler
import android.os.Looper
import com.google.android.gms.tasks.Tasks
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.face.FaceDetection
import com.google.mlkit.vision.face.FaceDetectorOptions
import com.google.mlkit.vision.face.FaceLandmark
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import org.opencv.android.OpenCVLoader
import org.opencv.android.Utils
import org.opencv.core.CvType
import org.opencv.core.Mat
import org.opencv.imgcodecs.Imgcodecs
import org.opencv.imgproc.Imgproc
import org.opencv.objdetect.FaceRecognizerSF
import java.io.File
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit

object LocalFace {
    private val worker = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())
    private var recognizer: FaceRecognizerSF? = null
    private val detector by lazy {
        FaceDetection.getClient(FaceDetectorOptions.Builder()
            .setPerformanceMode(FaceDetectorOptions.PERFORMANCE_MODE_ACCURATE)
            .setLandmarkMode(FaceDetectorOptions.LANDMARK_MODE_ALL)
            .setClassificationMode(FaceDetectorOptions.CLASSIFICATION_MODE_ALL)
            .setMinFaceSize(0.18f).build())
    }

    fun register(context: Context, messenger: BinaryMessenger) {
        MethodChannel(messenger, "vn.nhom8.tranduytan/local_face").setMethodCallHandler { call, result ->
            if (call.method != "features") {
                result.notImplemented()
            } else {
                val path = call.argument<String>("image")
                val model = call.argument<String>("model")
                worker.execute {
                    try {
                        require(path != null && model != null)
                        val root = File(context.applicationInfo.dataDir).canonicalPath + File.separator
                        require(File(path).canonicalPath.startsWith(root) && File(model).canonicalPath.startsWith(root))
                        val output = features(path, model)
                        main.post { result.success(output) }
                    } catch (error: Throwable) {
                        val diagnostic = if (path != null && File(path).name.startsWith("fixed-face-"))
                            "${error.javaClass.simpleName}: ${error.message}; ${error.stackTrace.firstOrNull()}" else null
                        main.post { result.error("FACE_SCAN", "Giữ một khuôn mặt rõ, đủ sáng trong khung hình.", diagnostic) }
                    }
                }
            }
        }
    }

    private fun features(path: String, model: String): Map<String, Any> {
        check(OpenCVLoader.initLocal())
        val engine = recognizer ?: FaceRecognizerSF.create(model, "").also { recognizer = it }
        val source = Imgcodecs.imread(path)
        val rgba = Mat()
        val landmarks = Mat(1, 15, CvType.CV_32FC1)
        val aligned = Mat()
        val feature = Mat()
        var bitmap: Bitmap? = null
        try {
            require(!source.empty())
            Imgproc.cvtColor(source, rgba, Imgproc.COLOR_BGR2RGBA)
            val image = Bitmap.createBitmap(source.cols(), source.rows(), Bitmap.Config.ARGB_8888)
            bitmap = image
            Utils.matToBitmap(rgba, image)
            val faces = Tasks.await(detector.process(InputImage.fromBitmap(image, 0)), 10, TimeUnit.SECONDS)
            require(faces.size == 1) { "Expected one face, detected ${faces.size}" }
            val face = faces.first()
            val box = face.boundingBox
            require(box.width() >= 90 && box.height() >= 90)
            val eyes = listOf(FaceLandmark.LEFT_EYE, FaceLandmark.RIGHT_EYE)
                .map { requireNotNull(face.getLandmark(it)).position }.sortedBy { it.x }
            val mouth = listOf(FaceLandmark.MOUTH_LEFT, FaceLandmark.MOUTH_RIGHT)
                .map { requireNotNull(face.getLandmark(it)).position }.sortedBy { it.x }
            val nose = requireNotNull(face.getLandmark(FaceLandmark.NOSE_BASE)).position
            landmarks.put(0, 0, floatArrayOf(box.left.toFloat(), box.top.toFloat(), box.width().toFloat(), box.height().toFloat(),
                eyes[0].x, eyes[0].y, eyes[1].x, eyes[1].y, nose.x, nose.y,
                mouth[0].x, mouth[0].y, mouth[1].x, mouth[1].y, 1f))
            engine.alignCrop(source, landmarks, aligned)
            engine.feature(aligned, feature)
            require(feature.total() == 128L)
            val vector = FloatArray(128)
            feature.get(0, 0, vector)
            return mapOf("embedding" to vector.map { it.toDouble() }, "yaw" to face.headEulerAngleY.toDouble())
        } finally {
            bitmap?.recycle()
            source.release(); rgba.release(); landmarks.release(); aligned.release(); feature.release()
        }
    }
}
