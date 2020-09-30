#!/usr/bin/env bash

TYPE="${1:-all}"
PREFIX="${2:-user}"
TEST_REGIONS="${3:-main}"

if [[ $TEST_REGIONS == "all" ]]; then
  readarray -t REGIONS < /code/supported_regions.txt
else
  REGIONS=('us-east-1')
fi

if [[ $PREFIX == "tcat" ]]; then
    PREFIX_TO_DELETE="tcat"
else
    PREFIX_TO_DELETE="oe-patterns-jitsi-${USER}"
fi

if [[ $TYPE == "all" || $TYPE == "buckets" ]]; then
    for region in ${REGIONS[@]}; do
        echo "Removing $PREFIX_TO_DELETE buckets in $region..."
        BUCKETS=`aws s3 ls --region $region | awk '{print $3}'`
        for bucket in $BUCKETS; do
            if [[ $bucket == $PREFIX_TO_DELETE* ]]; then
                echo $bucket
                aws s3 rb s3://$bucket --region $region --force
            fi
        done
    done
    echo "done."
fi

if [[ $TYPE == "all" || $TYPE == "snapshots" ]]; then
    for region in ${REGIONS[@]}; do
        echo "Removing $PREFIX_TO_DELETE snapshots in $region..."
        SNAPSHOTS=`aws rds describe-db-cluster-snapshots --region $region | jq -r '.DBClusterSnapshots[].DBClusterSnapshotIdentifier'`
        for snapshot in $SNAPSHOTS; do
            if [[ $snapshot == $PREFIX_TO_DELETE* ]]; then
                echo $snapshot
                aws rds delete-db-cluster-snapshot --region $region --db-cluster-snapshot-identifier $snapshot
            fi
        done
    done
    echo "done."
fi

if [[ $TYPE == "all" || $TYPE == "logs" ]]; then
    for region in ${REGIONS[@]}; do
        echo "Removing $PREFIX_TO_DELETE log groups in $region..."
        LOG_GROUPS=`aws logs describe-log-groups --region $region | jq -r '.logGroups[].logGroupName'`
        for log_group in $LOG_GROUPS; do
            if [[ $log_group == $PREFIX_TO_DELETE* || $log_group == /aws/codebuild/$PREFIX_TO_DELETE* ]]; then
                echo $log_group
                aws logs delete-log-group --region $region --log-group-name $log_group
            fi
            if [[ $PREFIX_TO_DELETE == "tcat" ]]; then
                if [[ $log_group == tCaT* || $log_group == /aws/codebuild/tCaT* ]]; then
                    echo $log_group
                    aws logs delete-log-group --region $region --log-group-name $log_group
                fi
            fi
            if [[ $log_group == /aws/rds/cluster/$PREFIX_TO_DELETE* ]]; then
                echo $log_group
                aws logs delete-log-group --region $region --log-group-name $log_group
            fi
        done
    done
    echo "done."
fi
