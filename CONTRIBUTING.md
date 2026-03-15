# Contributing

Thanks for your interest in claude-server. Contributions are welcome.

## Getting Started

1. Fork the repo and clone it
2. Run `./setup.sh` to set up locally
3. Make your changes
4. Test manually — queue a task and verify the watchdog picks it up

## What's Helpful

- Bug fixes (especially around edge cases in watchdog/executor)
- Linux support (systemd units, cron alternatives to launchd)
- Dashboard improvements
- Documentation fixes

## Guidelines

- Keep it simple. This project runs on shell scripts and a single Express server. That's intentional.
- Test your changes. There's no test suite (yet), so manual verification is expected.
- One PR per feature or fix.
- Write clear commit messages.

## Architecture Notes

The system is intentionally file-based. Tasks are markdown files. State is JSON files. Logs are markdown files. This makes everything inspectable, debuggable, and version-controllable without additional infrastructure.

If you're adding a feature, prefer extending this pattern over introducing databases, message queues, or other dependencies.

## Questions?

Open an issue. Happy to discuss before you start working on something.
