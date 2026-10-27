package com.nilupul.grab

import android.media.audiofx.PresetReverb
import android.media.audiofx.Visualizer
import android.os.Handler
import android.os.Looper
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import kotlin.math.abs
import kotlin.math.hypot
import kotlin.math.log10
import kotlin.math.max
import kotlin.math.pow

/** Native audio helpers for the Flutter side (registered from MainActivity). */
object GrabAudioFx {
    private var reverb: PresetReverb? = null
    private var reverbSession = 0

    fun register(engine: FlutterEngine) {
        EventChannel(engine.dartExecutor.binaryMessenger, "grab/visualizer")
            .setStreamHandler(VisualizerHandler())
        MethodChannel(engine.dartExecutor.binaryMessenger, "grab/reverb")
            .setMethodCallHandler { call, result ->
                if (call.method != "set") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                val session = call.argument<Int>("session") ?: 0
                val preset = call.argument<Int>("preset") ?: 0
                try {
                    if (preset <= 0 || session <= 0) {
                        releaseReverb()
                    } else {
                        if (reverb == null || reverbSession != session) {
                            releaseReverb()
                            // Insert effect on the player's own audio session.
                            reverb = PresetReverb(0, session)
                            reverbSession = session
                        }
                        reverb!!.preset = preset.toShort()
                        reverb!!.enabled = true
                    }
                    result.success(true)
                } catch (e: Exception) {
                    releaseReverb()
                    result.error("reverb", e.message ?: "Reverb not supported", null)
                }
            }
    }

    private fun releaseReverb() {
        try {
            reverb?.enabled = false
            reverb?.release()
        } catch (_: Exception) {
        }
        reverb = null
        reverbSession = 0
    }
}

/**
 * Streams 24 log-spaced frequency bands (0..1) from the player's audio
 * session. Android requires the RECORD_AUDIO permission for this, but it
 * only reads the app's own playback.
 */
class VisualizerHandler : EventChannel.StreamHandler {
    private var visualizer: Visualizer? = null
    private val main = Handler(Looper.getMainLooper())
    private val bands = 24
    private val smooth = DoubleArray(bands)

    override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
        release()
        val session = (arguments as? Number)?.toInt() ?: 0
        if (session <= 0) {
            events.error("visualizer", "No audio session yet", null)
            return
        }
        try {
            val v = Visualizer(session)
            v.enabled = false
            v.captureSize = Visualizer.getCaptureSizeRange()[1].coerceAtMost(1024)
            v.setDataCaptureListener(
                object : Visualizer.OnDataCaptureListener {
                    override fun onWaveFormDataCapture(vis: Visualizer?, wave: ByteArray?, rate: Int) {}

                    override fun onFftDataCapture(vis: Visualizer?, fft: ByteArray?, rate: Int) {
                        if (fft == null) return
                        val out = toBands(fft)
                        main.post { events.success(out) }
                    }
                },
                Visualizer.getMaxCaptureRate(),
                false,
                true,
            )
            v.enabled = true
            visualizer = v
        } catch (e: Exception) {
            events.error("visualizer", e.message ?: "Visualizer unavailable", null)
        }
    }

    override fun onCancel(arguments: Any?) = release()

    private fun release() {
        try {
            visualizer?.enabled = false
            visualizer?.release()
        } catch (_: Exception) {
        }
        visualizer = null
        smooth.fill(0.0)
    }

    private fun toBands(fft: ByteArray): DoubleArray {
        val n = fft.size / 2
        if (n < 2) return DoubleArray(bands)
        val mags = DoubleArray(n)
        mags[0] = abs(fft[0].toDouble())
        for (k in 1 until n) {
            mags[k] = hypot(fft[2 * k].toDouble(), fft[2 * k + 1].toDouble())
        }
        val out = DoubleArray(bands)
        for (b in 0 until bands) {
            val lo = n.toDouble().pow(b.toDouble() / bands).toInt().coerceIn(1, n - 1)
            val hi = n.toDouble().pow((b + 1).toDouble() / bands).toInt().coerceIn(lo + 1, n)
            var peak = 0.0
            for (k in lo until hi) peak = max(peak, mags[k])
            val level = (20 * log10(peak + 1.0) / 42.0).coerceIn(0.0, 1.0)
            // Fast attack, slower release so bars look smooth.
            smooth[b] = if (level > smooth[b]) level else smooth[b] * 0.8 + level * 0.2
            out[b] = smooth[b]
        }
        return out
    }
}
