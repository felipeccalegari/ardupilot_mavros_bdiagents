#!/usr/bin/env bash
set -euo pipefail

SITL_HOST="${SITL_HOST:-127.0.0.1}"
SITL_PORT="${SITL_PORT:-14540}"
STABILIZE_SECS="${STABILIZE_SECS:-40}"
FCU_URL="tcp://${SITL_HOST}:${SITL_PORT}"
ROSBRIDGE_WS_PORT="${ROSBRIDGE_WS_PORT:-9090}"

rosbridge_pid=""
mavros_pid=""

cleanup() {
    if [[ -n "${mavros_pid}" ]] && kill -0 "${mavros_pid}" 2>/dev/null; then
        kill "${mavros_pid}" 2>/dev/null || true
        wait "${mavros_pid}" 2>/dev/null || true
    fi

    if [[ -n "${rosbridge_pid}" ]] && kill -0 "${rosbridge_pid}" 2>/dev/null; then
        kill "${rosbridge_pid}" 2>/dev/null || true
        wait "${rosbridge_pid}" 2>/dev/null || true
    fi
}

trap cleanup EXIT INT TERM

echo "[mavros] Waiting for direct SITL TCP listener on ${SITL_HOST}:${SITL_PORT}..."
until nc -z "${SITL_HOST}" "${SITL_PORT}" 2>/dev/null; do
    echo "[mavros]   ...not yet, retrying in 2s"
    sleep 2
done

echo "[mavros] Direct SITL TCP listener is up — waiting ${STABILIZE_SECS}s for SITL/Gazebo to settle..."
sleep "${STABILIZE_SECS}"

cat <<EOF
[mavros] Starting MAVROS on direct SITL TCP feed...

  FCU URL : ${FCU_URL}  (direct SITL SERIAL1 feed)
  GCS URL : disabled (MAVProxy owns the GCS fanout on SERIAL0)
  Delay   : ${STABILIZE_SECS}s stabilization wait

EOF

cat <<EOF
[rosbridge] Starting rosbridge_websocket on port ${ROSBRIDGE_WS_PORT}...
EOF

ros2 launch rosbridge_server rosbridge_websocket_launch.xml \
    call_services_in_new_thread:=true \
    default_call_service_timeout:=10.0 \
    port:="${ROSBRIDGE_WS_PORT}" &
rosbridge_pid=$!

ros2 run mavros mavros_node --ros-args \
    -p fcu_url:="${FCU_URL}" \
    -p system_id:=255 \
    -p component_id:=240 \
    -p target_system_id:=1 \
    -p target_component_id:=1 &
mavros_pid=$!

wait -n "${rosbridge_pid}" "${mavros_pid}"
