# debian-shadowsocks-onion-gateway

This repository provides a one-command installation script to configure any Debian-based system as a Tor-hidden gateway with two key services:

- **FRP (Fast Reverse Proxy)** — acts as a reverse tunnel server accessible through a `.onion` address. It listens on configurable ports (e.g., 80 and 443) and forwards incoming connections to internal client machines.
- **Shadowsocks-libev** — provides a local-only SOCKS5 proxy server that client-side scripts and services can use for secure and obfuscated outbound connections (e.g., sending email, making API calls, or reaching external networks over Tor).

The resulting setup exposes a `.onion` entry point on the public gateway, while hiding all actual service infrastructure behind it.

This configuration is flexible and can be used in a variety of use cases such as:

- Reverse proxy entry point for hidden infrastructure
- Encrypted transport layer for internal developer environments
- Secure SOCKS5 proxy for local scripts and agents
- General-purpose .onion forwarding for remote services


## License

Licensed under the Prostokvashino License. See [LICENSE.txt](LICENSE.txt) for details.
