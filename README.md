# Stadia Voice Mouse for macOS

Use a Stadia Controller running its original **Wi-Fi firmware** as a mouse and a push-to-talk voice input controller on macOS. [Stadiacast](https://github.com/jkfran/stadiacast) supplies the controller's input events and microphone audio. This small Swift program reads Stadiacast's local `/_events` stream and sends macOS mouse and keyboard events.

## Controls

| Controller | macOS |
| --- | --- |
| Left stick | Move pointer; radial deadzone and acceleration |
| Right stick up/down | Scroll |
| A | Left mouse button (hold to drag) |
| B | Right mouse button |
| Assistant, held | Hold the configured voice shortcut; Stadiacast separately opens the controller's built-in microphone |
| X, pressed after dictation | Tap Return to send the reviewed message in Telegram |

The program releases all mouse and keyboard buttons when Stadiacast disconnects or input becomes stale. It uses the first connected controller by default; `--controller c0` selects one explicitly.

## Requirements

- macOS 13 or later (Apple Silicon or Intel), Swift 6 toolchain for building.
- Stadia Controller with original Wi-Fi firmware. Stadiacast does **not** work with the Bluetooth gamepad firmware. Consult its documentation before considering any firmware change.
- [Stadiacast](https://github.com/jkfran/stadiacast) running on the Mac, with its network/DNS setup completed.
- `ffmpeg` and `BlackHole 16ch` for the microphone path, as described by Stadiacast.
- A voice input app such as Doubao that can use `BlackHole 16ch` and has a hold-to-talk keyboard shortcut.

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

3. Set macOS's microphone input to **Built-in Microphone**. Configure Doubao's voice shortcut to **right Command**. The bridge switches the default input to BlackHole 16ch while Assistant is held, then restores Built-in Microphone after release. Avoid setting BlackHole as the Mac's system output.
4. Build and run the bridge:

   ```sh
   swift build -c release
   .build/release/stadia-voice-mouse --url http://MAC_LAN_IP/_events
   ```

   Grant **Accessibility** to Terminal (or the app used to launch the bridge) under System Settings → Privacy & Security → Accessibility, then relaunch it. The default shortcut sends right Command, macOS keycode `54`, as a macOS modifier-key event.
5. Open the Telegram chat with your bot. Use the left stick and A to focus its message field. Hold Assistant, wait for the controller's microphone light to blink (about 0.3 seconds), speak, then release. **Check the recognized text, then press X once to send it.** X is ignored while Assistant is held; it never sends automatically when dictation ends. Telegram must be configured so Return sends messages, and its message field must still have focus.

### Options

```sh
.build/release/stadia-voice-mouse --help
.build/release/stadia-voice-mouse --controller c0 --voice-keycode 54 --send-keycode 36 --keyboard-input 'Built-in Microphone' --controller-input 'BlackHole 16ch' --speed 1250
.build/release/stadia-voice-mouse --self-test
```

`MAC_LAN_IP` is the Mac address Stadiacast listens on, for example `192.168.50.85`. `--voice-keycode` is a macOS virtual key code. It must match Doubao's configured shortcut. `--send-keycode` defaults to Return (`36`); changing it changes what X sends. `--dry-run` prints actions without injecting them or needing Accessibility. The bridge accepts only a local Mac address for the Stadiacast SSE endpoint.

## What is verified

The project compiles on macOS 15.8.2 with Swift 6.2. Its self-test covers SSE parsing, controller selection, joystick deadzone, stale input, and one-send-per-X-press behavior. On an Intel Mac, the Wi-Fi controller, Stadiacast, BlackHole, microphone recording, and live button mapping have been checked with a real controller. Doubao response to the synthetic right Command shortcut and Telegram sending still need a clear end-to-end confirmation; the M4 Mac has not been tested.

## Credits and license

Stadiacast is an independent project by [jkfran](https://github.com/jkfran/stadiacast), licensed under MIT. This bridge uses only its documented local HTTP event API and does not include its code. This repository is also MIT licensed.
