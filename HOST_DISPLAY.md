# Host Display Mode

The default `compose.yml` keeps XRDP and Guacamole because that is the reliable remote desktop path for Docker Desktop on Windows.

The accelerated path is different: run GUI applications through the host display server instead of remoting a full GNOME desktop through RDP. On Windows, that means WSLg. WSLg can provide the X11/Pulse sockets and DirectX GPU bridge that GUI applications need, while the container keeps CUDA access through Docker/NVIDIA.

## Why GNOME Remote Desktop Was Not Kept

GNOME Remote Desktop did replace XRDP mechanically, but it was not suitable here:

- Guacamole 1.5.5 / guacd did not advertise the RDP Graphics Pipeline, so GNOME Remote Desktop closed the connection.
- Direct mstsc reached the service but produced an unusable/black remote login path in this non-systemd Docker Desktop container.
- Docker Desktop exposed `/dev/dxg` for CUDA, but not `/dev/dri/renderD*`, so GNOME Remote Desktop still could not initialize its CUDA/graphics acceleration path.

## Use WSLg Host Display

This machine already has a WSL2 distro named `Ubuntu`. Open it from PowerShell with:

```powershell
wsl -d Ubuntu
```

If `wsl` reports `WSL_E_DISTRO_NOT_FOUND`, use the installed distro name `Ubuntu`, not `Ubuntu-24.04`.

If `wsl` reports `WSL installation appears corrupt` with `Wsl/CallMsi/Install/REGDB_E_CLASSNOTREG`, repair the WSL app package without deleting the Ubuntu distro:

```powershell
winget repair --id Microsoft.WSL --exact --accept-source-agreements --accept-package-agreements
wsl --shutdown
wsl -d Ubuntu
```

If that still fails, open PowerShell as Administrator and make sure the Windows WSL features are enabled, then reboot:

```powershell
dism /online /enable-feature /featurename:Microsoft-Windows-Subsystem-Linux /all /norestart
dism /online /enable-feature /featurename:VirtualMachinePlatform /all /norestart
```

Do not run `wsl --unregister Ubuntu` unless you intentionally want to delete the Ubuntu distro data.

Run these commands from inside that Ubuntu shell. If the repo is on `F:`, the path is usually under `/mnt/f/...`.

```bash
cd /mnt/f/Docker/Display/'Display CUDA'
docker compose -f compose.yml -f compose.wslg.yml --profile host-display up -d --build ereshkigal-host-display
```

Open a shell in the host-display container:

```bash
docker compose -f compose.yml -f compose.wslg.yml --profile host-display exec -u ereshkigal ereshkigal-host-display bash
```

Then launch GUI applications from that shell, for example:

```bash
dbus-run-session -- gnome-terminal --wait --working-directory=/home/ereshkigal
glxinfo -B
```

Those windows should appear on the Windows desktop through WSLg. This mode is for accelerated GUI applications, not a browser-served full desktop.

This overlay maps WSLg's `/dev/dxg` device. It intentionally does not require `/dev/dri`, because this Windows/WSL host does not expose `/dev/dri/renderD*`; making that device mandatory prevents the container from starting.

If `glxinfo -B` reports `llvmpipe`, first check the host WSL renderer before debugging the container:

```bash
glxinfo -B
eglinfo -B
ls -l /dev/dxg /dev/dri 2>/dev/null
```

On this host, Mesa may default to `llvmpipe` even though WSLg's D3D12 path works. The host-display overlay forces Mesa's D3D12 Gallium driver and prefers the NVIDIA adapter:

```yaml
MESA_LOADER_DRIVER_OVERRIDE: d3d12
GALLIUM_DRIVER: d3d12
MESA_D3D12_DEFAULT_ADAPTER_NAME: NVIDIA
```

With those variables, `glxinfo -B` should report a renderer such as `D3D12 (NVIDIA GeForce RTX 4070 Laptop GPU)` and `Accelerated: yes`.

For GUI apps launched directly from the Ubuntu WSL shell, use the same variables:

```bash
export MESA_LOADER_DRIVER_OVERRIDE=d3d12
export GALLIUM_DRIVER=d3d12
export MESA_D3D12_DEFAULT_ADAPTER_NAME=NVIDIA
glxinfo -B
```

If `/dev/dri/renderD*` exists but permissions are denied, add your Ubuntu WSL user to the `render` group, then restart WSL:

```bash
sudo usermod -aG render "$USER"
exit
```

Back in PowerShell:

```powershell
wsl --shutdown
wsl -d Ubuntu
```

Then rerun `glxinfo -B`. The renderer should no longer be `llvmpipe` before you expect container GUI apps to be accelerated.

## Full Accelerated Desktop Requirement

A genuinely hardware-composited full GNOME remote desktop needs a different host shape: a Linux host or VM with systemd/GDM, NVIDIA DRM enabled, and real render nodes such as `/dev/dri/renderD128` exposed to the session. Docker Desktop's WSL2 backend does not provide that display architecture to this container.