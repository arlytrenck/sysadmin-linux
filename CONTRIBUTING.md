# Contributing

Thanks for considering a contribution. This is a small, personal collection
of sysadmin scripts and docs, kept simple on purpose — contributions are
welcome but should fit that spirit.

## Reporting a bug or suggesting a change

Open an issue describing:
- What script or doc is affected.
- What you expected vs. what actually happened (for a script, include the
  distro/OS and shell version if relevant).
- Any error output.

## Submitting a change

1. Fork the repo and create a branch for your change.
2. Keep changes focused — one script/doc per pull request is easier to
   review than a bundle of unrelated fixes.
3. For scripts:
   - Match the existing style: a comment-block header with `.SYNOPSIS`/
     usage description, options parsed with `getopts` (bash) or named
     parameters with comment-based help (PowerShell), and a `-h`/`-Help`
     option.
   - Scripts should fail safely — prefer erroring out over guessing, and
     avoid destructive actions without a clear opt-in flag.
   - Run `shellcheck` (bash) or `PSScriptAnalyzer` (PowerShell) locally
     before submitting — CI runs the same check.
4. For docs:
   - Keep the same tone: practical, concrete commands over abstract
     advice. Prefer real command examples to prose descriptions.
   - Note any assumptions (elevated privileges required, specific
     package manager, etc.).
5. Update the relevant README's file listing if you add a new script or
   doc.

## What's out of scope

- Anything that requires a specific commercial product or vendor-specific
  API to be useful to most readers.
- Scripts that make destructive changes with no dry-run or confirmation
  option.
- Content that only makes sense for one very specific environment rather
  than general server administration.

## Code of conduct

Be respectful and constructive in issues and pull requests. Disagreement
about approach is fine and expected; personal attacks are not.

