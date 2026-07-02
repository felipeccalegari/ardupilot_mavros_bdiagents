FROM osrf/ros:humble-desktop

# ── Environment ────────────────────────────────────────────────────────────────
ENV DEBIAN_FRONTEND=noninteractive
ENV LANG=en_US.UTF-8
ENV LC_ALL=en_US.UTF-8
ENV ROS_DISTRO=humble
ENV GZ_VERSION=harmonic
ENV JAVA_HOME=/usr/lib/jvm/temurin-21-jdk-amd64
ENV PATH=/usr/lib/ccache:${PATH}

SHELL ["/bin/bash", "-lc"]

# ── Base locale + bootstrap tools ─────────────────────────────────────────────
RUN apt-get update && apt-get install -y --no-install-recommends \
        locales \
        curl \
        ca-certificates \
        gnupg \
        lsb-release \
        wget \
        sudo \
        software-properties-common \
    && locale-gen en_US.UTF-8 \
    && rm -rf /var/lib/apt/lists/*

# ── Adoptium (Temurin) repository — Java 21 ───────────────────────────────────
RUN mkdir -p /etc/apt/keyrings \
    && wget -qO - https://packages.adoptium.net/artifactory/api/gpg/key/public \
       | gpg --dearmor -o /etc/apt/keyrings/adoptium.gpg \
    && echo "deb [signed-by=/etc/apt/keyrings/adoptium.gpg] \
       https://packages.adoptium.net/artifactory/deb \
       $(lsb_release -cs) main" \
       > /etc/apt/sources.list.d/adoptium.list

# ── Gazebo Harmonic + OSRF rosdep source ──────────────────────────────────────
RUN wget -qO /usr/share/keyrings/pkgs-osrf-archive-keyring.gpg \
        https://packages.osrfoundation.org/gazebo.gpg \
    && echo "deb [arch=$(dpkg --print-architecture) \
       signed-by=/usr/share/keyrings/pkgs-osrf-archive-keyring.gpg] \
       http://packages.osrfoundation.org/gazebo/ubuntu-stable \
       $(lsb_release -cs) main" \
       > /etc/apt/sources.list.d/gazebo-stable.list \
    && mkdir -p /etc/ros/rosdep/sources.list.d \
    && wget -qO /etc/ros/rosdep/sources.list.d/00-gazebo.list \
       https://raw.githubusercontent.com/osrf/osrf-rosdep/master/gz/00-gazebo.list

# ── Main package installation ──────────────────────────────────────────────────
RUN apt-get update && apt-get install -y --no-install-recommends \
        # Version control & editors
        git \
        vim \
        nano \
        tmux \
        # Network / debug utils
        socat \
        jq \
        lsof \
        iproute2 \
        netcat-openbsd \
        tcpdump \
        # GUI / X11 / OpenGL
        x11-apps \
        mesa-utils \
        libgl1-mesa-dri \
        libgl1-mesa-glx \
        libxcb-xinerama0 \
        libxkbcommon-x11-0 \
        libxcb-cursor0 \
        # Build tools
        build-essential \
        ccache \
        g++ \
        gdb \
        gawk \
        make \
        cmake \
        ninja-build \
        libtool \
        libtool-bin \
        zip \
        # Python
        python3-pip \
        python3-vcstool \
        python3-rosdep \
        python3-colcon-common-extensions \
        python3-numpy \
        python3-pyparsing \
        python3-serial \
        python3-empy \
        python3-jinja2 \
        python-is-python3 \
        # ROS 2 dev tools
        ros-dev-tools \
        # Java 21 (Temurin — must match JAVA_HOME env above)
        temurin-21-jdk \
        # Gazebo Harmonic + ROS bridge
        gz-harmonic \
        ros-humble-ros-gzharmonic \
        # MAVROS
        ros-humble-mavros \
        ros-humble-mavros-extras \
        ros-humble-rosbridge-server \
        geographiclib-tools \
        # rqt console (+ core rqt framework)
        ros-humble-rqt \
        ros-humble-rqt-common-plugins \
        ros-humble-rqt-console \
    && rm -rf /var/lib/apt/lists/*

# ── Python packages ────────────────────────────────────────────────────────────
RUN python3 -m pip install --no-cache-dir -U \
        wheel \
        future \
        lxml \
        pexpect \
        flake8 \
        "empy==3.3.4" \
        pyelftools \
        tabulate \
        pymavlink \
        websocket-client \
        MAVProxy \
        pre-commit \
        junitparser

# ── rosdep bootstrap ───────────────────────────────────────────────────────────
RUN rosdep init || true

# ── GeographicLib datasets (required by MAVROS) ────────────────────────────────
RUN /opt/ros/humble/lib/mavros/install_geographiclib_datasets.sh

# ── Clone & seed ArduPilot + Gazebo ROS 2 workspace ──────────────────────────
RUN mkdir -p /opt/ardu_ws_seed/src /workspaces/ardu_ws \
    && cd /opt/ardu_ws_seed \
    && vcs import --recursive --input \
       https://raw.githubusercontent.com/ArduPilot/ardupilot_gz/main/ros2_gz.repos src \
    && find src/ardupilot_gazebo/models -name model.sdf -print0 \
       | xargs -0 sed -i 's|package://ardupilot_gazebo/models/|model://|g'

# ── rosdep install + colcon build ─────────────────────────────────────────────
RUN source /opt/ros/humble/setup.bash \
    && cd /opt/ardu_ws_seed \
    && rosdep update \
    && apt-get update \
    && rosdep install --rosdistro "${ROS_DISTRO}" \
       --from-paths src --ignore-src -r -y \
    && colcon build \
       --packages-up-to ardupilot_sitl \
       --cmake-args -DARDUPILOT_ENABLE_DDS=OFF \
    && colcon build \
       --packages-up-to ardupilot_gz_bringup \
    && rm -rf /var/lib/apt/lists/*

# ── Seed workspace into working location ──────────────────────────────────────
RUN cp -a /opt/ardu_ws_seed/. /workspaces/ardu_ws/

# ── Shell environment for all shell sessions ──────────────────────────────────
RUN cat <<'EOF' >/etc/profile.d/ardupilot_env.sh
export GZ_VERSION=harmonic
export JAVA_HOME=/usr/lib/jvm/temurin-21-jdk-amd64
export PATH=/usr/lib/ccache:${PATH}
export ROS_LOCALHOST_ONLY=0

source /opt/ros/humble/setup.bash

if [ -f /workspaces/ardu_ws/install/setup.bash ]; then
    source /workspaces/ardu_ws/install/setup.bash
elif [ -f /opt/ardu_ws_seed/install/setup.bash ]; then
    source /opt/ardu_ws_seed/install/setup.bash
fi
EOF

ENV BASH_ENV=/etc/profile.d/ardupilot_env.sh

RUN echo "source /etc/profile.d/ardupilot_env.sh" >> /root/.bashrc \
    && echo "source /etc/profile.d/ardupilot_env.sh" >> /root/.profile

# ── Entry-point scripts ───────────────────────────────────────────────────────
COPY container-startup.sh /usr/local/bin/container-startup.sh
COPY start-mavros.sh      /usr/local/bin/start-mavros.sh
RUN chmod +x /usr/local/bin/container-startup.sh \
             /usr/local/bin/start-mavros.sh

# ── Agents volume mount-point (must exist inside the image) ───────────────────
RUN mkdir -p /Agents

WORKDIR /workspaces/ardu_ws

CMD ["/usr/local/bin/container-startup.sh"]
