#!/bin/bash

if [ $# -ne 1 ]; then
    echo "Usage) $0 \${CLUSTER_NAME}(ex. skcc05599)"
    exit 1
else
    CLUSTER_NAME=$1
fi

################################################
##### delete kubernetes ENIConfig
################################################
kubectl delete eniconfig ap-northeast-2a
kubectl delete eniconfig ap-northeast-2b
kubectl delete eniconfig ap-northeast-2c

################################################
##### SET VALUES
################################################
export EKS_CLUSTER=${CLUSTER_NAME}
export VPC_ID=$(eksctl utils describe-stacks --region=ap-northeast-2 --cluster=${EKS_CLUSTER} | grep OutputValue | grep vpc | cut -d"\"" -f2)

export CUST_SUBNET_A=`aws ec2 describe-subnets --filters Name=vpc-id,Values=$VPC_ID Name=tag:Name,Values=${EKS_CLUSTER}-PodSubnetA | jq -r .Subnets[].SubnetId`
export CUST_SUBNET_B=`aws ec2 describe-subnets --filters Name=vpc-id,Values=$VPC_ID Name=tag:Name,Values=${EKS_CLUSTER}-PodSubnetB | jq -r .Subnets[].SubnetId`
export CUST_SUBNET_C=`aws ec2 describe-subnets --filters Name=vpc-id,Values=$VPC_ID Name=tag:Name,Values=${EKS_CLUSTER}-PodSubnetC | jq -r .Subnets[].SubnetId`

export RTA_ID_A=`aws ec2 describe-route-tables --filters Name=vpc-id,Values=$VPC_ID | jq -r --arg CUST_SUBNET "${CUST_SUBNET_A}" '.RouteTables[].Associations[] | select (.SubnetId==$CUST_SUBNET) | .RouteTableAssociationId'`
export RTA_ID_B=`aws ec2 describe-route-tables --filters Name=vpc-id,Values=$VPC_ID | jq -r --arg CUST_SUBNET "${CUST_SUBNET_B}" '.RouteTables[].Associations[] | select (.SubnetId==$CUST_SUBNET) | .RouteTableAssociationId'`
export RTA_ID_C=`aws ec2 describe-route-tables --filters Name=vpc-id,Values=$VPC_ID | jq -r --arg CUST_SUBNET "${CUST_SUBNET_C}" '.RouteTables[].Associations[] | select (.SubnetId==$CUST_SUBNET) | .RouteTableAssociationId'`

echo "# VPC_ID        : ${VPC_ID}"

echo "# CUST_SUBNET_A : ${CUST_SUBNET_A}"
echo "# CUST_SUBNET_B : ${CUST_SUBNET_B}"
echo "# CUST_SUBNET_C : ${CUST_SUBNET_C}"

echo "# RTA_ID_A      : ${RTA_ID_A}"
echo "# RTA_ID_B      : ${RTA_ID_B}"
echo "# RTA_ID_C      : ${RTA_ID_C}"

################################################
##### disassociate pod subnet from route-table
################################################
aws ec2 disassociate-route-table --association-id ${RTA_ID_A}
aws ec2 disassociate-route-table --association-id ${RTA_ID_B}
aws ec2 disassociate-route-table --association-id ${RTA_ID_C}

################################################
##### delete pod subnet
################################################
aws ec2 delete-subnet            --subnet-id      ${CUST_SUBNET_A}
aws ec2 delete-subnet            --subnet-id      ${CUST_SUBNET_B}
aws ec2 delete-subnet            --subnet-id      ${CUST_SUBNET_C}

