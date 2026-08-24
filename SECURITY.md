# Security Policy

## Scope

This project is intended to perform read-only AWS discovery for security architecture and telemetry sizing.

## Reporting a security issue

Do not publish credentials, AWS account data, customer identifiers or discovery output in a public issue. Report security concerns to the project maintainer through a private GitHub channel when available.

## Operational guidance

Run the script with the least-privilege read-only role available. Review generated packages before sharing them because discovery output can contain infrastructure identifiers, ARNs, resource names, bucket names, network metadata and other environment-sensitive information.

## Security invariants

The canonical project must not intentionally:

- create, modify or delete AWS resources;
- retrieve plaintext secrets or credentials;
- enable or disable security controls;
- perform exploitation or offensive testing;
- hide collection behavior from the operator.
