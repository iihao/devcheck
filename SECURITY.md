# Security

DevCheck reads local process metadata (`lsof`, `ps`, `/proc`-equivalent syscalls) and opens loopback TCP connections to ports that are already listening. It does **not**:

- require root or any privileged helper
- make outbound network requests
- collect telemetry, analytics, or crash reports
- write to files outside its own state (currently: nothing)

## Threat model notes

- `devcheck` never executes user-provided strings; port numbers are validated as integers.
- Killing processes requires explicit confirmation and only targets processes owned by the current user.

## Reporting

If you find a vulnerability, please open a private security advisory on GitHub (Security → Advisories) instead of a public issue.
