# ArduPilot + MAVROS + Jason Agents in Docker

This repository provides a Docker-based ArduPilot simulation stack for developing
and testing MAVROS-connected Jason BDI agents.

The main idea is to run the robotics side in containers:

- Gazebo Harmonic + ArduPilot SITL + MAVProxy in one container
- MAVROS 2 + rosbridge websocket in a second container
- Jason agents from `Agents/tmp_repo/Agents/Mavros`, connected through
  rosbridge and MAVROS services/topics

The stack is built around ROS 2 Humble, Gazebo Harmonic, ArduPilot SITL, MAVROS,
rosbridge, Java 21, and Gradle.

## Repository Layout

```text
.
|-- Dockerfile
|-- docker-compose.yml
|-- container-startup.sh
|-- start-mavros.sh
`-- Agents/
    `-- tmp_repo/Agents/Mavros/
        |-- build.gradle
        |-- gradlew
        |-- perception_action.jcm
        `-- src/agt/sample_agent.asl
```

## Build the Docker Image

From the repository root:

```bash
cd /home/felipe/tmp1/ardupilot_mavros_docker
docker compose build
```


## Start the Containers

Allow Docker containers to use the host X11 display:

```bash
xhost +local:docker
```

Then start the full stack:

```bash
docker compose up -d
```

This starts two containers:

```text
ardupilot_humble_gz   ->   Gazebo, ArduPilot SITL, MAVProxy
ardupilot_humble_mavros -> MAVROS 2, rosbridge websocket
```

## Check Logs

Gazebo/SITL/MAVProxy:

```bash
docker compose logs -f ardupilot_humble_gz
```

MAVROS/rosbridge:

```bash
docker compose logs -f mavros
```

## Open Shells in the Containers

Use the Gazebo/SITL container for simulator-side commands:

```bash
docker exec -it ardupilot_humble_gz bash
```

Use the MAVROS container for ROS 2, MAVROS, rosbridge, and agent commands:

```bash
docker exec -it ardupilot_humble_mavros bash
```

The repository's `Agents/` directory is mounted at `/Agents` in both containers.

## Using MAVROS Commands

Run MAVROS commands inside the MAVROS container:

```bash
docker exec -it ardupilot_humble_mavros bash
```

Useful checks:

```bash
ros2 node list
ros2 topic list | grep mavros
ros2 service list | grep mavros
ros2 topic echo /mavros/state
ros2 topic echo /mavros/local_position/pose
```
* It's recommended to wait ~40-50 seconds before testing any command due to Ardupilot/MAVROS initialization.

Typical control sequence:

```bash
ros2 service call /mavros/set_mode mavros_msgs/srv/SetMode \
  "{base_mode: 0, custom_mode: 'GUIDED'}"

ros2 service call /mavros/cmd/arming mavros_msgs/srv/CommandBool \
  "{value: true}"

ros2 service call /mavros/cmd/takeoff mavros_msgs/srv/CommandTOL \
  "{min_pitch: 0.0, yaw: 0.0, latitude: 0.0, longitude: 0.0, altitude: 3.0}"
```

Land the vehicle:

```bash
ros2 service call /mavros/set_mode mavros_msgs/srv/SetMode \
  "{base_mode: 0, custom_mode: 'LAND'}"
```

MAVROS connects directly to ArduPilot SITL through TCP port `14540`.
MAVProxy owns the separate GCS fanout and publishes UDP outputs on `14550` and
`14551`.

## Running the Agents

The agent project is here:

```bash
/Agents/tmp_repo/Agents/Mavros
```

Run it from the MAVROS container, after the stack is up and MAVROS/rosbridge are
running:

```bash
docker exec -it ardupilot_humble_mavros bash
cd /Agents/tmp_repo/Agents/Mavros
./gradlew run
```
* Additionally, if ```./gradlew run``` won't work directly, try ```chmod +x gradlew``` command in the ```/Agents/tmp_repo/Agents/Mavros``` directory, and then proceed to run the agents.


The default Gradle task launches:

```text
perception_action.jcm
```

That JCM starts `sample_agent`, whose source is:

```text
src/agt/sample_agent.asl
```

The agent is configured by:

```text
src/agt/sample_agent.yaml
```

The YAML maps MAVROS topics into beliefs, including:

- `/mavros/state`
- `/mavros/battery`
- `/mavros/rc/in`
- `/mavros/local_position/pose`
- `/mavros/global_position/global`
- `/mavros/param/event`

It also maps agent actions to MAVROS services, including:

- `arming` -> `/mavros/cmd/arming`
- `takeoff_cmd` -> `/mavros/cmd/takeoff`
- `set_mode` -> `/mavros/set_mode`
- `mission_clear` -> `/mavros/mission/clear`
- `mission_set_current` -> `/mavros/mission/set_current`
- `set_stream_rate` -> `/mavros/set_stream_rate`
- `set_message_interval` -> `/mavros/set_message_interval`

The current `sample_agent.asl` contains a GUIDED-mode body-relative movement
demo. It switches to GUIDED, arms, takes off, sends local setpoints, and then
lands.

## Ports and Connections

Important runtime connections:

```text
TCP 14540   ArduPilot SITL SERIAL1, used directly by MAVROS
TCP 5760    ArduPilot SITL SERIAL0, used by MAVProxy
UDP 14550   MAVProxy GCS output
UDP 14551   MAVProxy GCS output
TCP 9090    rosbridge websocket
```

The agent YAML uses:

```text
ws://localhost:9090
```

Because the containers use host networking, this works from the MAVROS
container.

## Useful Maintenance Commands

Stop the stack:

```bash
docker compose down
```

Restart only MAVROS/rosbridge:

```bash
docker compose restart mavros
```

Restart the simulator stack:

```bash
docker compose restart ardupilot_humble_gz mavros
```

Check container status:

```bash
docker compose ps
```

## Notes

- Use `ardupilot_humble_gz` for Gazebo, SITL, and MAVProxy debugging.
- Use `ardupilot_humble_mavros` for `ros2`, MAVROS service/topic commands,
  rosbridge checks, and `./gradlew run`.
- MAVROS waits for SITL and then delays startup using `STABILIZE_SECS`, default
  `40`, before launching - delay was necessary otherwise system wouldn't launch properly.
- rosbridge is exposed on port `9090`.
- Java 21 is installed in the image for the Jason agent project.
