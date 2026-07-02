# ArduPilot SITL + MAVROS 2 Humble + Gazebo (Container)

This container is set up for the workflow you asked for:

- ROS 2 Humble
- Gazebo Harmonic
- ArduPilot SITL
- MAVROS 2
- `git`
- Java 21

## Compatibility review

After reviewing the official docs, there are two different integration paths that are easy to mix up:

1. ArduPilot ROS 2 + Gazebo documentation is centered on the ArduPilot DDS / micro-ROS path.
2. MAVROS is the MAVLink bridge path.

Those are compatible ideas, but they are not the same stack.

The important result for this container is:

- ArduPilot officially supports ROS 2 Humble.
- ArduPilot's Gazebo guide recommends Gazebo Harmonic.
- Gazebo's own docs say Humble + Harmonic is a non-default pairing and should be treated as an advanced setup.
- MAVROS on Humble is supported.
- The ArduPilot Gazebo bringup code contains a non-DDS path using `use_dds_agent:=False`, which is the cleaner fit for a MAVROS-first workflow.

Because of that, this setup is intentionally biased toward:

- building the ArduPilot Gazebo workspace during `docker compose build`,
- disabling DDS for the `ardupilot_sitl` build,
- launching native `ardupilot_gazebo` server + GUI + SITL when the container starts,
- and starting MAVROS plus rosbridge automatically in a second compose service over MAVLink/UDP.

That avoids forcing `Micro-XRCE-DDS-Gen` into the image just to support a workflow you did not ask for.

## Why the earlier build failed

The earlier Dockerfile tried to compile `Micro-XRCE-DDS-Gen` from source inside the image. That pulled in a separate Java / Gradle compatibility problem unrelated to MAVROS itself.

For a MAVROS-based setup, that dependency is unnecessary noise, so it has been removed from the default container path.

## Host assumptions

This is aimed at a Linux host with Docker Engine and X11.

For GUI access:

```bash
xhost +local:docker
```

## Build

```bash
cd /home/felipe/tmp1/ardupilot_mavros_docker
docker compose build
```

## Start the stack

```bash
docker compose up -d
```

This starts:

- `ardupilot_humble_gz`: Gazebo server, Gazebo GUI, ArduPilot SITL, MAVProxy
- `ardupilot_humble_mavros`: MAVROS 2 and rosbridge websocket

## Verify basics

```bash
docker exec -it ardupilot_humble_gz bash
```

Then inside:

```bash
java -version
git --version
gz sim --version
ros2 pkg list | grep mavros
```

## Logs

```bash
docker compose logs -f ardupilot_humble_gz
docker compose logs -f mavros
```

## Shell access

Gazebo / SITL container:

```bash
docker exec -it ardupilot_humble_gz bash
```

MAVROS container:

```bash
docker exec -it ardupilot_humble_mavros bash
```

Rosbridge websocket in the merged MAVROS container is exposed on host port `9090` by default.

## What Docker now does automatically

During image build:

- imports the `ardupilot_gz` workspace
- runs `rosdep install`
- builds `ardupilot_sitl` with `-DARDUPILOT_ENABLE_DDS=OFF`
- builds `ardupilot_gz_bringup`

During `docker compose up`:

- launches `gz sim -v4 -s -r iris_runway.sdf`
- launches `gz sim -v4 -g`
- launches `arducopter --model json ...`
- launches MAVProxy with UDP output on `14550`
- launches `mavros_node` and `rosbridge_websocket` in a companion service

## Notes

- If you want the ArduPilot DDS / micro-ROS path later, that is a separate setup concern from MAVROS.
- The ArduPilot docs do provide a Docker route for the DDS-oriented ROS environment, but the main Linux build docs still caution that Docker is not their preferred path for graphical SITL unless you add graphics plumbing.
- This container already includes the graphics plumbing needed for Gazebo GUI on a Linux desktop.

## Sources

- ArduPilot ROS 2 install: https://ardupilot.org/dev/docs/ros2.html
- ArduPilot ROS 2 with SITL: https://ardupilot.org/dev/docs/ros2-sitl.html
- ArduPilot ROS 2 with Gazebo: https://ardupilot.org/dev/docs/ros2-gazebo.html
- ArduPilot Linux build environment / Docker note: https://ardupilot.org/dev/docs/building-setup-linux.html
- Official ArduPilot ROS Dockerfile repo: https://github.com/ArduPilot/ardupilot_dev_docker
- `ardupilot_gz` repo: https://github.com/ArduPilot/ardupilot_gz
- Gazebo Harmonic + ROS compatibility: https://gazebosim.org/docs/harmonic/ros_installation/
- MAVROS Humble docs: https://docs.ros.org/en/humble/p/mavros/
