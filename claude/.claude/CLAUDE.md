# Personal setup

## 1Password and hardware MFA

- Git commit signing, the SSH agent, and the `op` CLI all go through 1Password, which is protected by a physical security key (hardware MFA) on top of the 1Password unlock.
- A signing or 1Password failure (for example `1Password: failed to fill whole buffer`, an agent or signing error, or a timeout) usually means 1Password is locked or waiting for me to approve with the key. Stop, ask me to unlock or approve, then retry once.
- Never work around it: do not disable commit signing, pass `--no-gpg-sign`, switch keys, or bypass the 1Password agent.
