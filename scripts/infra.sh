#!/usr/bin/env bash
# Pause/resume the hourly-billed resources (EC2, RDS) between work sessions.
set -euo pipefail

PROFILE="de-project"
REGION="us-east-1"
EC2_NAME_TAG="de-project-airflow"
RDS_IDENTIFIER="de-project-postgres"

usage() {
  echo "Usage: $0 {pause|resume|status}"
  exit 1
}

[ $# -eq 1 ] || usage

ec2_instance_id() {
  aws ec2 describe-instances --profile "$PROFILE" --region "$REGION" \
    --filters "Name=tag:Name,Values=$EC2_NAME_TAG" "Name=instance-state-name,Values=running,stopped,stopping,pending" \
    --query "Reservations[0].Instances[0].InstanceId" --output text
}

case "$1" in
  pause)
    INSTANCE_ID=$(ec2_instance_id)
    if [ "$INSTANCE_ID" != "None" ]; then
      echo "Stopping EC2 instance $INSTANCE_ID..."
      aws ec2 stop-instances --profile "$PROFILE" --region "$REGION" --instance-ids "$INSTANCE_ID" >/dev/null
    else
      echo "No EC2 instance found (not applied yet?)."
    fi

    echo "Stopping RDS instance $RDS_IDENTIFIER..."
    aws rds stop-db-instance --profile "$PROFILE" --region "$REGION" \
      --db-instance-identifier "$RDS_IDENTIFIER" >/dev/null 2>&1 \
      && echo "RDS stopping." || echo "RDS already stopped, stopping, or not found."
    ;;

  resume)
    INSTANCE_ID=$(ec2_instance_id)
    if [ "$INSTANCE_ID" != "None" ]; then
      echo "Starting EC2 instance $INSTANCE_ID..."
      aws ec2 start-instances --profile "$PROFILE" --region "$REGION" --instance-ids "$INSTANCE_ID" >/dev/null
    else
      echo "No EC2 instance found (not applied yet?)."
    fi

    echo "Starting RDS instance $RDS_IDENTIFIER..."
    aws rds start-db-instance --profile "$PROFILE" --region "$REGION" \
      --db-instance-identifier "$RDS_IDENTIFIER" >/dev/null 2>&1 \
      && echo "RDS starting." || echo "RDS already running, starting, or not found."

    echo "Note: EC2 will get a NEW public IP on start unless an Elastic IP is attached."
    echo "Note: RDS's endpoint hostname stays the same across stop/start."
    ;;

  status)
    aws ec2 describe-instances --profile "$PROFILE" --region "$REGION" \
      --filters "Name=tag:Name,Values=$EC2_NAME_TAG" "Name=instance-state-name,Values=running,stopped,stopping,pending" \
      --query "Reservations[0].Instances[0].[InstanceId,State.Name,PublicIpAddress]" \
      --output table
    aws rds describe-db-instances --profile "$PROFILE" --region "$REGION" \
      --db-instance-identifier "$RDS_IDENTIFIER" \
      --query "DBInstances[0].[DBInstanceIdentifier,DBInstanceStatus,Endpoint.Address]" \
      --output table 2>&1
    ;;

  *)
    usage
    ;;
esac
