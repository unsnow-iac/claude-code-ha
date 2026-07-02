# Security Policy

## Reporting a vulnerability

Please report security issues **privately** — do not open a public issue for a
vulnerability.

Use GitHub's private vulnerability reporting: go to the
[**Security** tab](https://github.com/unsnow-iac/claude-code-ha/security) →
**Report a vulnerability**. This opens a private advisory visible only to the
maintainer.

Please include what the issue is, how to reproduce it, and the impact you see.
You'll get an acknowledgement as soon as the maintainer can, and a fix or
mitigation coordinated privately before any public disclosure.

## Supported versions

This add-on ships as a rolling release: the Home Assistant store only ever offers
the **latest** version. Security fixes land in the next version — there are no
back-ported patch branches. Always run the latest.

## Trust model — what this add-on actually is

This is a **community add-on** (not affiliated with Anthropic or Home Assistant)
that runs the Claude Code CLI in a browser terminal. Understand its blast radius
before installing:

- **It is a root shell.** The terminal (`ttyd`) runs a writable shell as root
  inside the add-on container, with **no terminal-level password**. Anyone who can
  open the panel can run arbitrary commands.
- **It can read and write your Home Assistant configuration.** The add-on maps
  `/config` read/write, so the shell (and Claude) can read `secrets.yaml` and every
  other config file, and change them. This is inherent to the add-on's purpose.
- **It holds a Supervisor token.** The add-on requests `hassio_api` with the
  reduced `homeassistant` role (not `manager`), plus `homeassistant_api` and
  `auth_api`. It deliberately does **not** request `privileged`, `host_network`,
  Docker access, or the `manager` role.

Because of the above, the security of your instance depends on **who can reach the
panel**. Treat access to this add-on as equivalent to root on your HA config.

## How access is gated

- **Ingress-only.** The add-on is reachable only through the **authenticated Home
  Assistant ingress panel**. Home Assistant enforces authentication and
  authorization before any request reaches the add-on.
- **No host ports.** There is deliberately no `ports:` mapping — ttyd and the image
  service **cannot** be exposed on the host/LAN from the Network panel. ttyd is
  bound to loopback inside the container, and the image service rejects any request
  that did not arrive through ingress.
- **Running a fork that re-adds a host port, or otherwise bypassing ingress, is
  unsupported** and exposes an unauthenticated root shell. Don't.

## Good practice for operators

- Keep the add-on updated to the latest version.
- Limit which Home Assistant users can open the panel (the add-on appears as an
  ingress panel subject to HA's normal user permissions).
- Only set `dangerously_skip_permissions: true` if you understand it lets Claude
  act without per-action confirmation.
- Review anything you paste into the terminal — image paths and auth codes flow to
  the Claude CLI.
