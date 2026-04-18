# Claude Instructions

## Deployment

After any code change, always commit and push immediately — do not ask.
Push triggers GitHub Actions → Docker Hub → Dockhand webhook automatically.

- **Dockhand stack:** `fbeilke-pia`
- **Docker compose:** `docker-compose.prod.yml` in this repo
- **Build:** multi-arch (`linux/amd64,linux/arm64`) via QEMU in CI

## TrueNAS / Vault Execution

Never execute commands directly on TrueNAS or Vault. Instead, provide the commands to the user to run.

For Vault writes, use this pattern:

```bash
export VAULT_ADDR=http://vault:8200
export VAULT_TOKEN=<your-vault-root-token>
docker exec -e VAULT_ADDR=$VAULT_ADDR -e VAULT_TOKEN=$VAULT_TOKEN Vault vault kv put secret/<path> key="value"
```

For multi-key writes, chain all fields in a single `vault kv put` call.
Never include `#` comments inside bash code blocks meant for execution — they break pasting into a shell.
