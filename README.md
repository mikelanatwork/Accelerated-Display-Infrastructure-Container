# Accelerated Display Infrastructure Container

This workspace builds an Ubuntu 24.04 CUDA desktop container with two access paths:

- `compose.yml`: the stable full Ubuntu/GNOME desktop path through XRDP, mstsc, and Apache Guacamole.
- `compose.wslg.yml`: the accelerated WSLg host-display path for launching individual Linux GUI applications as Windows desktop windows.

The WSLg path is the accelerated path. It does not show a full remote desktop. Instead, every GUI app launched inside the container appears directly on the Windows desktop through WSLg.

## Current Validated State

The host-display container has been validated with:

```text
OpenGL renderer string: D3D12 (NVIDIA GeForce RTX 4070 Laptop GPU)
Accelerated: yes
CUDA visible through nvidia-smi
```

The Docker container name, when the host-display profile is running, is:

```text
displaycuda-ereshkigal-host-display-1
```

The container user is:

```text
ereshkigal
```

## Start The Accelerated Host-Display Container

Run the WSLg profile from inside the real Ubuntu WSL distro, not from a plain Windows PowerShell prompt. This matters because Docker Compose needs WSL's `DISPLAY`, WSLg sockets, and Linux paths.

From PowerShell:

```powershell
wsl -d Ubuntu
```

Inside Ubuntu WSL:

```bash
cd /mnt/f/Docker/Display/'Display CUDA'
docker compose -f compose.yml -f compose.wslg.yml --profile host-display up -d --build ereshkigal-host-display
```

Check that it is running:

```bash
docker ps --filter name=displaycuda-ereshkigal-host-display-1
```

## SSH Into The Host-Display Container

The host-display service runs OpenSSH Server and maps it to localhost only:

```powershell
ssh -p 2222 ereshkigal@127.0.0.1
```

The default password is configured by the compose build args. For this workspace it is:

```text
ereshkigal
```

The port is bound to `127.0.0.1`, so it is reachable from this Windows host without exposing SSH on the LAN.

## Connect With VS Code Remote-SSH

The image includes the VS Code Server that matches the local VS Code build used during setup:

```text
1.125.1
fcf604774b9f2674b473065736ee75077e256353
x64
```

Use the same SSH endpoint from VS Code Remote-SSH:

```text
ssh -p 2222 ereshkigal@127.0.0.1
```

Or use this SSH config entry from `C:\Users\User\.ssh\config`:

```text
Host ereshkigal
	HostName 127.0.0.1
	User ereshkigal
	Port 2222
```

The Windows public key from `C:\Users\User\.ssh\id_ed25519.pub` is installed in the mounted home at:

```text
home/.ssh/authorized_keys
```

The container disables SSH `StrictModes` because the Windows bind-mounted home can appear world-writable inside Linux, which otherwise causes OpenSSH to reject `authorized_keys`.

At container startup, the server is copied into the VS Code Server volume if it is missing:

```text
/home/ereshkigal/.vscode-server/bin/fcf604774b9f2674b473065736ee75077e256353
```

This path is mounted as a Docker named volume, not the Windows `./home` bind mount. Remote-SSH extracts archives into `.vscode-server`, and Docker volumes support the Linux permissions and timestamps that `tar` expects.

If Remote-SSH reports that the host identification changed after rebuilding the image, refresh the localhost entry and connect once to accept the new container host key:

```powershell
ssh-keygen -R "[127.0.0.1]:2222"
ssh -o StrictHostKeyChecking=accept-new ereshkigal true
```

## Show A Linux Window On The Windows Desktop

There is no viewer application to open for WSLg mode. To show a window, launch a GUI program in the container. WSLg will place that program's window on the Windows desktop.

### Summon GNOME Terminal

From PowerShell or Ubuntu WSL, run:

```bash
docker exec -u ereshkigal -d displaycuda-ereshkigal-host-display-1 dbus-run-session -- gnome-terminal --wait --working-directory=/home/ereshkigal
```

The `--wait` option is important. GNOME Terminal is a DBus application; without `--wait`, the temporary DBus session can exit and the window can disappear.

### Open A Shell In The Container First

You can also enter the container and launch apps from there:

```bash
docker compose -f compose.yml -f compose.wslg.yml --profile host-display exec -u ereshkigal ereshkigal-host-display bash
```

Then run GUI commands, for example:

```bash
dbus-run-session -- gnome-terminal --wait --working-directory=/home/ereshkigal
glxgears
glxinfo -B
```

For other installed GUI applications, use the same pattern:

```bash
docker exec -u ereshkigal -d displaycuda-ereshkigal-host-display-1 <program>
```

If the program needs a session bus, wrap it with `dbus-run-session`:

```bash
docker exec -u ereshkigal -d displaycuda-ereshkigal-host-display-1 dbus-run-session -- <program>
```

## Validate Acceleration

Check OpenGL:

```bash
docker exec -u ereshkigal displaycuda-ereshkigal-host-display-1 glxinfo -B
```

Expected renderer:

```text
OpenGL renderer string: D3D12 (NVIDIA GeForce RTX 4070 Laptop GPU)
Accelerated: yes
```

Check CUDA:

```bash
docker exec -u ereshkigal displaycuda-ereshkigal-host-display-1 nvidia-smi
```

Expected result: the NVIDIA GPU appears and CUDA is available.

## What The WSLg Overlay Does

`compose.wslg.yml` adds a separate `ereshkigal-host-display` service. It reuses the same image build but does not start XRDP. Instead, it idles with `tail -f /dev/null` so GUI applications can be launched on demand.

The important mounts are:

```yaml
- /mnt/wslg:/mnt/wslg
- /tmp/.X11-unix:/tmp/.X11-unix
- /usr/lib/wsl:/usr/lib/wsl:ro
```

The important device mapping is:

```yaml
- /dev/dxg:/dev/dxg
```

This host does not expose `/dev/dri/renderD*` inside WSL, so `/dev/dri` is intentionally not required. Requiring it makes Docker fail with:

```text
error gathering device information while adding custom device "/dev/dri": no such file or directory
```

The important WSLg and Mesa settings are:

```yaml
DISPLAY: ${DISPLAY}
XDG_RUNTIME_DIR: /tmp/runtime-ereshkigal
PULSE_SERVER: unix:/mnt/wslg/PulseServer
LANG: C.UTF-8
LC_ALL: C.UTF-8
GDK_BACKEND: x11
QT_QPA_PLATFORM: xcb
LD_LIBRARY_PATH: /usr/lib/wsl/lib:/usr/local/cuda/lib64
LIBGL_ALWAYS_INDIRECT: "0"
MESA_LOADER_DRIVER_OVERRIDE: d3d12
GALLIUM_DRIVER: d3d12
MESA_D3D12_DEFAULT_ADAPTER_NAME: NVIDIA
```

These force Mesa to use WSLg's D3D12 Gallium path and prefer the NVIDIA adapter. Without them, Mesa may fall back to `llvmpipe` even though the D3D12 path works.

`XDG_RUNTIME_DIR` is a container-owned directory, not `/mnt/wslg/runtime-dir`, because the WSLg runtime directory is owned by the host WSL user. GNOME applications can fail or warn when the runtime directory is owned by a different UID.

## Full Desktop Path

The default full desktop path is still XRDP and Guacamole:

```bash
docker compose up -d --build
```

Then connect with mstsc to:

```text
localhost:8888
```

Or open Guacamole at:

```text
http://localhost:8080/guacamole
```

The XRDP path is reliable for a full Ubuntu/GNOME desktop, but the desktop is not hardware-composited. The WSLg path is the accelerated path for individual GUI applications.

## Host System Changes Made During Setup

This section records the host-side changes and repairs that were needed while building the accelerated WSLg path.

### 1. WSL Was Repaired And Reinstalled Without Deleting Ubuntu

The host hit this WSL failure:

```text
Wsl/CallMsi/Install/REGDB_E_CLASSNOTREG
installer exit code 1603
```

The WSL MSI logs showed registry permission failures:

```text
Error 1406. Could not write value to key \SOFTWARE\Classes\Directory\shell\WSL
Error 1406. Could not write value to key \SOFTWARE\Classes\Directory\Background\shell\WSL
Info 1401. Could not create key ... Explorer\IdListAliasTranslations\WSL
```

The stale registry keys had broken ACLs. They were backed up and removed so the WSL installer could recreate them correctly:

```text
HKLM\SOFTWARE\Classes\Directory\shell\WSL
HKLM\SOFTWARE\Classes\Directory\Background\shell\WSL
```

Backups were written under temporary folders like:

```text
%TEMP%\wsl-reg-backup-YYYYMMDD-HHMMSS
```

WSL repair and force install commands used:

```powershell
winget repair --id Microsoft.WSL --exact --accept-source-agreements --accept-package-agreements
winget install --id Microsoft.WSL --exact --force --accept-source-agreements --accept-package-agreements
```

After the registry cleanup, `wsl --version`, `wsl -l -v`, and `wsl -d Ubuntu -- uname -a` worked again.

### 2. Windows Installer And App Package Registration Were Repaired

During troubleshooting, Windows Installer and App Installer registration were refreshed:

```powershell
msiexec.exe /unregister
msiexec.exe /regserver
```

Desktop App Installer was re-registered:

```powershell
$pkg = Get-AppxPackage Microsoft.DesktopAppInstaller
Add-AppxPackage -DisableDevelopmentMode -Register "$($pkg.InstallLocation)\AppxManifest.xml"
```

The WSL app package was also re-registered for the current user:

```powershell
$wslPkg = Get-AppxPackage MicrosoftCorporationII.WindowsSubsystemForLinux
Add-AppxPackage -DisableDevelopmentMode -Register "$($wslPkg.InstallLocation)\AppxManifest.xml"
```

These are recovery steps, not normal daily startup steps.

### 3. Windows WSL Features Were Checked

The required Windows optional features are:

```powershell
dism /online /enable-feature /featurename:Microsoft-Windows-Subsystem-Linux /all /norestart
dism /online /enable-feature /featurename:VirtualMachinePlatform /all /norestart
```

After WSL package repair or feature changes, a reboot was required and completed.

### 4. Docker Desktop Was Restarted And Ubuntu WSL Integration Was Verified

After the reboot, Docker Desktop's Linux engine was initially unavailable. Docker Desktop was launched again, and Docker integration in the `Ubuntu` WSL distro was verified.

Validated commands:

```powershell
docker version
wsl -d Ubuntu -- docker version
```

Inside Ubuntu WSL, Docker became available as:

```text
/usr/bin/docker
```

Docker Desktop must keep WSL integration enabled for the `Ubuntu` distro.

### 5. WSLg Host GPU Path Was Verified

The host WSL distro exposes WSLg and the DirectX bridge:

```bash
echo "$DISPLAY"
echo "$WAYLAND_DISPLAY"
ls -l /mnt/wslg/.X11-unix/X0
ls -l /mnt/wslg/runtime-dir/wayland-0
ls -l /dev/dxg
```

This host exposes `/dev/dxg` but not `/dev/dri/renderD*`:

```text
/dev/dxg exists
/dev/dri does not exist
```

That is why `compose.wslg.yml` maps `/dev/dxg` only.

### 6. Mesa D3D12 Was Forced For Acceleration

Default WSLg OpenGL initially reported:

```text
OpenGL renderer string: llvmpipe
Accelerated: no
```

Forcing Mesa's D3D12 driver fixed it:

```bash
MESA_LOADER_DRIVER_OVERRIDE=d3d12 \
GALLIUM_DRIVER=d3d12 \
MESA_D3D12_DEFAULT_ADAPTER_NAME=NVIDIA \
glxinfo -B
```

The validated accelerated result was:

```text
OpenGL renderer string: D3D12 (NVIDIA GeForce RTX 4070 Laptop GPU)
Accelerated: yes
```

The same environment is now baked into the host-display compose overlay.

### 7. Ubuntu WSL User Group Was Adjusted During Testing

The Ubuntu WSL user was added to the `render` group while investigating `/dev/dri` access:

```bash
sudo usermod -aG render "$USER"
```

On this host, `/dev/dri` is absent, so this group is not what enables acceleration. Acceleration comes from `/dev/dxg` plus Mesa D3D12. Leaving the group membership is harmless.

## Troubleshooting

### No Window Appears

Check that WSLg sockets exist in Ubuntu WSL:

```bash
ls -l /mnt/wslg/.X11-unix/X0
echo "$DISPLAY"
```

Check that the container has the display environment:

```bash
docker exec -u ereshkigal displaycuda-ereshkigal-host-display-1 printenv DISPLAY XDG_RUNTIME_DIR GDK_BACKEND
```

Expected values:

```text
:0
/tmp/runtime-ereshkigal
x11
```

### GNOME Terminal Opens And Immediately Closes

Use the documented command with `--wait`:

```bash
docker exec -u ereshkigal -d displaycuda-ereshkigal-host-display-1 dbus-run-session -- gnome-terminal --wait --working-directory=/home/ereshkigal
```

Also confirm UTF-8 locale is present:

```bash
docker exec -u ereshkigal displaycuda-ereshkigal-host-display-1 locale
```

Expected:

```text
LANG=C.UTF-8
LC_ALL=C.UTF-8
```

### Renderer Is llvmpipe

Check the container environment:

```bash
docker exec -u ereshkigal displaycuda-ereshkigal-host-display-1 printenv MESA_LOADER_DRIVER_OVERRIDE GALLIUM_DRIVER MESA_D3D12_DEFAULT_ADAPTER_NAME
```

Expected:

```text
d3d12
d3d12
NVIDIA
```

Then rerun:

```bash
docker exec -u ereshkigal displaycuda-ereshkigal-host-display-1 glxinfo -B
```

### Docker Refuses /dev/dri

Do not add `/dev/dri` to `compose.wslg.yml` unless the host WSL distro actually exposes it.

This host uses `/dev/dxg` for the WSLg DirectX bridge.

### WSL Fails With REGDB_E_CLASSNOTREG Again

Do not unregister the Ubuntu distro unless you intend to delete its data.

Inspect the latest WSL installer log under:

```text
C:\Users\Daowu\AppData\Local\Packages\Microsoft.DesktopAppInstaller_8wekyb3d8bbwe\LocalState\DiagOutputDir
```

If the log again shows MSI Error 1406 or 1401 on WSL shell registry keys, back up and remove the stale `...\shell\WSL` keys, then rerun `winget install --force` for Microsoft.WSL.

## Summary

Use XRDP/Guacamole for a full Ubuntu desktop. Use WSLg host-display for accelerated Linux GUI applications. To show any window from the container, start the `host-display` profile and launch the GUI program with `docker exec`; WSLg will place the window directly on the Windows desktop.