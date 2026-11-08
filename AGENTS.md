# Zigzag local development

The user has authorized replacing the installed application after each development task in this repository.

- After code changes and the relevant checks pass, run `./dev.local.sh` by default. It builds the locally signed Release, backs up the existing application and browser data, replaces `/Applications/Zigzag.app`, and launches the updated application.
- Use `--build-only` only when the user explicitly asks to build without installing. Do not stop at a build artifact when installation is authorized.
- Preserve the local signing identity, bundle identifiers, disabled upstream updates, and the user's existing changes in `project.yml` and the generated project.
- If Zigzag is running, request a normal application quit and wait for its profile lock to be released before installation. Never force-kill it or discard unsaved pages to make installation proceed. If normal quit cannot finish, report the specific blocker.
- Use the installer's backup and migration safeguards. Preserve real tabs, history, settings, website storage, and passwords; do not reset or replace the profile with test data.
- Verify the installed application's signature and that the running process comes from `/Applications/Zigzag.app` before reporting installation complete.

This workflow applies to Zigzag only, unless the user explicitly extends it to another project.
