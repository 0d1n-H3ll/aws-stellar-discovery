#!/usr/bin/env bash
# ==============================================================================
#                              ODIN // HELL
#                         AWS STELLAR DISCOVERY
#                               0d1n-H3ll
# ==============================================================================
# SPDX-FileCopyrightText: 2026 0d1n-H3ll
# SPDX-License-Identifier: MPL-2.0
# Canonical source: https://github.com/0d1n-H3ll/aws-stellar-discovery
#
# Project ID  : ODH-ASD
# Namespace   : hell.odin.aws.discovery
# Purpose     : Read-only AWS discovery and security telemetry sizing
# Security    : No resource creation, modification or deletion
# ==============================================================================

set -uo pipefail

readonly TOOL_NAME="AWS Stellar Cyber Discovery"
readonly TOOL_ID="ODH-ASD"
readonly TOOL_VERSION="1.0.0"
readonly TOOL_AUTHOR="0d1n-H3ll"
readonly TOOL_NAMESPACE="hell.odin.aws.discovery"
readonly TOOL_REPOSITORY="https://github.com/0d1n-H3ll/aws-stellar-discovery"
readonly TOOL_PROVENANCE_ID="ODH-ASD-1.0.0-7D3F9A21"

fingerprint() {
  printf '%s' "${TOOL_NAMESPACE}:${TOOL_ID}:${TOOL_VERSION}:${TOOL_PROVENANCE_ID}" \
    | sha256sum | awk '{print $1}'
}

TOOL_FINGERPRINT="$(fingerprint)"
readonly TOOL_FINGERPRINT

export AWS_PAGER=""
export AWS_CLI_AUTO_PROMPT=off

usage() {
  cat <<'EOF'
AWS Stellar Cyber Discovery v1.0.0

Usage:
  ./aws_stellar_discovery.sh [--days N] [--output DIR]
  ./aws_stellar_discovery.sh --version
  ./aws_stellar_discovery.sh --help

Options:
  --days N      CloudWatch lookback window, 1-62 days (default: 30)
  --output DIR  Output directory (default: auto-generated)
  --version     Print project and provenance information
  --help        Show this help
EOF
}

banner() {
  cat <<'EOF'

             ╔══════════════════════════════════════════╗
             ║                                          ║
             ║               ODIN // HELL               ║
             ║                                          ║
             ║          AWS STELLAR DISCOVERY           ║
             ║                                          ║
             ║               0d1n-H3ll                  ║
             ║                                          ║
             ╚══════════════════════════════════════════╝

                    ODH-ASD · Version 1.0.0
                   hell.odin.aws.discovery

             Read-Only AWS Security Discovery

EOF
}

DAYS="${DAYS:-30}"
CUSTOM_OUT=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --days)
      [[ $# -ge 2 ]] || { echo "ERROR: --days requires a value" >&2; exit 2; }
      DAYS="$2"; shift 2 ;;
    --output)
      [[ $# -ge 2 ]] || { echo "ERROR: --output requires a value" >&2; exit 2; }
      CUSTOM_OUT="$2"; shift 2 ;;
    --version)
      printf '%s\n' "$TOOL_NAME"
      printf 'Version     : %s\n' "$TOOL_VERSION"
      printf 'Project ID  : %s\n' "$TOOL_ID"
      printf 'Author      : %s\n' "$TOOL_AUTHOR"
      printf 'Namespace   : %s\n' "$TOOL_NAMESPACE"
      printf 'Provenance  : %s\n' "$TOOL_PROVENANCE_ID"
      printf 'Fingerprint : %s\n' "$TOOL_FINGERPRINT"
      printf 'Repository  : %s\n' "$TOOL_REPOSITORY"
      printf 'License     : MPL-2.0\n'
      exit 0 ;;
    --help|-h)
      usage; exit 0 ;;
    *)
      echo "ERROR: unknown option: $1" >&2
      usage >&2
      exit 2 ;;
  esac
done

if [[ ! "$DAYS" =~ ^[0-9]+$ ]] || (( DAYS < 1 || DAYS > 62 )); then
  echo "ERROR: --days must be an integer between 1 and 62" >&2
  exit 2
fi

need() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "ERROR: required command '$1' was not found." >&2
    exit 1
  }
}

need aws
need jq
need awk
need sha256sum

banner

HOME_REGION="${AWS_REGION:-${AWS_DEFAULT_REGION:-us-east-1}}"
NOW="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
START="$(date -u -d "${DAYS} days ago" +%Y-%m-%dT%H:%M:%SZ)"
STAMP="$(date -u +%Y%m%dT%H%M%SZ)"

IDENTITY="$(aws sts get-caller-identity --output json 2>/dev/null || true)"
ACCOUNT_ID="$(jq -r '.Account // empty' <<<"$IDENTITY")"
CALLER_ARN="$(jq -r '.Arn // empty' <<<"$IDENTITY")"

if [[ -z "$ACCOUNT_ID" ]]; then
  echo "ERROR: unable to identify the current AWS account." >&2
  exit 1
fi

OUT="${CUSTOM_OUT:-stellar-discovery-${ACCOUNT_ID}-${STAMP}}"
mkdir -p "$OUT/global" "$OUT/regions" "$OUT/errors"

COUNTS="$OUT/resource_counts.csv"
VOLUME="$OUT/cloudwatch_volume_${DAYS}d.csv"
ERRORS="$OUT/errors/errors.log"
MATRIX="$OUT/log_source_destination_matrix.csv"

printf 'account_id,region,service,count,status\n' > "$COUNTS"
printf 'account_id,region,log_group,retention_days,stored_bytes,total_bytes_%sd,avg_gb_day,peak_gb_hour,total_events_%sd,peak_events_hour,peak_eps_hour_avg,subscription_destinations\n' "$DAYS" "$DAYS" > "$VOLUME"
printf 'account_id,region,source,resource,destination_type,destination\n' > "$MATRIX"

capture() {
  local file="$1"; shift
  mkdir -p "$(dirname "$file")"
  local tmp="${file}.tmp" err="${file}.err"
  if "$@" >"$tmp" 2>"$err"; then
    mv "$tmp" "$file"
    rm -f "$err"
    return 0
  fi
  local rc=$?
  {
    printf '[%s] RC=%s CMD=' "$(date -u +%FT%TZ)" "$rc"
    printf '%q ' "$@"
    printf '\n'
    cat "$err"
    printf '\n------------------------------------------------------------\n'
  } >> "$ERRORS"
  jq -Rs --argjson rc "$rc" '{error: ., return_code: $rc}' < "$err" > "$file"
  rm -f "$tmp" "$err"
  return "$rc"
}

add_count() {
  local region="$1" service="$2" file="$3" expr="$4"
  local count status
  if jq -e '.error? != null' "$file" >/dev/null 2>&1; then
    count="NA"; status="ERROR_OR_DENIED"
  else
    count="$(jq -r "($expr) | length" "$file" 2>/dev/null || echo NA)"
    status="OK"
  fi
  printf '%s,%s,%s,%s,%s\n' "$ACCOUNT_ID" "$region" "$service" "$count" "$status" >> "$COUNTS"
}

# ------------------------------------------------------------------------------
# Identity, Organizations and global resources
# ------------------------------------------------------------------------------
printf '%s\n' "$IDENTITY" | jq . > "$OUT/global/sts.json"
capture "$OUT/global/account-aliases.json" aws iam list-account-aliases --output json || true
capture "$OUT/global/iam-account-summary.json" aws iam get-account-summary --output json || true
capture "$OUT/global/organizations-describe.json" aws organizations describe-organization --output json || true
capture "$OUT/global/organizations-accounts.json" aws organizations list-accounts --output json || true
capture "$OUT/global/organizations-roots.json" aws organizations list-roots --output json || true
capture "$OUT/global/s3-buckets.json" aws s3api list-buckets --output json || true
add_count GLOBAL S3Bucket "$OUT/global/s3-buckets.json" '.Buckets // []'
capture "$OUT/global/cloudfront-distributions.json" aws cloudfront list-distributions --output json || true
add_count GLOBAL CloudFront "$OUT/global/cloudfront-distributions.json" '(.DistributionList.Items // [])'
capture "$OUT/global/route53-hosted-zones.json" aws route53 list-hosted-zones --output json || true
add_count GLOBAL Route53HostedZone "$OUT/global/route53-hosted-zones.json" '.HostedZones // []'

capture "$OUT/global/regions-all.json" aws ec2 describe-regions --all-regions --region "$HOME_REGION" --output json || true
mapfile -t REGIONS < <(jq -r '.Regions[]? | select(.OptInStatus=="opt-in-not-required" or .OptInStatus=="opted-in") | .RegionName' "$OUT/global/regions-all.json" 2>/dev/null)
[[ ${#REGIONS[@]} -gt 0 ]] || REGIONS=("$HOME_REGION")
printf '%s\n' "${REGIONS[@]}" > "$OUT/global/enabled-regions.txt"

# ------------------------------------------------------------------------------
# Regional inventory and security/logging discovery
# ------------------------------------------------------------------------------
for REGION in "${REGIONS[@]}"; do
  echo "[+] $ACCOUNT_ID / $REGION"
  R="$OUT/regions/$REGION"
  mkdir -p "$R"

  capture "$R/ec2-instances.json" aws ec2 describe-instances --region "$REGION" --output json || true
  add_count "$REGION" EC2 "$R/ec2-instances.json" '[.Reservations[]?.Instances[]?]'
  capture "$R/vpcs.json" aws ec2 describe-vpcs --region "$REGION" --output json || true
  add_count "$REGION" VPC "$R/vpcs.json" '.Vpcs // []'
  capture "$R/subnets.json" aws ec2 describe-subnets --region "$REGION" --output json || true
  add_count "$REGION" Subnet "$R/subnets.json" '.Subnets // []'
  capture "$R/network-interfaces.json" aws ec2 describe-network-interfaces --region "$REGION" --output json || true
  add_count "$REGION" ENI "$R/network-interfaces.json" '.NetworkInterfaces // []'
  capture "$R/security-groups.json" aws ec2 describe-security-groups --region "$REGION" --output json || true
  add_count "$REGION" SecurityGroup "$R/security-groups.json" '.SecurityGroups // []'
  capture "$R/network-acls.json" aws ec2 describe-network-acls --region "$REGION" --output json || true
  add_count "$REGION" NACL "$R/network-acls.json" '.NetworkAcls // []'
  capture "$R/route-tables.json" aws ec2 describe-route-tables --region "$REGION" --output json || true
  add_count "$REGION" RouteTable "$R/route-tables.json" '.RouteTables // []'
  capture "$R/nat-gateways.json" aws ec2 describe-nat-gateways --region "$REGION" --output json || true
  add_count "$REGION" NATGateway "$R/nat-gateways.json" '.NatGateways // []'
  capture "$R/transit-gateways.json" aws ec2 describe-transit-gateways --region "$REGION" --output json || true
  add_count "$REGION" TransitGateway "$R/transit-gateways.json" '.TransitGateways // []'
  capture "$R/vpc-endpoints.json" aws ec2 describe-vpc-endpoints --region "$REGION" --output json || true
  add_count "$REGION" VPCEndpoint "$R/vpc-endpoints.json" '.VpcEndpoints // []'
  capture "$R/vpn-connections.json" aws ec2 describe-vpn-connections --region "$REGION" --output json || true
  add_count "$REGION" VPN "$R/vpn-connections.json" '.VpnConnections // []'
  capture "$R/directconnect-connections.json" aws directconnect describe-connections --region "$REGION" --output json || true
  add_count "$REGION" DirectConnect "$R/directconnect-connections.json" '.connections // []'

  capture "$R/vpc-flow-logs.json" aws ec2 describe-flow-logs --region "$REGION" --output json || true
  add_count "$REGION" VPCFlowLog "$R/vpc-flow-logs.json" '.FlowLogs // []'

  capture "$R/elbv2.json" aws elbv2 describe-load-balancers --region "$REGION" --output json || true
  add_count "$REGION" ELBv2 "$R/elbv2.json" '.LoadBalancers // []'
  capture "$R/elb-classic.json" aws elb describe-load-balancers --region "$REGION" --output json || true
  add_count "$REGION" ELBClassic "$R/elb-classic.json" '.LoadBalancerDescriptions // []'

  capture "$R/lambda-functions.json" aws lambda list-functions --region "$REGION" --output json || true
  add_count "$REGION" Lambda "$R/lambda-functions.json" '.Functions // []'
  capture "$R/eks-clusters.json" aws eks list-clusters --region "$REGION" --output json || true
  add_count "$REGION" EKS "$R/eks-clusters.json" '.clusters // []'
  capture "$R/ecs-clusters.json" aws ecs list-clusters --region "$REGION" --output json || true
  add_count "$REGION" ECS "$R/ecs-clusters.json" '.clusterArns // []'

  capture "$R/rds-instances.json" aws rds describe-db-instances --region "$REGION" --output json || true
  add_count "$REGION" RDSInstance "$R/rds-instances.json" '.DBInstances // []'
  capture "$R/rds-clusters.json" aws rds describe-db-clusters --region "$REGION" --output json || true
  add_count "$REGION" RDSCluster "$R/rds-clusters.json" '.DBClusters // []'
  capture "$R/dynamodb-tables.json" aws dynamodb list-tables --region "$REGION" --output json || true
  add_count "$REGION" DynamoDB "$R/dynamodb-tables.json" '.TableNames // []'
  capture "$R/redshift-clusters.json" aws redshift describe-clusters --region "$REGION" --output json || true
  add_count "$REGION" Redshift "$R/redshift-clusters.json" '.Clusters // []'
  capture "$R/elasticache.json" aws elasticache describe-cache-clusters --region "$REGION" --output json || true
  add_count "$REGION" ElastiCache "$R/elasticache.json" '.CacheClusters // []'
  capture "$R/efs.json" aws efs describe-file-systems --region "$REGION" --output json || true
  add_count "$REGION" EFS "$R/efs.json" '.FileSystems // []'
  capture "$R/fsx.json" aws fsx describe-file-systems --region "$REGION" --output json || true
  add_count "$REGION" FSx "$R/fsx.json" '.FileSystems // []'

  capture "$R/kinesis-streams.json" aws kinesis list-streams --region "$REGION" --output json || true
  add_count "$REGION" Kinesis "$R/kinesis-streams.json" '.StreamNames // []'
  capture "$R/firehose.json" aws firehose list-delivery-streams --region "$REGION" --output json || true
  add_count "$REGION" Firehose "$R/firehose.json" '.DeliveryStreamNames // []'
  capture "$R/sqs.json" aws sqs list-queues --region "$REGION" --output json || true
  add_count "$REGION" SQS "$R/sqs.json" '(.QueueUrls // [])'
  capture "$R/sns.json" aws sns list-topics --region "$REGION" --output json || true
  add_count "$REGION" SNS "$R/sns.json" '.Topics // []'
  capture "$R/eventbridge-buses.json" aws events list-event-buses --region "$REGION" --output json || true
  add_count "$REGION" EventBridge "$R/eventbridge-buses.json" '.EventBuses // []'
  capture "$R/apigateway-rest.json" aws apigateway get-rest-apis --region "$REGION" --output json || true
  add_count "$REGION" APIGatewayREST "$R/apigateway-rest.json" '.items // []'
  capture "$R/apigateway-v2.json" aws apigatewayv2 get-apis --region "$REGION" --output json || true
  add_count "$REGION" APIGatewayV2 "$R/apigateway-v2.json" '.Items // []'

  capture "$R/cloudtrail-trails.json" aws cloudtrail describe-trails --include-shadow-trails --region "$REGION" --output json || true
  add_count "$REGION" CloudTrail "$R/cloudtrail-trails.json" '.trailList // []'
  capture "$R/cloudwatch-log-groups.json" aws logs describe-log-groups --region "$REGION" --output json || true
  add_count "$REGION" CloudWatchLogGroup "$R/cloudwatch-log-groups.json" '.logGroups // []'

  capture "$R/waf-regional.json" aws wafv2 list-web-acls --scope REGIONAL --region "$REGION" --output json || true
  add_count "$REGION" WAFRegional "$R/waf-regional.json" '.WebACLs // []'
  capture "$R/network-firewalls.json" aws network-firewall list-firewalls --region "$REGION" --output json || true
  add_count "$REGION" NetworkFirewall "$R/network-firewalls.json" '.Firewalls // []'
  capture "$R/route53-resolver-query-log-configs.json" aws route53resolver list-resolver-query-log-configs --region "$REGION" --output json || true
  add_count "$REGION" Route53ResolverQueryLog "$R/route53-resolver-query-log-configs.json" '.ResolverQueryLogConfigs // []'

  capture "$R/guardduty-detectors.json" aws guardduty list-detectors --region "$REGION" --output json || true
  add_count "$REGION" GuardDutyDetector "$R/guardduty-detectors.json" '.DetectorIds // []'
  capture "$R/securityhub.json" aws securityhub describe-hub --region "$REGION" --output json || true
  capture "$R/inspector2-account.json" aws inspector2 batch-get-account-status --region "$REGION" --output json || true
  capture "$R/macie-session.json" aws macie2 get-macie-session --region "$REGION" --output json || true
  capture "$R/securitylake.json" aws securitylake list-data-lakes --regions "$REGION" --region "$REGION" --output json || true
  capture "$R/config-recorders.json" aws configservice describe-configuration-recorders --region "$REGION" --output json || true
  capture "$R/config-recorder-status.json" aws configservice describe-configuration-recorder-status --region "$REGION" --output json || true

  # Source -> destination matrix
  jq -r --arg a "$ACCOUNT_ID" --arg r "$REGION" '.trailList[]? | select(.S3BucketName) | [$a,$r,"CloudTrail",(.Name // .TrailARN // ""),"S3",("s3://"+.S3BucketName+(if .S3KeyPrefix then "/"+.S3KeyPrefix else "" end))] | @csv' "$R/cloudtrail-trails.json" 2>/dev/null >> "$MATRIX" || true
  jq -r --arg a "$ACCOUNT_ID" --arg r "$REGION" '.FlowLogs[]? | [$a,$r,"VPC Flow Log",(.FlowLogId // .ResourceId // ""),(.LogDestinationType // ""),(.LogDestination // .LogGroupName // "")] | @csv' "$R/vpc-flow-logs.json" 2>/dev/null >> "$MATRIX" || true
  jq -r --arg a "$ACCOUNT_ID" --arg r "$REGION" '.ResolverQueryLogConfigs[]? | [$a,$r,"Route53 Resolver Query Log",(.Name // .Id // ""),"DestinationArn",(.DestinationArn // "")] | @csv' "$R/route53-resolver-query-log-configs.json" 2>/dev/null >> "$MATRIX" || true
  jq -r --arg a "$ACCOUNT_ID" --arg r "$REGION" '.dataLakes[]? | [$a,$r,"Security Lake",(.dataLakeArn // ""),"S3/OCSF",(.s3BucketArn // .dataLakeArn // "")] | @csv' "$R/securitylake.json" 2>/dev/null >> "$MATRIX" || true

  # CloudWatch Logs volume baseline
  if ! jq -e '.error? != null' "$R/cloudwatch-log-groups.json" >/dev/null 2>&1; then
    while IFS=$'\t' read -r LG RET STORED; do
      [[ -z "$LG" ]] && continue
      DIMS="$(jq -cn --arg lg "$LG" '[{Name:"LogGroupName",Value:$lg}]')"
      BYTES_JSON="$(aws cloudwatch get-metric-statistics --namespace AWS/Logs --metric-name IncomingBytes --dimensions "$DIMS" --start-time "$START" --end-time "$NOW" --period 3600 --statistics Sum --region "$REGION" --output json 2>/dev/null || printf '{"Datapoints":[]}')"
      EVENTS_JSON="$(aws cloudwatch get-metric-statistics --namespace AWS/Logs --metric-name IncomingLogEvents --dimensions "$DIMS" --start-time "$START" --end-time "$NOW" --period 3600 --statistics Sum --region "$REGION" --output json 2>/dev/null || printf '{"Datapoints":[]}')"

      TOTAL_BYTES="$(jq '[.Datapoints[]?.Sum // 0] | add // 0' <<<"$BYTES_JSON")"
      PEAK_HOUR_BYTES="$(jq '[.Datapoints[]?.Sum // 0] | if length==0 then 0 else max end' <<<"$BYTES_JSON")"
      TOTAL_EVENTS="$(jq '[.Datapoints[]?.Sum // 0] | add // 0' <<<"$EVENTS_JSON")"
      PEAK_HOUR_EVENTS="$(jq '[.Datapoints[]?.Sum // 0] | if length==0 then 0 else max end' <<<"$EVENTS_JSON")"
      AVG_GB_DAY="$(awk -v b="$TOTAL_BYTES" -v d="$DAYS" 'BEGIN {printf "%.6f", b/1073741824/d}')"
      PEAK_GB_HOUR="$(awk -v b="$PEAK_HOUR_BYTES" 'BEGIN {printf "%.6f", b/1073741824}')"
      PEAK_EPS="$(awk -v e="$PEAK_HOUR_EVENTS" 'BEGIN {printf "%.3f", e/3600}')"
      SUBS="$(aws logs describe-subscription-filters --log-group-name "$LG" --region "$REGION" --output json 2>/dev/null | jq -r '[.subscriptionFilters[]?.destinationArn] | join("|")' 2>/dev/null || true)"
      printf '"%s","%s","%s","%s","%s","%s","%s","%s","%s","%s","%s","%s"\n' "$ACCOUNT_ID" "$REGION" "${LG//\"/\"\"}" "${RET:-}" "${STORED:-0}" "$TOTAL_BYTES" "$AVG_GB_DAY" "$PEAK_GB_HOUR" "$TOTAL_EVENTS" "$PEAK_HOUR_EVENTS" "$PEAK_EPS" "${SUBS//\"/\"\"}" >> "$VOLUME"
    done < <(jq -r '.logGroups[]? | [.logGroupName, (.retentionInDays // ""), (.storedBytes // 0)] | @tsv' "$R/cloudwatch-log-groups.json")
  fi
done

# CloudFront-scoped WAF is queried in us-east-1
capture "$OUT/global/waf-cloudfront.json" aws wafv2 list-web-acls --scope CLOUDFRONT --region us-east-1 --output json || true

# De-duplicate matrix rows while preserving header
{
  head -n 1 "$MATRIX"
  tail -n +2 "$MATRIX" | sort -u
} > "${MATRIX}.tmp"
mv "${MATRIX}.tmp" "$MATRIX"

TOTAL_AVG_GB_DAY="$(awk -F',' 'NR>1 {gsub(/"/,"",$7); s+=$7} END {printf "%.3f", s+0}' "$VOLUME")"
TOTAL_PEAK_GB_HOUR_SUM="$(awk -F',' 'NR>1 {gsub(/"/,"",$8); s+=$8} END {printf "%.3f", s+0}' "$VOLUME")"
LOGGROUPS_MEASURED="$(awk 'END {print NR-1}' "$VOLUME")"

jq -n \
  --arg name "$TOOL_NAME" \
  --arg version "$TOOL_VERSION" \
  --arg author "$TOOL_AUTHOR" \
  --arg project_id "$TOOL_ID" \
  --arg namespace "$TOOL_NAMESPACE" \
  --arg provenance "$TOOL_PROVENANCE_ID" \
  --arg fingerprint "$TOOL_FINGERPRINT" \
  --arg repository "$TOOL_REPOSITORY" \
  --arg account "$ACCOUNT_ID" \
  --arg caller "$CALLER_ARN" \
  --arg start "$START" \
  --arg end "$NOW" \
  --argjson days "$DAYS" \
  '{generator:{name:$name,version:$version,author:$author,project_id:$project_id,namespace:$namespace,provenance_id:$provenance,fingerprint:$fingerprint,canonical_repository:$repository},execution:{mode:"read-only",account_id:$account,caller_arn:$caller,start:$start,end:$end,lookback_days:$days}}' \
  > "$OUT/metadata.json"

cat > "$OUT/stellar-sizing-summary.txt" <<EOF
======================================================================
                     AWS STELLAR CYBER DISCOVERY
======================================================================
                          ODIN // HELL
                            0d1n-H3ll

Project ID   : $TOOL_ID
Version      : $TOOL_VERSION
Namespace    : $TOOL_NAMESPACE
Provenance   : $TOOL_PROVENANCE_ID
Fingerprint  : $TOOL_FINGERPRINT
Repository   : $TOOL_REPOSITORY

AWS Account  : $ACCOUNT_ID
Caller       : $CALLER_ARN
Window       : $DAYS days
Regions      : ${#REGIONS[@]}
Log Groups   : $LOGGROUPS_MEASURED
Average CloudWatch Incoming Volume : $TOTAL_AVG_GB_DAY GB/day
Sum of per-log-group peak hours     : $TOTAL_PEAK_GB_HOUR_SUM GB/hour

IMPORTANT
- IncomingBytes is an uncompressed CloudWatch Logs ingestion baseline.
- It is not automatically equal to final Stellar Cyber licensed ingestion.
- Sources stored only in S3 may not appear in CloudWatch volume metrics.
- Review log_source_destination_matrix.csv for duplicate-path risk.
- Review errors/errors.log before concluding a service is absent.
======================================================================
EOF

PACKAGE="${OUT}.zip"
if command -v zip >/dev/null 2>&1; then
  zip -rq "$PACKAGE" "$OUT"
else
  PACKAGE="${OUT}.tar.gz"
  tar -czf "$PACKAGE" "$OUT"
fi

printf '\n[+] Discovery completed\n'
printf '    Account        : %s\n' "$ACCOUNT_ID"
printf '    Regions        : %s\n' "${#REGIONS[@]}"
printf '    Avg CloudWatch : %s GB/day\n' "$TOTAL_AVG_GB_DAY"
printf '    Package        : %s\n' "$PACKAGE"
