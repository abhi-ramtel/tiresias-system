Server Configuration

Environment variables:

- `TIRESIAS_FAST_FPS` (default: 12): Fast lane inference target FPS.
- `TIRESIAS_SLOW_INTERVAL_S` (default: 1.5): Slow lane analysis interval in seconds.
- `TIRESIAS_CRITICAL_DISTANCE_M` (default: 2.0): Critical distance for fast-lane alerts.
- `TIRESIAS_RING_SECONDS` (default: 5): Ring buffer duration in seconds.
- `TIRESIAS_RING_FPS` (default: 15): Expected capture FPS for ring buffer sizing.
- `TIRESIAS_GEOCODE` (default: 0): Set to 1 to enable reverse geocoding.
- `TIRESIAS_USE_YOLOV10` (default: 0): Set to 1 to use `yolov10n.pt` if available.
- `TIRESIAS_FAST_MODEL`: Override fast lane model path (e.g., `yolov8n.pt`).
- `TIRESIAS_NAV_MODEL`: Override slow lane model path (e.g., `yolov8s.pt`).

WebSocket control messages:

- `{ "type": "thermal", "state": "hot" }` lowers fast FPS and slows slow-lane cadence.
- `{ "type": "thermal", "state": "nominal" }` restores default rates.
- `{ "type": "system", "fast_fps": 8, "slow_interval_s": 2.5 }` overrides lane rates at runtime.

Endpoints:

- `GET /health` Basic health check.
- `GET /stats` Server stats.
- `GET /frame` Latest annotated frame.
- `GET /replay/info` Ring buffer status.
- `GET /replay/latest` Latest raw frame from ring buffer.
- `GET /replay/analyse` Analyse latest ring buffer frame.
