---
sidebar_position: 2
title: Remote access
---

# Remote access

The gateway binds `0.0.0.0:4000` and is protected by one bearer token. That is
fine on a LAN you control. It is not fine on the open internet, and this repo
does not try to make it so — there is no TLS termination, no rate limiting, and
no per-user identity.

If you want to reach your GPU host from elsewhere, put it on a private network
rather than forwarding a port.

## Tailscale

```bash
curl -fsSL https://tailscale.com/install.sh | sh
sudo tailscale up
```

The host now has a stable name and address on your tailnet. Point the control
host at that:

```ini
# ~/.pi/agent/extensions/.env
LMSTACK_H1_URL=http://h1-nvidia.your-tailnet.ts.net:4000/v1
```

Nothing in the stack changes. LiteLLM already listens on all interfaces; the
tailnet is simply another one, and the difference is that it is not reachable by
anyone who is not on it.

### Then close the LAN port

Bootstrap adds a UFW rule opening 4000. Once you are reaching the host over
Tailscale, that rule is doing nothing except widening the exposure:

```bash
sudo ufw delete allow 4000/tcp
sudo ufw allow in on tailscale0 to any port 4000 proto tcp
```

### Or do not open it at all

Tailscale can serve the endpoint to your tailnet without any firewall rule:

```bash
tailscale serve --bg 4000
```

This also gives you HTTPS with a certificate your devices already trust, which
removes the plaintext bearer token from the wire.

## SSH tunnel

For occasional use, no daemon needed:

```bash
ssh -N -L 4000:localhost:4000 h1-nvidia
```

The gateway is then at `http://127.0.0.1:4000/v1` on the control host, which is
also the default `LMSTACK_H2_URL` — so if you use both a local AMD host and a
tunnel, give them different local ports.

## What not to do

**Do not port-forward 4000 from your router.** A single static bearer token
protecting an endpoint that will happily generate text for anyone who has it is
not an access control story. It will be found.

**Do not put it behind a reverse proxy and call it done.** TLS solves
eavesdropping, not authorisation. If more than one person needs access, create
per-user keys in the LiteLLM UI so you can revoke one without rotating the
master key — and note that the master key can create keys, so it should not be
the thing you hand out.

## The internal ports stay internal

Whatever you do externally, the engines remain bound to `127.0.0.1` and Postgres
publishes nothing. `tests/render_test.sh` fails the build if a template stops
doing that, so exposing an engine directly takes a deliberate change that will
not pass CI by accident.
