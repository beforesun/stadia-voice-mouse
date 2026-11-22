# Stadia Voice Mouse for macOS

Use a Stadia Controller running its original **Wi-Fi firmware** as a mouse and a voice input controller on macOS. [Stadiacast](https://github.com/jkfran/stadiacast) supplies the controller's input events and microphone audio. This small Swift program reads Stadiacast's local `/_events` stream and sends macOS mouse and keyboard events.

## Controls

| Controller | macOS |
| --- | --- |
| Left stick | Move pointer; radial deadzone and acceleration |
| Right stick up/down | Scroll |
| A | Left mouse button (hold to drag) |
| B | Right mouse button |
| Assistant or L2, one press | Start Doubao dictation and the controller's built-in microphone; press again to stop |
| X or R2, pressed after dictation | Tap Return to send the reviewed message in Telegram |
| Y | Tap Backspace to delete the character before the cursor |
| Capture | Open the macOS Screenshot toolbar (Command-Shift-5) |

L2 and R2 are analog triggers. They count as pressed above 160/255 and remain pressed until below 80/255, so a long pull sends one action. L1, R1, L3, R3, the D-pad, Menu, Options, and Stadia are not mapped by this bridge.

The program releases all mouse and keyboard buttons when Stadiacast disconnects or input becomes stale. It uses the first connected controller by default; `--controller c0` selects one explicitly. The table above is the default profile; the settings window can change each button's action.

## Graphical button settings

Download the universal macOS settings app from [Releases](https://github.com/beforesun/stadia-voice-mouse/releases), or build it on a Mac with the Swift toolchain:

```sh
./scripts/build-settings-app.sh
```

To make one app bundle with both Intel and Apple Silicon code, use `./scripts/build-settings-app.sh --universal`.

Then open `dist/Stadia Controller Settings.app` in Finder. Choose an action for each button and click **保存设置**. The running bridge reads the saved configuration within about one second; no code edit or restart is needed. The window also adjusts pointer and scroll speed, and **恢复默认** restores the profile in the table above after you save it.

Settings are stored at `~/Library/Application Support/StadiaVoiceMouse/config.json`. The settings app changes button actions only; the Wi-Fi receiver, BlackHole, Doubao shortcut, and macOS Accessibility permission still need their normal setup. L2 and R2 are analog triggers with a press threshold. A configured mouse button stays held until the physical button is released; keyboard actions fire once per press. If multiple buttons use the same action, either one can trigger it.

## Requirements

- macOS 13 or later (Apple Silicon or Intel), Swift 6 toolchain for building.
- Stadia Controller with original Wi-Fi firmware. Stadiacast does **not** work with the Bluetooth gamepad firmware. Consult its documentation before considering any firmware change.
- [Stadiacast](https://github.com/jkfran/stadiacast) running on the Mac, with its network/DNS setup completed.
- `ffmpeg` and `BlackHole 16ch` for the microphone path, as described by Stadiacast.
- A voice input app such as Doubao that can use `BlackHole 16ch` and has a press-to-toggle keyboard shortcut.

## Setup

1. Follow [Stadiacast's network setup](https://github.com/jkfran/stadiacast/blob/main/docs/setup.md#network) so the controller connects to the receiver on your Mac. The Mac or its hotspot must be the controller's DNS server. This is more than ordinary Bluetooth pairing.
2. Install Stadiacast's audio dependencies and BlackHole 16ch. Start Stadiacast with microphone push-to-talk and virtual input enabled:

   ```sh
   stadiacast --preset live --dns-upstream YOUR_ROUTER_IP --mic ptt --mic-device
   ```

   `YOUR_ROUTER_IP` is the upstream DNS server reachable by the Mac. See Stadiacast's guide for alternate LAN arrangements. Verify the Mac sees the Stadiacast event endpoint and the controller's Assistant button:

   ```sh
   curl -N http://MAC_LAN_IP/_events
   ```

3. Set macOS's microphone input to **Built-in Microphone**. Configure Doubao's voice shortcut to **right Command** in press-to-toggle mode. The bridge switches the default input to BlackHole 16ch when controller dictation starts, then restores Built-in Microphone when it ends. Avoid setting BlackHole as the Mac's system output.
4. Build and run the bridge:

   ```sh
   swift build -c release
   .build/release/stadia-voice-mouse --url http://MAC_LAN_IP/_events
   ```

   Grant **Accessibility** to Terminal (or the app used to launch the bridge) under System Settings → Privacy & Security → Accessibility, then relaunch it. The default shortcut sends right Command, macOS keycode `54`, as a macOS modifier-key event.
5. Open the Telegram chat with your bot. Use the left stick and A to focus its message field. Press Assistant or L2 once, wait for the controller's microphone to start, speak, then press Assistant or L2 again. **Check the recognized text, then press X or R2 once to send it.** Enter is ignored while dictation is active; it never sends automatically when dictation ends. Telegram must be configured so Return sends messages, and its message field must still have focus.

### Options

```sh
.build/release/stadia-voice-mouse --help
.build/release/stadia-voice-mouse --controller c0 --voice-keycode 54 --send-keycode 36 --keyboard-input 'Built-in Microphone' --controller-input 'BlackHole 16ch' --speed 1250
.build/release/stadia-voice-mouse --self-test
```

`MAC_LAN_IP` is the Mac address Stadiacast listens on, for example `192.168.50.85`. `--voice-keycode` is a macOS virtual key code. It must match Doubao's configured shortcut. `--send-keycode` defaults to Return (`36`); changing it changes what X sends. `--dry-run` prints actions without injecting them or needing Accessibility. The bridge accepts only a local Mac address for the Stadiacast SSE endpoint.

## What is verified

The project compiles on macOS 15.8.2 with Swift 6.2. Its self-test covers SSE parsing, controller selection, joystick deadzone, stale input, and one-action-per-press behavior. The settings window opened on an Intel Mac and saved and restored a changed mapping. On that Mac, the Wi-Fi controller, Stadiacast, BlackHole, microphone recording, and live button mapping have been checked with a real controller. The M4 Mac has not been tested.

## Credits and license

Stadiacast is an independent project by [jkfran](https://github.com/jkfran/stadiacast), licensed under MIT. This bridge uses only its documented local HTTP event API and does not include its code. This repository is also MIT licensed.
