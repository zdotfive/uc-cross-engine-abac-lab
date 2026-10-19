#!/usr/bin/env bash
# AWS CLI commands for the EMR Serverless run. Usage:
#   AWS_PROFILE=<profile> bash emr/commands.sh create|run|wait|fetch|delete
# Reads DATABRICKS_HOST, DATABRICKS_CLIENT_ID, DATABRICKS_CLIENT_SECRET from .env.
# The secret value is passed to Secrets Manager through a temporary file (mode 600)
# that is deleted right away; it is never printed.
set -euo pipefail
cd "$(dirname "$0")/.."
REGION=${REGION:-eu-west-1}
ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
BUCKET=xabac-lab-emr-${ACCOUNT}-euw1
SECRET_ID=xabac-lab/reader
ROLE=xabac-lab-emr-job-role
APP_NAME=xabac-lab
RELEASE=${RELEASE:-emr-spark-8.1.0}
STATE=emr/.state            # application id and job run id (git-ignored)
# emr-spark-8.x ships Iceberg on the default classpath. The 7.x path from the EMR Serverless
# docs (/usr/share/aws/iceberg/lib/iceberg-spark3-runtime.jar) does not exist there
# (NoSuchFileException). Set EXTRA_JARS only for older releases.
EXTRA_JARS=${EXTRA_JARS:-}
HOST=$(grep '^DATABRICKS_HOST=' .env | cut -d= -f2-)
TABLES=customers_small_ice,customers_small_uniform,customers_small_ice_abac,customers_small_uniform_abac,customers_big_ice,customers_big_uniform,customers_big_ice_abac,customers_big_uniform_abac
A="--region $REGION"

case "${1:-}" in
create)
  echo "## bucket"
  aws s3api create-bucket $A --bucket "$BUCKET" --create-bucket-configuration LocationConstraint=$REGION
  aws s3api put-public-access-block $A --bucket "$BUCKET" --public-access-block-configuration \
    BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true
  aws s3 cp $A emr/emr_bench.py "s3://$BUCKET/code/emr_bench.py"

  echo "## secret"
  TMP=$(mktemp); chmod 600 "$TMP"
  python3 - "$TMP" <<'PY'
import json, sys
env = dict(l.rstrip("\n").split("=", 1) for l in open(".env") if "=" in l and not l.startswith("#"))
json.dump({"client_id": env["DATABRICKS_CLIENT_ID"], "client_secret": env["DATABRICKS_CLIENT_SECRET"]},
          open(sys.argv[1], "w"))
PY
  aws secretsmanager create-secret $A --name "$SECRET_ID" --secret-string "file://$TMP" \
    --query '{ARN:ARN,Name:Name}' --output json
  rm -f "$TMP"
  SECRET_ARN=$(aws secretsmanager describe-secret $A --secret-id "$SECRET_ID" --query ARN --output text)

  echo "## IAM role"
  aws iam create-role --role-name "$ROLE" --query 'Role.Arn' --output text --assume-role-policy-document '{
    "Version": "2012-10-17",
    "Statement": [{"Effect": "Allow", "Principal": {"Service": "emr-serverless.amazonaws.com"},
                   "Action": "sts:AssumeRole",
                   "Condition": {"StringEquals": {"aws:SourceAccount": "'"$ACCOUNT"'"}}}]}'
  aws iam put-role-policy --role-name "$ROLE" --policy-name xabac-lab-job --policy-document '{
    "Version": "2012-10-17",
    "Statement": [
      {"Effect": "Allow", "Action": ["s3:GetObject", "s3:PutObject", "s3:ListBucket"],
       "Resource": ["arn:aws:s3:::'"$BUCKET"'", "arn:aws:s3:::'"$BUCKET"'/*"]},
      {"Effect": "Allow", "Action": "secretsmanager:GetSecretValue", "Resource": "'"$SECRET_ARN"'"}]}'

  echo "## EMR Serverless application"
  aws emr-serverless create-application $A --name "$APP_NAME" --type SPARK --release-label "$RELEASE" \
    --maximum-capacity cpu=8vCPU,memory=32GB,disk=100GB \
    --auto-stop-configuration enabled=true,idleTimeoutMinutes=5 \
    --query '{applicationId:applicationId,arn:arn}' --output json | tee "$STATE.app.json"
  ;;
upload)
  aws s3 cp $A emr/emr_bench.py "s3://$BUCKET/code/emr_bench.py"
  ;;
network-create)
  # Without a VPC, EMR Serverless reaches only some AWS services in the same Region, not the
  # Databricks host. Private subnets with a NAT gateway give the workers outbound internet.
  NET=emr/.state.net.json
  V=$(aws ec2 create-vpc $A --cidr-block 10.42.0.0/16 --tag-specifications 'ResourceType=vpc,Tags=[{Key=Name,Value=xabac-lab}]' --query Vpc.VpcId --output text)
  AZ1=${REGION}a; AZ2=${REGION}b
  PUB=$(aws ec2 create-subnet $A --vpc-id "$V" --cidr-block 10.42.0.0/24 --availability-zone $AZ1 --query Subnet.SubnetId --output text)
  PRIV1=$(aws ec2 create-subnet $A --vpc-id "$V" --cidr-block 10.42.1.0/24 --availability-zone $AZ1 --query Subnet.SubnetId --output text)
  PRIV2=$(aws ec2 create-subnet $A --vpc-id "$V" --cidr-block 10.42.2.0/24 --availability-zone $AZ2 --query Subnet.SubnetId --output text)
  IGW=$(aws ec2 create-internet-gateway $A --query InternetGateway.InternetGatewayId --output text)
  aws ec2 attach-internet-gateway $A --vpc-id "$V" --internet-gateway-id "$IGW"
  RT_PUB=$(aws ec2 create-route-table $A --vpc-id "$V" --query RouteTable.RouteTableId --output text)
  aws ec2 create-route $A --route-table-id "$RT_PUB" --destination-cidr-block 0.0.0.0/0 --gateway-id "$IGW" --query Return --output text
  aws ec2 associate-route-table $A --route-table-id "$RT_PUB" --subnet-id "$PUB" --query AssociationId --output text
  EIP=$(aws ec2 allocate-address $A --domain vpc --query AllocationId --output text)
  NAT=$(aws ec2 create-nat-gateway $A --subnet-id "$PUB" --allocation-id "$EIP" --query NatGateway.NatGatewayId --output text)
  echo "waiting for NAT gateway $NAT"; aws ec2 wait nat-gateway-available $A --nat-gateway-ids "$NAT"
  RT_PRIV=$(aws ec2 create-route-table $A --vpc-id "$V" --query RouteTable.RouteTableId --output text)
  aws ec2 create-route $A --route-table-id "$RT_PRIV" --destination-cidr-block 0.0.0.0/0 --nat-gateway-id "$NAT" --query Return --output text
  aws ec2 associate-route-table $A --route-table-id "$RT_PRIV" --subnet-id "$PRIV1" --query AssociationId --output text
  aws ec2 associate-route-table $A --route-table-id "$RT_PRIV" --subnet-id "$PRIV2" --query AssociationId --output text
  VPCE=$(aws ec2 create-vpc-endpoint $A --vpc-id "$V" --service-name com.amazonaws.$REGION.s3 --route-table-ids "$RT_PRIV" --query VpcEndpoint.VpcEndpointId --output text)
  SG=$(aws ec2 create-security-group $A --vpc-id "$V" --group-name xabac-lab-emr --description "EMR Serverless workers, egress only" --query GroupId --output text)
  python3 - "$NET" <<PY
import json, sys
json.dump(dict(vpc="$V", pub="$PUB", priv1="$PRIV1", priv2="$PRIV2", igw="$IGW", rt_pub="$RT_PUB",
               rt_priv="$RT_PRIV", eip="$EIP", nat="$NAT", vpce="$VPCE", sg="$SG"), open(sys.argv[1], "w"), indent=1)
PY
  cat "$NET"
  APP_ID=$(python3 -c 'import json;print(json.load(open("emr/.state.app.json"))["applicationId"])')
  aws emr-serverless update-application $A --application-id "$APP_ID" \
    --network-configuration "subnetIds=$PRIV1,$PRIV2,securityGroupIds=$SG" \
    --query 'application.{state:state,networkConfiguration:networkConfiguration}' --output json
  ;;
network-delete)
  NET=emr/.state.net.json
  [ -f "$NET" ] || { echo "no network state"; exit 0; }
  j() { python3 -c "import json;print(json.load(open('$NET'))['$1'])"; }
  aws ec2 delete-nat-gateway $A --nat-gateway-id "$(j nat)" --query NatGatewayId --output text
  echo "waiting for NAT gateway deletion"; aws ec2 wait nat-gateway-deleted $A --nat-gateway-ids "$(j nat)"
  aws ec2 release-address $A --allocation-id "$(j eip)" && echo "elastic IP released"
  aws ec2 delete-vpc-endpoints $A --vpc-endpoint-ids "$(j vpce)" --query 'Unsuccessful' --output text
  aws ec2 detach-internet-gateway $A --internet-gateway-id "$(j igw)" --vpc-id "$(j vpc)"
  aws ec2 delete-internet-gateway $A --internet-gateway-id "$(j igw)" && echo "internet gateway deleted"
  for s in pub priv1 priv2; do aws ec2 delete-subnet $A --subnet-id "$(j $s)" && echo "subnet $s deleted"; done
  for r in rt_pub rt_priv; do aws ec2 delete-route-table $A --route-table-id "$(j $r)" && echo "route table $r deleted"; done
  # ENIs left by EMR workers can hold the security group for a few minutes
  for i in $(seq 1 20); do aws ec2 delete-security-group $A --group-id "$(j sg)" 2>/dev/null && { echo "security group deleted"; break; }; sleep 15; done
  aws ec2 delete-vpc $A --vpc-id "$(j vpc)" && echo "vpc deleted"
  aws ec2 describe-vpcs $A --filters Name=tag:Name,Values=xabac-lab --query 'Vpcs[].VpcId' --output json
  aws ec2 describe-nat-gateways $A --nat-gateway-ids "$(j nat)" --query 'NatGateways[].State' --output json
  aws ec2 describe-addresses $A --filters Name=allocation-id,Values="$(j eip)" --query 'Addresses[].AllocationId' --output json
  ;;
run)
  APP_ID=$(python3 -c 'import json;print(json.load(open("emr/.state.app.json"))["applicationId"])')
  ROLE_ARN=$(aws iam get-role --role-name "$ROLE" --query Role.Arn --output text)
  aws emr-serverless start-job-run $A --application-id "$APP_ID" --execution-role-arn "$ROLE_ARN" \
    --name xabac-bench --execution-timeout-minutes 20 \
    --job-driver '{"sparkSubmit": {
        "entryPoint": "s3://'"$BUCKET"'/code/emr_bench.py",
        "entryPointArguments": ["'"$HOST"'", "'"$SECRET_ID"'", "'"$REGION"'", "s3://'"$BUCKET"'/results/emr_bench.jsonl", "'"$TABLES"'", "3"],
        "sparkSubmitParameters": "'"${EXTRA_JARS:+--jars $EXTRA_JARS }"'--conf spark.driver.cores=2 --conf spark.driver.memory=4g --conf spark.executor.cores=2 --conf spark.executor.memory=4g --conf spark.executor.instances=2 --conf spark.dynamicAllocation.enabled=false"}}' \
    --configuration-overrides '{"monitoringConfiguration": {"s3MonitoringConfiguration": {"logUri": "s3://'"$BUCKET"'/logs/"}}}' \
    --query '{jobRunId:jobRunId}' --output json | tee "$STATE.run.json"
  ;;
wait)
  APP_ID=$(python3 -c 'import json;print(json.load(open("emr/.state.app.json"))["applicationId"])')
  RUN_ID=$(python3 -c 'import json;print(json.load(open("emr/.state.run.json"))["jobRunId"])')
  while :; do
    S=$(aws emr-serverless get-job-run $A --application-id "$APP_ID" --job-run-id "$RUN_ID" --query jobRun.state --output text)
    echo "$(date -u +%H:%M:%S) $S"
    case "$S" in SUCCESS|FAILED|CANCELLED) break ;; esac
    sleep 30
  done
  aws emr-serverless get-job-run $A --application-id "$APP_ID" --job-run-id "$RUN_ID" --output json \
    --query 'jobRun.{state:state,stateDetails:stateDetails,releaseLabel:releaseLabel,createdAt:createdAt,updatedAt:updatedAt,totalExecutionDurationSeconds:totalExecutionDurationSeconds,totalResourceUtilization:totalResourceUtilization,billedResourceUtilization:billedResourceUtilization}'
  ;;
fetch)
  APP_ID=$(python3 -c 'import json;print(json.load(open("emr/.state.app.json"))["applicationId"])')
  RUN_ID=$(python3 -c 'import json;print(json.load(open("emr/.state.run.json"))["jobRunId"])')
  mkdir -p results/emr
  aws s3 cp $A "s3://$BUCKET/results/emr_bench.jsonl" results/emr/emr_bench.jsonl || true
  for f in stdout stderr; do
    aws s3 cp $A "s3://$BUCKET/logs/applications/$APP_ID/jobs/$RUN_ID/SPARK_DRIVER/$f.gz" "results/emr/driver_$f.gz" || true
  done
  ;;
delete)
  APP_ID=$(python3 -c 'import json;print(json.load(open("emr/.state.app.json"))["applicationId"])' 2>/dev/null || true)
  if [ -n "$APP_ID" ]; then
    aws emr-serverless stop-application $A --application-id "$APP_ID" || true
    for i in $(seq 1 20); do
      S=$(aws emr-serverless get-application $A --application-id "$APP_ID" --query application.state --output text)
      echo "application state: $S"; [ "$S" = STOPPED ] || [ "$S" = CREATED ] && break; sleep 15
    done
    aws emr-serverless delete-application $A --application-id "$APP_ID" && echo "application deleted"
  fi
  aws secretsmanager delete-secret $A --secret-id "$SECRET_ID" --force-delete-without-recovery \
    --query '{Name:Name,DeletionDate:DeletionDate}' --output json
  aws iam delete-role-policy --role-name "$ROLE" --policy-name xabac-lab-job && echo "role policy deleted"
  aws iam delete-role --role-name "$ROLE" && echo "role deleted"
  aws s3 rm $A "s3://$BUCKET" --recursive --quiet && aws s3api delete-bucket $A --bucket "$BUCKET" && echo "bucket deleted"
  echo "## verify"
  aws emr-serverless list-applications $A --query "applications[?name=='$APP_NAME'].{id:id,state:state}" --output json
  aws secretsmanager list-secrets $A --filters Key=name,Values="$SECRET_ID" --query 'SecretList[].Name' --output json
  aws iam get-role --role-name "$ROLE" 2>&1 | tail -1 || true
  aws s3api head-bucket $A --bucket "$BUCKET" 2>&1 | tail -1 || true
  ;;
*) echo "usage: $0 create|upload|network-create|run|wait|fetch|delete|network-delete"; exit 2 ;;
esac
