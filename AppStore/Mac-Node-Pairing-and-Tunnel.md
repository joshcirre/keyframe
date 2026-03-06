# Keyframe Mac — Node Pairing & Tunnel Plan (for Screenshots + Remote QA)

This doc is about **getting a Mac environment reachable** so we can:
- build/run KeyframeMac
- capture App Store screenshots
- verify iOS Remote connectivity

It assumes the Keyframe code + docs live on this VPS, but the actual build + screenshot capture must happen on a **Mac**.

## Option 1 (best): Pair a Mac as an OpenClaw node
**Pros:** cleanest for screenshots, screen recording, consistent workflow.

### What we need on the Mac
- OpenClaw Node installed + running
- Permissions granted:
  - Screen Recording (for screenshots)
  - Accessibility (if we automate input)
  - Local network access (for Keyframe remote testing)

### Pairing flow (high-level)
1. On the VPS (Gateway): create a pairing request / code.
2. On the Mac: enter the pairing code to register the node.
3. Verify in Clive:
   - Node appears in `nodes status`
   - We can run a lightweight command (e.g. `uname -a`) via node invoke.

### Screenshot capture workflow
- Use the paired Mac node to:
  - open KeyframeMac
  - set a known window size
  - capture screenshots at native resolution
- Copy exported PNGs back into `repos/keyframe/AppStore/screenshots/` (folder TBD).

### Blockers / info needed
- The Mac needs to be online and running the node agent.
- We need the node name/id once paired.

## Option 2: SSH tunnel from Mac → VPS (to reach loopback-only services)
Use this if the Gateway/UI or a Keyframe-related local service is bound to `127.0.0.1` on the VPS.

### Local-forward (Mac exposes a local port that forwards to VPS)
On the Mac:

```bash
ssh -N \
  -L 127.0.0.1:7777:127.0.0.1:7777 \
  forge@<VPS_HOST>
```

- Left side `127.0.0.1:7777` = your Mac
- Right side `127.0.0.1:7777` = the VPS loopback service

Then on the Mac you can open:
- `http://127.0.0.1:7777` (it will actually hit the VPS service)

### Reverse-forward (VPS exposes a port that forwards to the Mac)
Use if the Mac needs to host something and the VPS must reach it:

```bash
ssh -N \
  -R 127.0.0.1:9000:127.0.0.1:9000 \
  forge@<VPS_HOST>
```

## Option 3: Tailscale (preferred networking glue)
If both the VPS and Mac are on Tailscale:
- avoid SSH tunnels
- use stable MagicDNS names
- restrict access with ACLs

**Needs:** Mac + VPS enrolled in the same tailnet.

## Practical recommendation
1) Pair the Mac node (Option 1). That unlocks screenshots + automation.
2) If anything is still loopback-bound, add a narrow SSH `-L` tunnel (Option 2).
3) Move to Tailscale for long-lived connectivity (Option 3).
