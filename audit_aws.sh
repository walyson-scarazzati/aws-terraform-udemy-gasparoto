#!/bin/bash
PROFILE="default"
# Get clean list of regions (remove any trailing characters/newlines)
REGIONS=$(aws ec2 describe-regions --all-regions --query 'Regions[?OptInStatus==`opt-in-not-required`||OptInStatus==`opted-in`].RegionName' --output text --profile "$PROFILE" | tr '\t' '\n' | tr -d '\r')

total_rds_inst=0
total_rds_clust=0
total_rds_snap=0
total_ecr_repos=0
total_ecr_imgs=0
total_cw_groups=0
total_cw_bytes=0
declare -a cleanup_cmds

echo "Starting AWS Audit..."
echo "--------------------------------------------------------------------------------"
printf "%-20s | %-8s | %-8s | %-8s | %-8s | %-8s\n" "Region" "RDS-I" "RDS-C" "RDS-S" "ECR" "CW-LG"
echo "--------------------------------------------------------------------------------"

for region in $REGIONS; do
    region=$(echo "$region" | xargs) # strip whitespace
    [ -z "$region" ] && continue

    # RDS Instances
    RDS_INST=$(aws rds describe-db-instances --region "$region" --profile "$PROFILE" --query "DBInstances[*].DBInstanceIdentifier" --output json 2>/dev/null)
    RDS_INST_COUNT=$(echo "$RDS_INST" | jq '. | length' 2>/dev/null || echo 0)
    
    # RDS Clusters
    RDS_CLUST=$(aws rds describe-db-clusters --region "$region" --profile "$PROFILE" --query "DBClusters[*].DBClusterIdentifier" --output json 2>/dev/null)
    RDS_CLUST_COUNT=$(echo "$RDS_CLUST" | jq '. | length' 2>/dev/null || echo 0)
    
    # RDS Snapshots (Manual)
    RDS_SNAP_M=$(aws rds describe-db-snapshots --snapshot-type manual --region "$region" --profile "$PROFILE" --query "DBSnapshots[*].DBSnapshotIdentifier" --output json 2>/dev/null)
    RDS_SNAP_C=$(aws rds describe-db-cluster-snapshots --snapshot-type manual --region "$region" --profile "$PROFILE" --query "DBClusterSnapshots[*].DBClusterSnapshotIdentifier" --output json 2>/dev/null)
    SNAP_M_LEN=$(echo "$RDS_SNAP_M" | jq '. | length' 2>/dev/null || echo 0)
    SNAP_C_LEN=$(echo "$RDS_SNAP_C" | jq '. | length' 2>/dev/null || echo 0)
    RDS_SNAP_COUNT=$((SNAP_M_LEN + SNAP_C_LEN))

    # ECR
    ECR_REPOS=$(aws ecr describe-repositories --region "$region" --profile "$PROFILE" --query "repositories[*].repositoryName" --output json 2>/dev/null)
    ECR_REPO_COUNT=$(echo "$ECR_REPOS" | jq '. | length' 2>/dev/null || echo 0)
    ECR_IMG_COUNT=0
    if [ "$ECR_REPO_COUNT" -gt 0 ]; then
        for repo in $(echo "$ECR_REPOS" | jq -r '.[]'); do
            IMG_COUNT=$(aws ecr describe-images --repository-name "$repo" --region "$region" --profile "$PROFILE" --query "imageDetails[*]" --output json 2>/dev/null | jq '. | length')
            ECR_IMG_COUNT=$((ECR_IMG_COUNT + IMG_COUNT))
            cleanup_cmds+=("aws ecr delete-repository --repository-name $repo --region $region --force")
        done
    fi

    # CW Logs (Active only)
    CW_GROUPS=$(aws logs describe-log-groups --region "$region" --profile "$PROFILE" --query "logGroups[?storedBytes > \`0\`].{name:logGroupName, bytes:storedBytes}" --output json 2>/dev/null)
    CW_COUNT=$(echo "$CW_GROUPS" | jq '. | length' 2>/dev/null || echo 0)
    CW_BYTES=$(echo "$CW_GROUPS" | jq -r 'map(.bytes) | add // 0' 2>/dev/null || echo 0)

    # Accumulate Totals
    total_rds_inst=$((total_rds_inst + RDS_INST_COUNT))
    total_rds_clust=$((total_rds_clust + RDS_CLUST_COUNT))
    total_rds_snap=$((total_rds_snap + RDS_SNAP_COUNT))
    total_ecr_repos=$((total_ecr_repos + ECR_REPO_COUNT))
    total_ecr_imgs=$((total_ecr_imgs + ECR_IMG_COUNT))
    total_cw_groups=$((total_cw_groups + CW_COUNT))
    total_cw_bytes=$((total_cw_bytes + CW_BYTES))

    # Display region if resources exist
    if [ $((RDS_INST_COUNT + RDS_CLUST_COUNT + RDS_SNAP_COUNT + ECR_REPO_COUNT + CW_COUNT)) -gt 0 ]; then
        printf "%-20s | %-8s | %-8s | %-8s | %-8s | %-8s\n" "$region" "$RDS_INST_COUNT" "$RDS_CLUST_COUNT" "$RDS_SNAP_COUNT" "$ECR_REPO_COUNT" "$CW_COUNT"
        
        # Cleanup candidates
        for id in $(echo "$RDS_INST" | jq -r '.[]' 2>/dev/null); do cleanup_cmds+=("aws rds delete-db-instance --db-instance-identifier $id --skip-final-snapshot --region $region"); done
        for id in $(echo "$RDS_CLUST" | jq -r '.[]' 2>/dev/null); do cleanup_cmds+=("aws rds delete-db-cluster --db-cluster-identifier $id --skip-final-snapshot --region $region"); done
        for id in $(echo "$RDS_SNAP_M" | jq -r '.[]' 2>/dev/null); do cleanup_cmds+=("aws rds delete-db-snapshot --db-snapshot-identifier $id --region $region"); done
        for id in $(echo "$RDS_SNAP_C" | jq -r '.[]' 2>/dev/null); do cleanup_cmds+=("aws rds delete-db-cluster-snapshot --db-cluster-snapshot-identifier $id --region $region"); done
        for name in $(echo "$CW_GROUPS" | jq -r '.[].name' 2>/dev/null); do cleanup_cmds+=("aws logs delete-log-group --log-group-name $name --region $region"); done
    fi
done

echo "--------------------------------------------------------------------------------"
echo ""
echo "S3 Audit (Global)"
echo "--------------------------------------------------------------------------------"
printf "%-40s | %-15s | %-10s | %-10s\n" "Bucket Name" "Region" "Versioning" "Empty?"
echo "--------------------------------------------------------------------------------"
S3_BUCKETS=$(aws s3api list-buckets --profile "$PROFILE" --query "Buckets[*].Name" --output json 2>/dev/null)
S3_COUNT=$(echo "$S3_BUCKETS" | jq '. | length' 2>/dev/null || echo 0)

if [ "$S3_COUNT" -gt 0 ]; then
    for bucket in $(echo "$S3_BUCKETS" | jq -r '.[]'); do
        REG=$(aws s3api get-bucket-location --bucket "$bucket" --profile "$PROFILE" --query "LocationConstraint" --output text 2>/dev/null)
        [ "$REG" == "None" ] || [ "$REG" == "null" ] && REG="us-east-1"
        
        VER=$(aws s3api get-bucket-versioning --bucket "$bucket" --profile "$PROFILE" --query "Status" --output text 2>/dev/null)
        [ "$VER" == "None" ] || [ -z "$VER" ] && VER="Disabled"
        
        OBJ=$(aws s3api list-objects-v2 --bucket "$bucket" --max-keys 1 --region "$REG" --profile "$PROFILE" --query "Contents[0].Key" --output text 2>/dev/null)
        EMPTY="Yes"
        [ "$OBJ" != "None" ] && [ -n "$OBJ" ] && EMPTY="No"
        
        printf "%-40s | %-15s | %-10s | %-10s\n" "$bucket" "$REG" "$VER" "$EMPTY"
        cleanup_cmds+=("aws s3 rb s3://$bucket --force")
    done
fi
echo "--------------------------------------------------------------------------------"

echo ""
echo "Summary Totals:"
echo "RDS Instances: $total_rds_inst"
echo "RDS Clusters:  $total_rds_clust"
echo "RDS Snapshots: $total_rds_snap"
echo "ECR Repos:     $total_ecr_repos (Total Images: $total_ecr_imgs)"
echo "CW Log Groups: $total_cw_groups (Total Stored: $total_cw_bytes bytes)"
echo "S3 Buckets:    $S3_COUNT"

echo ""
echo "Cleanup Candidates (NOT EXECUTED):"
if [ ${#cleanup_cmds[@]} -eq 0 ]; then
    echo "None."
else
    for cmd in "${cleanup_cmds[@]}"; do echo "$cmd"; done
fi
