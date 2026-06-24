FROM nvidia/cuda:12.6.3-devel-ubuntu24.04

# Prevent interactive prompts
ENV DEBIAN_FRONTEND=noninteractive
ENV CUDA_HOME=/usr/local/cuda \
    NVIDIA_VISIBLE_DEVICES=all \
    NVIDIA_DRIVER_CAPABILITIES=all \
    PATH=/usr/local/cuda/bin:${PATH} \
    LD_LIBRARY_PATH=/usr/local/cuda/lib64:${LD_LIBRARY_PATH}

# Build-time arguments (all configured in docker-compose.yml)
ARG USERNAME=ereshkigal
ARG PASSWORD=ereshkigal

# Install the default Ubuntu desktop session, xrdp, and CUDA development helpers.
# xorgxrdp provides the virtual Xorg backend used by mstsc and Guacamole.
RUN apt-get -o Acquire::Retries=5 update && \
    apt-get -o Acquire::Retries=5 install -y \
    build-essential \
    ca-certificates \
    cmake \
    curl \
    git \
    kmod \
    pciutils \
    pkg-config \
    python3 \
    python3-pip \
    python3-venv \
    mesa-utils \
    ubuntu-desktop-minimal \
    xrdp \
    xorgxrdp \
    gnome-session \
    ubuntu-session \
    dbus-x11 \
    x11-xserver-utils \
    sudo \
    && rm -rf /var/lib/apt/lists/*

RUN apt-get -o Acquire::Retries=5 update && \
    apt-get -o Acquire::Retries=5 install -y openssh-server && \
    rm -rf /var/lib/apt/lists/*

RUN cat <<'EOF' > /etc/ssh/sshd_config.d/99-container-bind-home.conf
PasswordAuthentication yes
PubkeyAuthentication yes
StrictModes no
EOF

ENV NVIDIA_DRIVER_CAPABILITIES=all

ENV CONTAINER_USER=${USERNAME}

# Avoid negotiating 32 bpp remote sessions. GNOME over xorgxrdp renders through
# a virtual Xorg display, so every extra byte per pixel costs responsiveness.
RUN sed -i \
    -e 's/^max_bpp=.*/max_bpp=24/' \
    -e 's/^allow_multimon=.*/allow_multimon=false/' \
    -e '/^\[Xorg\]/,/^\[/ s/^code=20$/code=20\nxserverbpp=24/' \
    /etc/xrdp/xrdp.ini

# Create the non‑root user with the specified password
RUN useradd -m -s /bin/bash ${USERNAME} && \
    echo "${USERNAME}:${PASSWORD}" | chpasswd && \
    usermod -aG sudo ${USERNAME}

ARG VSCODE_SERVER_COMMIT=fcf604774b9f2674b473065736ee75077e256353
ARG VSCODE_SERVER_QUALITY=stable

ENV VSCODE_SERVER_COMMIT=${VSCODE_SERVER_COMMIT} \
    VSCODE_SERVER_QUALITY=${VSCODE_SERVER_QUALITY}

RUN install -d -m 755 "/opt/vscode-server/${VSCODE_SERVER_COMMIT}" && \
    curl -fsSL --retry 5 --retry-delay 2 --retry-all-errors \
        "https://update.code.visualstudio.com/commit:${VSCODE_SERVER_COMMIT}/server-linux-x64/${VSCODE_SERVER_QUALITY}" \
        -o /tmp/vscode-server.tar.gz && \
    tar -xzf /tmp/vscode-server.tar.gz --strip-components=1 -C "/opt/vscode-server/${VSCODE_SERVER_COMMIT}" && \
    rm -f /tmp/vscode-server.tar.gz

RUN cat <<'EOF' > /usr/local/bin/install-vscode-server.sh
#!/bin/bash
set -e

server_commit="${VSCODE_SERVER_COMMIT:?VSCODE_SERVER_COMMIT is not set}"
container_user="${CONTAINER_USER:?CONTAINER_USER is not set}"
source_dir="/opt/vscode-server/${server_commit}"
target_dir="/home/${container_user}/.vscode-server/bin/${server_commit}"

if [ -x "${target_dir}/server.sh" ] || [ -x "${target_dir}/bin/code-server" ]; then
    exit 0
fi

if [ ! -d "${source_dir}" ]; then
    echo "VS Code server source is missing: ${source_dir}" >&2
    exit 1
fi

install -d -m 755 -o "${container_user}" -g "${container_user}" "${target_dir}"
cp -a "${source_dir}/." "${target_dir}/"
chown -R "${container_user}:${container_user}" "/home/${container_user}/.vscode-server"
EOF

RUN sed -i 's/\r$//' /usr/local/bin/install-vscode-server.sh && \
    chmod +x /usr/local/bin/install-vscode-server.sh

RUN cat <<'EOF' > /usr/local/bin/prepare-container-user.sh
#!/bin/bash
set -e

install -d -m 700 -o "$CONTAINER_USER" -g "$CONTAINER_USER" "/home/$CONTAINER_USER"
install -d -m 700 -o "$CONTAINER_USER" -g "$CONTAINER_USER" "/run/user/$(id -u "$CONTAINER_USER")"
install -d -m 700 -o "$CONTAINER_USER" -g "$CONTAINER_USER" \
    "/home/$CONTAINER_USER/.cache" \
    "/home/$CONTAINER_USER/.config" \
    "/home/$CONTAINER_USER/.config/autostart" \
    "/home/$CONTAINER_USER/.local" \
    "/home/$CONTAINER_USER/.local/share" \
    "/home/$CONTAINER_USER/.local/state"

/usr/local/bin/install-vscode-server.sh

for autostart in \
    org.gnome.Evolution-alarm-notify.desktop \
    snap-userd-autostart.desktop \
    tracker-miner-fs-3.desktop \
    ubuntu-advantage-notification.desktop \
    ubuntu-report-on-upgrade.desktop \
    update-notifier.desktop; do
    cat > "/home/$CONTAINER_USER/.config/autostart/$autostart" <<AUTOSTART
[Desktop Entry]
Type=Application
Name=$autostart
Hidden=true
AUTOSTART
    chown "$CONTAINER_USER:$CONTAINER_USER" "/home/$CONTAINER_USER/.config/autostart/$autostart"
    chmod 600 "/home/$CONTAINER_USER/.config/autostart/$autostart"
done

runuser -u "$CONTAINER_USER" -- dbus-run-session -- sh -c '
    gsettings set org.gnome.desktop.interface enable-animations false >/dev/null 2>&1 || true
    gsettings set org.gnome.desktop.privacy remember-recent-files false >/dev/null 2>&1 || true
    gsettings set org.gnome.desktop.search-providers disable-external true >/dev/null 2>&1 || true
' || true
EOF

RUN sed -i 's/\r$//' /usr/local/bin/prepare-container-user.sh && \
    chmod +x /usr/local/bin/prepare-container-user.sh

RUN cat <<'EOF' > /usr/local/bin/start-sshd.sh
#!/bin/bash
set -e

install -d -m 755 /run/sshd
ssh-keygen -A >/dev/null

if ! pgrep -x sshd >/dev/null; then
    /usr/sbin/sshd
fi
EOF

RUN sed -i 's/\r$//' /usr/local/bin/start-sshd.sh && \
    chmod +x /usr/local/bin/start-sshd.sh

RUN cat <<'EOF' > /usr/local/bin/start-ubuntu-xrdp-session.sh
#!/bin/sh

if command -v gsettings >/dev/null 2>&1; then
    gsettings set org.gnome.desktop.interface enable-animations false >/dev/null 2>&1 || true
    gsettings set org.gnome.desktop.privacy remember-recent-files false >/dev/null 2>&1 || true
    gsettings set org.gnome.desktop.search-providers disable-external true >/dev/null 2>&1 || true
fi

exec /usr/bin/gnome-session --debug --session=ubuntu
EOF

RUN sed -i 's/\r$//' /usr/local/bin/start-ubuntu-xrdp-session.sh && \
    chmod +x /usr/local/bin/start-ubuntu-xrdp-session.sh

RUN cat <<'EOF' > /etc/xrdp/startwm.sh
#!/bin/sh
exec >> "$HOME/.xrdp-session.log" 2>&1
echo "=== XRDP session started at $(date -Is) ==="

if [ -r /etc/profile ]; then
    . /etc/profile
fi

if [ -r "$HOME/.profile" ]; then
    . "$HOME/.profile"
fi

export DESKTOP_SESSION=ubuntu
export GNOME_SHELL_SESSION_MODE=ubuntu
export XDG_CURRENT_DESKTOP=ubuntu:GNOME
export XDG_SESSION_DESKTOP=ubuntu
export XDG_SESSION_TYPE=x11
export GDK_BACKEND=x11
export NO_AT_BRIDGE=1
export CLUTTER_DEFAULT_FPS=30

uid="$(id -u)"
export XDG_RUNTIME_DIR="/run/user/${uid}"
if [ ! -d "$XDG_RUNTIME_DIR" ]; then
    mkdir -p "$XDG_RUNTIME_DIR"
    chmod 700 "$XDG_RUNTIME_DIR"
fi

echo "Starting Ubuntu desktop XRDP session on DISPLAY=${DISPLAY:-unset}"
exec dbus-run-session -- /usr/local/bin/start-ubuntu-xrdp-session.sh
EOF

RUN sed -i 's/\r$//' /etc/xrdp/startwm.sh && \
    chmod +x /etc/xrdp/startwm.sh

# In a normal Ubuntu boot DBus asks systemd to activate logind. In this
# container DBus otherwise falls back to Exec=/bin/false, which makes GNOME
# Shell crash while looking up org.freedesktop.login1.
RUN sed -i 's#^Exec=/bin/false#Exec=/lib/systemd/systemd-logind#' \
    /usr/share/dbus-1/system-services/org.freedesktop.login1.service

RUN cat <<'EOF' > /usr/local/bin/start-container.sh
#!/bin/bash
set -e

/usr/local/bin/prepare-container-user.sh

service dbus start

/usr/local/bin/start-sshd.sh

if [ -x /lib/systemd/systemd-logind ] && ! pgrep -x systemd-logind >/dev/null; then
    /lib/systemd/systemd-logind >/var/log/systemd-logind.log 2>&1 &
fi

/usr/sbin/xrdp-sesman --nodaemon &
sesman_pid="$!"

/usr/sbin/xrdp --nodaemon &
xrdp_pid="$!"

wait -n "$sesman_pid" "$xrdp_pid"
EOF

RUN sed -i 's/\r$//' /usr/local/bin/start-container.sh && \
    chmod +x /usr/local/bin/start-container.sh

EXPOSE 22 3389

# Start DBus, sshd, logind, and both xrdp daemons so RDP logins can create sessions.
CMD ["/usr/local/bin/start-container.sh"]