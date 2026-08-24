# Output Reference

## `resource_counts.csv`

High-level inventory by account, region and service. Useful for establishing assessment scope and highlighting services that may produce relevant security telemetry.

## `cloudwatch_volume_<N>d.csv`

Contains CloudWatch Logs sizing indicators by Log Group, including total bytes, average GB/day, peak GB/hour, event totals and hourly-average peak EPS.

## `log_source_destination_matrix.csv`

Maps selected telemetry sources to destinations. It is primarily intended to support authoritative-source decisions and duplicate-ingestion prevention.

## `stellar-sizing-summary.txt`

Provides a simple account-level CloudWatch ingestion baseline. It is not a final licensing declaration.

## `metadata.json`

Records project identity, version, canonical repository, provenance fingerprint and execution context.

## `errors/errors.log`

Records failed AWS CLI calls. Review this file before concluding that a service is disabled or absent.

## Raw JSON

Raw responses under `global/` and `regions/` provide evidence for detailed follow-up analysis and troubleshooting.
