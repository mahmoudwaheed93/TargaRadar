# Continuous Audio-Stream Engine Evaluation (`SpeechPlatformService`)

## 1. Architecture Readiness
`SpeechPlatformService` (`lib/core/services/speech_to_text_service_interface.dart`) now exposes `SpeechEngineType` (`platformRecognizer` vs `continuousAudioStream`), allowing a direct PCM stream implementation (e.g., Sherpa-ONNX / Vosk / Deepgram WebSocket) to be swapped in behind the same `SpeechService` contract without modifying UI or providers.

## 2. Trade-Off Analysis (Egyptian/Arabic License Plates)

| Criterion | OS `SpeechRecognizer` (`speech_to_text`) — Current | Continuous PCM Stream (Local ONNX/Whisper or Cloud WS) |
|---|---|---|
| **Session Restart Gap** | Eliminated to ~0ms state-machine restart + muted system beep; cross-session fragments bridged by `PlateUtteranceStitcher`. | Zero OS session restarts (native continuous PCM frames). |
| **Egyptian & Multi-Dialect Accuracy** | High (`ar_EG`, `ar_SA`, `ar_AE` acoustic models trained natively on colloquial spoken letters & numbers). | Offline open models (Vosk/Whisper-tiny/small) drop short glottal Arabic letters (`أ`, `ع`, `هـ`) heavily without GPU/NPU quantization; Cloud WS (Deepgram/Soniox) adds latency & per-minute API fees. |
| **On-Device Offline Speed** | ~60–150ms when Android/iOS offline `ar` pack is downloaded (`SpeechListenOptions.onDevice = true`). | ~80–250ms local CPU inference, ~35–120MB extra APK/model footprint. |
| **Cost & Stability** | Zero marginal ASR cost, zero native C++ ABI / AGP 9.0.1 CMake build risk. | Paid API cost (Cloud WS) or heavy NDK/CMake maintenance (local ONNX). |

## 3. Recommendation
Keep OS `platformRecognizer` (`onDevice: true` default + automatic Cloud fallback) paired with `0ms` deduplicated restart scheduling, Android beep suppression, `AudioFocus.none` alarms, and `PlateUtteranceStitcher`, while keeping `SpeechEngineType` ready if dedicated streaming hardware/models are adopted later.
