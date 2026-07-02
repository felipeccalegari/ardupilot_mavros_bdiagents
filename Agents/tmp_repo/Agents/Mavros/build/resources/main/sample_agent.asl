/* ArduPilot example 1: GUIDED takeoff, wait 20 s, then land. */
/* !demo_ardupilot_takeoff_wait_land.

+!demo_ardupilot_takeoff_wait_land
  <-
    .print("ArduPilot demo: switch to GUIDED, arm, take off, wait, and land.");
    .set_mode("GUIDED");
    .wait(1000);
    .arming(true);
    .wait(1500);
    .takeoff_cmd(0.0, 0.0, 0.0, 0.0, 3.0);
    .print("Takeoff command sent to 3m.");
    .wait(20000);
    .set_mode("LAND");
    .print("LAND mode requested."). */

/* End of ArduPilot example 1. */

/* ArduPilot example 2: Perception examples.
   Local MAVLink equivalent:
     LOCAL_POSITION_NED -> MAVROS /mavros/local_position/pose -> belief position(...)
   Global MAVLink equivalent:
     GLOBAL_POSITION_INT -> usually a MAVROS global-position topic, which can be
     mapped to a belief such as global_position(...) if added in sample_agent.yaml.
*/

/* Existing local-position perception already available in this agent.
   This one reacts to the MAVROS local pose belief configured in sample_agent.yaml. */
/*+nav_pose_local(pose(position(x(X), y(Y), z(Z)),
                 orientation(x(QX), y(QY), z(QZ), w(QW))))
  <-
    .print("Local pose from MAVROS (/mavros/local_position/pose): ",
           "x=", X, ", y=", Y, ", z=", Z,
           ", qx=", QX, ", qy=", QY, ", qz=", QZ, ", qw=", QW).*/

/* Example if you later add a global-position belief in sample_agent.yaml.
   One common MAVROS source is /mavros/global_position/global. */
/*+global_position(latitude(Lat), longitude(Lon), altitude(Alt))
  <-
    .print("Global position (GLOBAL_POSITION_INT equivalent): ",
           "lat=", Lat, ", lon=", Lon, ", alt=", Alt).*/

/* Optional helper if you want to explicitly request MAVROS position streams first.
   STREAM_POSITION = 6 in mavros_msgs/srv/StreamRate. */
/* !request_position_streams.

+!request_position_streams
  <-
    .set_stream_rate(6, 5, true);
    .print("Requested MAVROS STREAM_POSITION at 5 Hz."). */

/* End of ArduPilot example 2. */

/* ArduPilot example 3: High-level GUIDED body-relative repositioning.
   The helper .setpoint_local(Forward, Right, Up) computes an absolute local
   target from /mavros/local_position/pose. The raw setpoint ignores yaw, while
   WP_YAW_BEHAVIOR=0 asks ArduPilot to keep the current heading.
   ArduPilot still wants an explicit takeoff command before repositioning from the ground. */
!demo_ardupilot_guided_body_relative_position.

+!demo_ardupilot_guided_body_relative_position
  <-
    .nano_time(T1);
    .print("Time1: ", T1);
    .print("ArduPilot GUIDED - using local setpoint_local(Forward, Right, Up) with heading hold.");
    .set_stream_rate(6, 5, true);
    .print("Requested MAVROS STREAM_POSITION at 5 Hz.");
    .wait(2000);
    .set_mode("GUIDED");
    .wait(1000);
    .arming(true);
    .wait(3000);

    // Explicit takeoff first. Use zeroed lat/lon params as in the working ArduPilot service flow.
    .takeoff_cmd(0.0, 0.0, 0.0, 0.0, 2.0);
    .print("Takeoff command sent to 2.0 m.");
    .reset_setpoint_local_reference;
    .print("Locked setpoint_local reference yaw after takeoff.");
    .wait(15000);

    .print("Command: move 2 m forward.");
    .setpoint_local(2.0, 0.0, 0.0);
    .wait(10000);

    .print("Command: move 2 m backward to return.");
    .setpoint_local(-2.0, 0.0, 0.0);
    .wait(10000);

    .print("Command: move 2 m right.");
    .setpoint_local(0.0, 2.0, 0.0);
    .wait(10000);

    .print("Command: move 2 m left to return.");
    .setpoint_local(0.0, -2.0, 0.0);
    .wait(10000);

    .print("Command: move 2 m left.");
    .setpoint_local(0.0, -2.0, 0.0);
    .wait(10000);

    .print("Command: move 2 m right to return.");
    .setpoint_local(0.0, 2.0, 0.0);
    .wait(10000);

    .print("Command: move 2 m backward.");
    .setpoint_local(-2.0, 0.0, 0.0);
    .wait(10000);

    .print("Command: move 2 m forward to return.");
    .setpoint_local(2.0, 0.0, 0.0);
    .wait(10000);

    .set_mode("LAND");
    .wait(200);
    .nano_time(T2);
    .print("Time2: ", T2);
    .print("LAND mode requested to finish GUIDED demo.").

/* End of ArduPilot example 3. */

/* MAVROS local position monitor: prints /mavros/local_position/pose at most every 3 seconds. */
lp_print_gap_ns(3000000000).
last_lp_print_ns(0).

+nav_pose_local(pose(position(x(X), y(Y), z(Z)),
                 orientation(x(QX), y(QY), z(QZ), w(QW))))
  : lp_print_gap_ns(Gap) & last_lp_print_ns(Last)
  <-
    .nano_time(Now);
    if (Now - Last >= Gap) {
      -last_lp_print_ns(_);
      +last_lp_print_ns(Now);
      .print("[MAVROS_LOCAL_POSITION] x=", X, " y=", Y, " z=", Z,
             " qx=", QX, " qy=", QY, " qz=", QZ, " qw=", QW)
    }.
/* End of MAVROS local position monitor. */
