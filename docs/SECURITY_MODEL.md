# Security Model

## Principles

- Read-only by design.
- Least privilege.
- Explicit evidence handling.
- No credential collection.
- No hidden or obfuscated behavior.
- Fail visibly when permissions are insufficient.

## Sensitive data

Discovery packages may expose infrastructure identifiers and topology. They should be handled according to the organization's information-classification and retention requirements.

## Recommended operator controls

- use short-lived SSO or federated sessions where available;
- prefer approved read-only roles;
- do not run from untrusted endpoints;
- review the generated package before transfer;
- store outputs encrypted at rest when required by organizational policy;
- remove customer-specific evidence before publishing examples;
- delete temporary assessment packages after the approved retention period.

## Out of scope

The project does not attempt to:

- retrieve application secrets;
- retrieve plaintext credentials;
- alter AWS resources;
- enable or disable logging;
- remediate findings;
- perform exploitation or offensive testing.
