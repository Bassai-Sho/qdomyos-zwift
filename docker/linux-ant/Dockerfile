# =============================================================================
# QDomyos-Zwift Dockerfile (Build + Package Only, Debian Bookworm)
# =============================================================================

FROM debian:bookworm AS builder
ENV DEBIAN_FRONTEND=noninteractive

# -----------------------------------------------------------------------------
# Build-time dependencies only (kept minimal)
# -----------------------------------------------------------------------------
# Qt build deps (headers + qmake)
# Python 3.11 + venv + headers (needed for pybind11)
# USB + UDev for ANT+ broadcaster compilation
# -----------------------------------------------------------------------------
# Install all necessary build dependencies.
# Install all necessary build dependencies.
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    git \
    cmake \
    xvfb \
    patchelf \
    qtbase5-dev \
    qtbase5-private-dev \
    qtchooser \
    qt5-qmake \
    qtbase5-dev-tools \
    qtquickcontrols2-5-dev \
    libqt5bluetooth5 \
    libqt5widgets5 \
    libqt5positioning5 \
    libqt5xml5 \
    qtconnectivity5-dev \
    qtpositioning5-dev \
    libqt5charts5-dev \
    libqt5charts5 \
    libqt5networkauth5-dev \
    libqt5websockets5-dev \
    qtmultimedia5-dev \
    qtlocation5-dev \
    libqt5texttospeech5-dev \
    libxcb-randr0-dev \
    libxcb-xtest0-dev \
    libxcb-xinerama0-dev \
    libxcb-shape0-dev \
    libxcb-xkb-dev \
    libqt5sql5-sqlite \
    libqt5sql5-mysql \
    libqt5sql5-psql \
    # --- Start of Pinned Python Version ---
    python3=3.11.2-1+b1 \
    python3-dev=3.11.2-1+b1 \
    python3-venv=3.11.2-1+b1 \
    # --- End of Pinned Python Version ---
    libusb-1.0-0-dev \
    libudev-dev

# -----------------------------------------------------------------------------
# Create Python venv for ANT+ module
# -----------------------------------------------------------------------------
RUN python3 -m venv /opt/ant_venv && \
    /opt/ant_venv/bin/pip install --quiet --upgrade pip && \
    /opt/ant_venv/bin/pip install --quiet openant pyusb pybind11

# -----------------------------------------------------------------------------
# Copy full QZ source tree
# -----------------------------------------------------------------------------
WORKDIR /app
COPY . .
RUN git submodule update --init --recursive

# --- START OF FINAL FIX: Set Executable Permissions ---
# The build scripts must have the executable bit set to be run by 'make'.
RUN chmod +x src/devices/antlinux/check_ant_env.sh \
             src/devices/antlinux/py_to_header.py
# --- END OF FINAL FIX ---

# -----------------------------------------------------------------------------
# Create .ant_venv_path for plugin + C++ AntWorker
# -----------------------------------------------------------------------------
RUN echo -n "/opt/ant_venv/bin/python3" > /app/src/.ant_venv_path
RUN chmod 644 /app/src/.ant_venv_path

# Diagnostic: Verify the file was created in the right place.
RUN cat /app/src/.ant_venv_path

# -----------------------------------------------------------------------------
# Ensure ANT+ plugin integrated in qmake graph
# -----------------------------------------------------------------------------
#RUN grep -q "antlinux.pri" src/qdomyos-zwift.pro || \
#    echo -e "\n# Enable ANT+ feature\ninclude(devices/antlinux/antlinux.pri)" >> src/qdomyos-zwift.pro

RUN sed -i -e "/^!ios: !android: {/r /dev/stdin" \
           -e "/^!ios: !android: {/,/}/d" \
           qdomyos-zwift.pro <<'EOF'
!ios: !android: {
    SUBDIRS = \
        src/qdomyos-zwift-lib.pro \
        src \
        ant_plugin \
        tst/qdomyos-zwift-tests.pro

    src.file = src/qdomyos-zwift.pro
    ant_plugin.file = src/devices/antlinux/qz_ant_plugin.pro

    src.depends = src/qdomyos-zwift-lib.pro
    ant_plugin.depends = src/qdomyos-zwift-lib.pro
    tst.depends = src/qdomyos-zwift-lib.pro
}
EOF

# -----------------------------------------------------------------------------
# Build application + plugin
# -----------------------------------------------------------------------------
RUN qmake qdomyos-zwift.pro && make -j$(nproc)

# -----------------------------------------------------------------------------
# Stage 2: The Final Artifact Package
# -----------------------------------------------------------------------------
# This stage creates a clean, minimal image containing ONLY the final distributable files.
FROM debian:bookworm-slim

# Create a distribution directory.
WORKDIR /dist

# Copy all three required components from the 'builder' stage into this directory.
# This creates the exact file structure we want in our final .tar.gz.

# 1. Copy the main executable.
COPY --from=builder /app/src/qdomyos-zwift .

# 2. Copy the ANT+ plugin shared library.
COPY --from=builder /app/src/libqz_ant.so .

# 3. Copy the entire Python virtual environment.
COPY --from=builder /opt/ant_venv ./ant_venv

# Add a dummy command to ensure the image is valid for 'docker create'.
CMD ["/bin/true"]