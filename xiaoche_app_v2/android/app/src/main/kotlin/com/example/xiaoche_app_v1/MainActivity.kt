package com.example.xiaoche_app_v1

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Bundle
import android.speech.RecognitionListener
import android.speech.RecognizerIntent
import android.speech.SpeechRecognizer
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
  private val channelName = "com.example.xiaoche_app_v1/speech"
  private val micRequestCode = 12001

  private lateinit var channel: MethodChannel
  private var speechRecognizer: SpeechRecognizer? = null
  private var pendingStartResult: MethodChannel.Result? = null

  override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
    super.configureFlutterEngine(flutterEngine)

    channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
    channel.setMethodCallHandler { call, result ->
      when (call.method) {
        "initialize" -> {
          result.success(true)
        }
        "startListening" -> {
          startListening(result)
        }
        "stopListening" -> {
          stopListening()
          result.success(true)
        }
        else -> result.notImplemented()
      }
    }
  }

  private fun startListening(result: MethodChannel.Result) {
    val granted = ContextCompat.checkSelfPermission(
      this,
      Manifest.permission.RECORD_AUDIO
    ) == PackageManager.PERMISSION_GRANTED

    if (!granted) {
      pendingStartResult = result
      ActivityCompat.requestPermissions(
        this,
        arrayOf(Manifest.permission.RECORD_AUDIO),
        micRequestCode
      )
      return
    }

    internalStartListening(result)
  }

  private fun internalStartListening(result: MethodChannel.Result) {
    try {
      if (!SpeechRecognizer.isRecognitionAvailable(this)) {
        result.error("not_available", "Speech recognition not available", null)
        return
      }

      stopListening()

      speechRecognizer = SpeechRecognizer.createSpeechRecognizer(this)

      val intent = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
        putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
        putExtra(RecognizerIntent.EXTRA_LANGUAGE, "zh-CN")
        putExtra(RecognizerIntent.EXTRA_PARTIAL_RESULTS, true)
        putExtra(RecognizerIntent.EXTRA_CALLING_PACKAGE, packageName)
      }

      speechRecognizer?.setRecognitionListener(object : RecognitionListener {
        override fun onReadyForSpeech(params: Bundle?) {}
        override fun onBeginningOfSpeech() {}
        override fun onRmsChanged(rmsdB: Float) {}
        override fun onBufferReceived(buffer: ByteArray?) {}
        override fun onEndOfSpeech() {}

        override fun onError(error: Int) {
          val errorMsg = when (error) {
            SpeechRecognizer.ERROR_AUDIO -> "音频错误"
            SpeechRecognizer.ERROR_CLIENT -> "客户端错误"
            SpeechRecognizer.ERROR_INSUFFICIENT_PERMISSIONS -> "权限不足"
            SpeechRecognizer.ERROR_NETWORK -> "网络错误"
            SpeechRecognizer.ERROR_NO_MATCH -> "无匹配结果"
            SpeechRecognizer.ERROR_RECOGNIZER_BUSY -> "识别器忙碌"
            SpeechRecognizer.ERROR_SERVER -> "服务器错误"
            SpeechRecognizer.ERROR_SPEECH_TIMEOUT -> "语音超时"
            else -> "未知错误($error)"
          }
          channel.invokeMethod(
            "onSpeechResult",
            mapOf("text" to "ERR:$errorMsg")
          )
        }

        override fun onResults(results: Bundle?) {
          val matches = results?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)
          if (!matches.isNullOrEmpty()) {
            channel.invokeMethod("onSpeechResult", mapOf("text" to matches[0]))
          }
        }

        override fun onPartialResults(partialResults: Bundle?) {
          val matches = partialResults?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)
          if (!matches.isNullOrEmpty()) {
            channel.invokeMethod("onSpeechResult", mapOf("text" to matches[0]))
          }
        }

        override fun onEvent(eventType: Int, params: Bundle?) {}
      })

      speechRecognizer?.startListening(intent)
      result.success(true)
    } catch (e: Exception) {
      result.error("start_failed", e.message, null)
    }
  }

  private fun stopListening() {
    try {
      speechRecognizer?.stopListening()
      speechRecognizer?.cancel()
      speechRecognizer?.destroy()
    } catch (_: Exception) {
    } finally {
      speechRecognizer = null
    }
  }

  override fun onRequestPermissionsResult(
    requestCode: Int,
    permissions: Array<out String>,
    grantResults: IntArray
  ) {
    super.onRequestPermissionsResult(requestCode, permissions, grantResults)

    if (requestCode == micRequestCode) {
      val granted = grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED
      val pending = pendingStartResult
      pendingStartResult = null

      if (pending == null) return

      if (!granted) {
        pending.error("permission_denied", "RECORD_AUDIO permission denied", null)
        return
      }

      internalStartListening(pending)
    }
  }
}
