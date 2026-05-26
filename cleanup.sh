#!/bin/bash
REGION="eu-central-1"
PROFILE="default"
THIRTY_DAYS_AGO=$(date -v-30d +%Y-%m-%dT%H:%M:%S 2>/dev/null || date -d "30 days ago" +%Y-%m-%dT%H:%M:%S)

echo "Starting cleanup in $REGION using profile $PROFILE..."

# Counts
EBS_VOL_COUNT=0
EIP_COUNT=0
SNAPSHOT_COUNT=0
ELB_COUNT=0
NAT_COUNT=0
ERRORS=()

# 1) EBS orphan volumes
VOL_IDS=$(aws ec2 describe-volumes --region "$REGION" --profile "$PROFILE" --filters Name=status,Values=available --query "Volumes[*].VolumeId" --output text)
for id in $VOL_IDS; do
    echo "Deleting EBS Volume: $id"
    if aws ec2 delete-volume --volume-id "$id" --region "$REGION" --profile "$PROFILE" 2>/dev/null; then
        ((EBS_VOL_COUNT++))
    else
        echo "Error deleting volume $id"
        ERRORS+=("Volume $id")
    fi
done

# 2) Unassociated Elastic IPs
EIP_ALLOCS=$(aws ec2 describe-addresses --region "$REGION" --profile "$PROFILE" --query "Addresses[?AssociationId == null].AllocationId" --output text)
for id in $EIP_ALLOCS; do
    echo "Releasing EIP: $id"
    if aws ec2 release-address --allocation-id "$id" --region "$REGION" --profile "$PROFILE" 2>/dev/null; then
        ((EIP_COUNT++))
    else
        echo "Error releasing EIP $id"
        ERRORS+=("EIP $id")
    fi
done

# 3) Old EBS snapshots
SNAPSHOTS_JSON=$(aws ec2 describe-snapshots --region "$REGION" --profile "$PROFILE" --owner-ids self --query "Snapshots[*].{Id:SnapshotId, Time:StartTime, Tags:Tags}" --output json)
while read -r snapshot; do
    SID=$(echo "$snapshot" | jq -r '.Id')
    STIME=$(echo "$snapshot" | jq -r '.Time')
    TAGS=$(echo "$snapshot" | jq -c '.Tags')
    
    if [[ "$STIME" < "$THIRTY_DAYS_AGO" ]]; then
        MATCH=false
        # Filter tags ManagedBy=Terraform OR Project='Curso AWS com Terraform' OR Owner='Cleber Gasparoto'
        if echo "$TAGS" | jq -e '.[] | select(.Key=="ManagedBy" and .Value=="Terraform")' >/dev/null 2>&1; then MATCH=true; fi
        if echo "$TAGS" | jq -e '.[] | select(.Key=="Project" and .Value=="Curso AWS com Terraform")' >/dev/null 2>&1; then MATCH=true; fi
        if echo "$TAGS" | jq -e '.[] | select(.Key=="Owner" and .Value=="Cleber Gasparoto")' >/dev/null 2>&1; then MATCH=true; fi
        
        if [ "$MATCH" = true ]; then
            echo "Deleting Snapshot: $SID (Created: $STIME)"
            if aws ec2 delete-snapshot --snapshot-id "$SID" --region "$REGION" --profile "$PROFILE" 2>/dev/null; then
                ((SNAPSHOT_COUNT++))
            else
                echo "Error deleting snapshot $SID"
                ERRORS+=("Snapshot $SID")
            fi
        fi
    fi
done < <(echo "$SNAPSHOTS_JSON" | jq -c '.[]')

# 4) Load balancers
# Classic
CLB_NAMES=$(aws elb describe-load-balancers --region "$REGION" --profile "$PROFILE" --query "LoadBalancerDescriptions[*].LoadBalancerName" --output text)
for name in $CLB_NAMES; do
    echo "Deleting Classic ELB: $name"
    if aws elb delete-load-balancer --load-balancer-name "$name" --region "$REGION" --profile "$PROFILE" 2>/dev/null; then
        ((ELB_COUNT++))
    else
        echo "Error deleting Classic ELB $name"
        ERRORS+=("CLB $name")
    fi
done
# ELBv2
ALB_ARNS=$(aws elbv2 describe-load-balancers --region "$REGION" --profile "$PROFILE" --query "LoadBalancers[*].LoadBalancerArn" --output text)
for arn in $ALB_ARNS; do
    echo "Deleting ELBv2: $arn"
    if aws elbv2 delete-load-balancer --load-balancer-arn "$arn" --region "$REGION" --profile "$PROFILE" 2>/dev/null; then
        ((ELB_COUNT++))
    else
        echo "Error deleting ELBv2 $arn"
        ERRORS+=("ELBv2 $arn")
    fi
done

# 5) NAT gateways
NAT_IDS=$(aws ec2 describe-nat-gateways --region "$REGION" --profile "$PROFILE" --filter "Name=state,Values=available,pending" --query "NatGateways[*].NatGatewayId" --output text)
for id in $NAT_IDS; do
    echo "Deleting NAT Gateway: $id"
    if aws ec2 delete-nat-gateway --nat-gateway-id "$id" --region "$REGION" --profile "$PROFILE" 2>/dev/null; then
        ((NAT_COUNT++))
    else
        echo "Error deleting NAT Gateway $id"
        ERRORS+=("NAT $id")
    fi
done

echo ""
echo "--- Cleanup Summary ---"
echo "EBS Volumes Deleted: $EBS_VOL_COUNT"
echo "Elastic IPs Released: $EIP_COUNT"
echo "Snapshots Deleted: $SNAPSHOT_COUNT"
echo "Load Balancers Deleted: $ELB_COUNT"
echo "NAT Gateways Deleted: $NAT_COUNT"
if [ ${#ERRORS[@]} -gt 0 ]; then
    echo "Errors encountered with: ${ERRORS[*]}"
fi
