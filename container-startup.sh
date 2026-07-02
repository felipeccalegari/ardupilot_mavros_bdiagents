#!/usr/bin/env bash
set -euo pipefail

LIVE_WS="/opt/ardu_ws_seed"
export START_GZ_GUI="${START_GZ_GUI:-1}"
SITL_PORT="${SITL_PORT:-14540}"

# ── Gazebo resource paths ──────────────────────────────────────────────────────
GZ_SIM_RESOURCE_PATH="$(ros2 pkg prefix ardupilot_gazebo)/share/ardupilot_gazebo/models"
GZ_SIM_RESOURCE_PATH+=":$(ros2 pkg prefix ardupilot_gazebo)/share/ardupilot_gazebo/worlds"
GZ_SIM_RESOURCE_PATH+=":$(ros2 pkg prefix ardupilot_gz_description)/share/ardupilot_gz_description/models"
GZ_SIM_RESOURCE_PATH+=":$(ros2 pkg prefix ardupilot_sitl_models)/share/ardupilot_sitl_models/models"
GZ_SIM_RESOURCE_PATH+=":$(ros2 pkg prefix ardupilot_sitl_models)/share/ardupilot_sitl_models/worlds"
export GZ_SIM_RESOURCE_PATH
export SDF_PATH="${GZ_SIM_RESOURCE_PATH}:${SDF_PATH:-}"
export GZ_SIM_SYSTEM_PLUGIN_PATH=\
"$(ros2 pkg prefix ardupilot_gazebo)/lib/ardupilot_gazebo:${GZ_SIM_SYSTEM_PLUGIN_PATH:-}"
export GZ_IP=127.0.0.1

WORLD_FILE="$(ros2 pkg prefix ardupilot_gazebo)/share/ardupilot_gazebo/worlds/iris_runway.sdf"
DEFAULTS="$(ros2 pkg prefix ardupilot_sitl)/share/ardupilot_sitl/config/default_params/copter.parm"
DEFAULTS+=",$(ros2 pkg prefix ardupilot_gazebo)/share/ardupilot_gazebo/config/gazebo-iris-gimbal.parm"
ARDUCOPTER_BIN="$(ros2 pkg prefix ardupilot_sitl)/bin/arducopter"

echo
echo "============================================"
echo " ArduPilot ROS 2 / Gazebo container ready"
echo "============================================"
echo "  Workspace : ${LIVE_WS}"
echo "  ROS distro: ${ROS_DISTRO}"
echo "  Gazebo    : ${GZ_VERSION}"
echo "  World     : ${WORLD_FILE}"
echo; java -version 2>&1 || true; echo

# ── Cleanup trap ───────────────────────────────────────────────────────────────
CRITICAL_PIDS=()
cleanup() {
    echo "[shutdown] Stopping all processes..."
    kill "${CRITICAL_PIDS[@]}" "${GZ_GUI_PID:-}" 2>/dev/null || true
    exit 0
}
trap cleanup EXIT INT TERM

# ── Poll until Gazebo Transport advertises services ────────────────────────────
wait_for_gz_server() {
    local max_wait=120
    local waited=0
    echo "[gz-server] Waiting for Gazebo Transport..."
    while [ "${waited}" -lt "${max_wait}" ]; do
        if gz service -l 2>/dev/null | grep -q "^/gazebo"; then
            echo "[gz-server] Ready after ${waited}s."
            return 0
        fi
        sleep 2
        waited=$((waited + 2))
    done
    echo "[gz-server] WARNING: not detected after ${max_wait}s — continuing anyway."
    return 0
}

# ── 1. Gazebo server (CRITICAL) ────────────────────────────────────────────────
echo "[1/4] Starting Gazebo server..."
gz sim -v4 -s -r "${WORLD_FILE}" --render-engine ogre &
GZ_SERVER_PID=$!
CRITICAL_PIDS+=("${GZ_SERVER_PID}")
wait_for_gz_server

# ── 2. Gazebo GUI (optional, non-critical) ─────────────────────────────────────
if [ "${START_GZ_GUI}" = "1" ]; then
    echo "[2/4] Starting Gazebo GUI..."
    gz sim -v4 -g --render-engine ogre &
    GZ_GUI_PID=$!
    sleep 3
else
    echo "[2/4] Gazebo GUI disabled (START_GZ_GUI=${START_GZ_GUI})"
fi

# ── 3. ArduPilot SITL (CRITICAL) ──────────────────────────────────────────────
# SERIAL0 is reserved for MAVProxy/QGC; SERIAL1 is the dedicated MAVROS link.
echo "[3/4] Starting ArduPilot SITL..."
"${ARDUCOPTER_BIN}" \
        --model json \
        --speedup 1 \
        --slave 0 \
        --serial1="tcp:${SITL_PORT}" \
        --sim-address=127.0.0.1 \
        --instance 0 \
        --defaults "${DEFAULTS}" \
    --synthetic-clock \
    --sysid 1 &
SITL_PID=$!
CRITICAL_PIDS+=("${SITL_PID}")
sleep 4

# ── 4. MAVProxy watchdog (CRITICAL) ───────────────────────────────────────────
# Owns TCP 5760 (SERIAL0) exclusively — forwards to GCS endpoints.
echo "[4/4] Starting MAVProxy..."
mavproxy_watchdog() {
    while true; do
        mavproxy.py \
            --master tcp:127.0.0.1:5760 \
            --sitl 127.0.0.1:5501 \
            --out udp:127.0.0.1:14550 \
            --out udp:127.0.0.1:14551 \
            --non-interactive || true
        if ! kill -0 "${SITL_PID}" 2>/dev/null; then
            echo "[mavproxy] SITL is down — stopping watchdog."
            break
        fi
        echo "[mavproxy] MAVProxy exited — restarting in 5s..."
        sleep 5
    done
}
mavproxy_watchdog &
MAVPROXY_PID=$!
CRITICAL_PIDS+=("${MAVPROXY_PID}")

echo
echo "[ready] All processes launched. Monitoring critical processes..."
echo "        Server=${GZ_SERVER_PID}  SITL=${SITL_PID}  MAVProxy=${MAVPROXY_PID}"
echo
echo "  Port layout:"
echo "    TCP  5760 → SERIAL0 → MAVProxy"
echo "    TCP  ${SITL_PORT} → SERIAL1 direct to MAVROS"
echo "    UDP  14550/14551 → MAVProxy GCS fanout"
echo "    TCP  5762/5763 → SITL side ports (unused by MAVROS)"
echo "    UDP  5501 → SITL sensor input"
echo "    GUI start mode: START_GZ_GUI=${START_GZ_GUI}"
echo

# ── Monitor: exit only if a critical process dies ─────────────────────────────
while true; do
    for pid in "${CRITICAL_PIDS[@]}"; do
        if ! kill -0 "${pid}" 2>/dev/null; then
            echo "[monitor] Critical PID=${pid} exited. Shutting down."
            exit 1
        fi
    done
    sleep 5
done
