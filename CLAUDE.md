# Claude Instructions

## Deployment

After any code change, always commit and push immediately — do not ask.
Push triggers GitHub Actions → Docker Hub → Dockhand webhook automatically.

- **Dockhand stack:** `fbeilke-pia`
- **Docker compose:** `docker-compose.prod.yml` in this repo
- **Build:** multi-arch (`linux/amd64,linux/arm64`) via QEMU in CI
