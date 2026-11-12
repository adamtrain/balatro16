# BalatroMulti

Play 2, 4, 8 or 16 copies of Balatro at once on Windows, all receiving the same
mouse and keyboard input, each on a different seed.

## Setup (once)

You need Windows and the Steam version of Balatro.

1. Get this folder onto the PC: on the GitHub page choose **Code → Download ZIP**
   and extract it, or run `git clone https://github.com/adamtrain/balatro16`.
2. Install [Lovely](https://github.com/ethangreen-dev/lovely-injector): download
   the Windows release and put `version.dll` next to `Balatro.exe`. To find that
   folder, right-click Balatro in Steam and choose **Manage → Browse local files**.
3. Double-click `install.bat`. It copies the mod to
   `%AppData%\Balatro\Mods\BalatroMulti`. Run it again after updating this folder.

The mod does nothing when the game is started normally from Steam.

## Running

1. Start Steam and leave it running.
2. Open a Command Prompt in this folder (type `cmd` in the folder's address bar
   in Explorer and press Enter).
3. Start the instances. Try 2 first to check everything works:

       launch.bat 2

   then as many as you want:

       launch.bat 16

`launch.bat` first closes any copy of Balatro that is already running, including
one you started normally from Steam. The instances start one after
another, each waiting for the previous one to load, so 16 takes a minute or so.
Double-clicking `launch.bat` starts 4. To stop, press Ctrl+F10 in any window.

The count can be 2, 4, 8 or 16 (default 4). If Balatro is not in the default
Steam folder, pass the path:

    launch.bat 8 "D:\SteamLibrary\steamapps\common\Balatro\Balatro.exe"

| Key | Action |
|---|---|
| F1 | Zoom into the instance under the mouse; press again to return to the grid |
| F2 / F3 | Zoom to the previous / next instance |
| F4 | Solo input: send input to one instance only; press again to go back to all |
| Ctrl+F10 | Quit every instance |

Everything else you do with the mouse or keyboard, in any window, happens in
all of them. The game's own cursor is drawn in every window so you can see
where the pointer is in each.

### Fixing a desync

If one instance ends up on a different screen from the rest, hover it (or zoom
into it) and press F4. From then on only that instance receives input: it gets
a pulsing orange outline and a "SOLO INPUT" tag, and the others are dimmed.
Bring it back in line, then press F4 again to return to all instances. While
solo input is on, zooming to another instance moves solo input to it.

## What to expect

- **Layout.** Windows keep the monitor's aspect ratio so the pointer lands on
  the same spot in every copy. 4 is a 2×2 grid, 16 is 4×4, 2 is one centred
  row, and 8 uses a 3×3 grid with one cell empty.
- **Saves.** Each instance has its own save folder, `%AppData%\Balatro_multi_<n>`,
  copied from your real save the first time (without any run in progress). Your
  real save is never changed. Delete those folders to re-copy.
- **Seeds.** New runs get a different seed in every instance. A seed you type in
  yourself is typed into all of them, and the tutorial uses the game's fixed seed.
- **Sound.** Only instance 1 is audible in the grid, and only the zoomed
  instance when zoomed.
- **Steam.** Only instance 1 talks to Steam. If it closes straight away, start
  Steam first, or turn Steam off for all instances (see below).
- **Controllers** are read by every instance directly. This is untested.

## Options

Edit the `set` lines near the top of `launch.bat`:

| Variable | Meaning | Default |
|---|---|---|
| `BALATRO_MULTI_DISPLAY` | Monitor number to use | 1 |
| `BALATRO_MULTI_FPS` | Frame cap per instance | 60 |
| `BALATRO_MULTI_STEAM` | `0` disables Steam in every instance | on in instance 1 |
| `BALATRO_MULTI_LABEL` | `0` hides the instance number | shown |
| `BALATRO_MULTI_PORT` | Local port the instances talk over | 42421 |

Hotkeys are in the `keys` table at the top of `mod/BalatroMulti/multi.lua`.

## Troubleshooting

- Instance 1 shows `(cannot listen on port ...)`: it could not open the local
  port the instances talk over, and the text after the colon is the reason.
  If it says `address already in use`, run `netstat -ano | findstr :42421`
  while the instances are open; the last column is the ID of the program
  holding the port, and `tasklist /FI "PID eq <id>"` names it. Otherwise,
  remove the `rem ` in front of the `BALATRO_MULTI_PORT` line in `launch.bat`
  and try another number such as `23816`. To see whether Windows has reserved
  the port, run `netsh interface ipv4 show excludedportrange protocol=tcp`.
- Another window shows `(no link ...)`: it cannot reach instance 1. Check
  instance 1 is still running and is not showing the message above.
- A crash at startup: Lovely writes logs to `%AppData%\Balatro\Mods\lovely\log`.

## Development

`dev/stubgame` is a stand-in for Balatro that mirrors the parts of its
`main.lua` the mod hooks. `dev/run_stub.sh <love-binary> 4 test` runs four
copies under plain LÖVE 11.5 with a scripted input sequence and writes what each
copy received to `dev/logs`, for comparison.
