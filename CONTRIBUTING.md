# Contributing

Thank you for considering contributing to this project!

## How to Contribute
- Fork the repository and create your branch from `master`.
- Make your changes with clear, descriptive commit messages.
- Ensure your code is formatted using `tofu fmt` and follows best practices.
- Test your changes if possible.
- Open a pull request and describe your changes.

## CI Checks
Pull requests automatically run:

1. **OpenTofu fmt / init / validate** — syntax and provider validation
2. **Checkov** — IaC security scanning
3. **Commitlint** — conventional commit enforcement
4. **OpenTofu Plan Check** — dry-run plan against `test/minimal` (requires `HCLOUD_TOKEN` secret)

For full integration testing, add the `e2e-test` label to your PR, or trigger the
[E2E workflow](.github/workflows/e2e.yml) manually via `workflow_dispatch`.

## Code Style
- Use clear, descriptive variable and resource names.
- Add comments where necessary for clarity.
- Keep modules and resources modular and reusable.
- Run `tofu fmt -recursive` before committing.
