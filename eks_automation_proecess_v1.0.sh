# 1. Dual Cidr VPC 생성하기
#   1-0. Cloudformatioon Temaplate 확인하기 
aws s3 ls s3://resource-infra-data-d-myprj --recursive

#   1-1. Dual Cidr Base VPC 생성용 환경변수 설정하기
export CFSTACK_S3URL1="s3://resource-infra-data-d-myprj/cloudformation/eks-dualcidr/sk-IaC-infra-vpc-base-EKS-DualCIDR.yaml"
export CFSTACK_URL1=$(aws s3 presign ${CFSTACK_S3URL1})
export CFSTACK_NAME1="dualcidr-base-stack"
export CFSTACK_PROJECT1="dualcidr"
export CFSTACK_PARAM1=' ParameterKey="ProjectName",ParameterValue="'${CFSTACK_PROJECT1}'" ParameterKey="Environment",ParameterValue="product" ParameterKey="StackCreater",ParameterValue="ksk" '
export CFSTACK_TAGS1=' Key="Name",Value="ksk" Key="Env",Value="product" Key="Project",Value="'${CFSTACK_PROJECT1}'" '

#   1-1-1. CloudFormation 명령 실행하기
aws cloudformation create-stack \
--stack-name ${CFSTACK_NAME1}  \
--parameters  ${CFSTACK_PARAM1} \
--template-url ${CFSTACK_URL1} \
--tags ${CFSTACK_TAGS1}

#   1-1-2. VPC 생성 완료될 때까지 반복 확인
aws cloudformation describe-stack-events \
--stack-name ${CFSTACK_NAME1} | jq -r ".StackEvents[] | select(.LogicalResourceId==\"${CFSTACK_NAME1}\"  )  "
##   진행 중인 상황은 Output 문자열이 이렇게 나옴. =>   "ResourceStatus": "CREATE_IN_PROGRESS", "ResourceStatusReason": "User Initiated"
while true; do \
  results=$(aws cloudformation describe-stack-events \
          --stack-name ${CFSTACK_NAME1} | jq -r ".StackEvents[] | select(.LogicalResourceId==\"${CFSTACK_NAME1}\" and .ResourceStatusReason < 0 ) | .ResourceStatus ") ; \
  echo "check status : ${results} "; \
  if [ "${results}" == "CREATE_COMPLETE" ]; then break; fi; \
  sleep 5; \
done
##   최종 확인 방법 Output 문자열이 이렇게 나와야 함. => CREATE_COMPLETE

##   => 1-1-3. 삭제하기 : aws cloudformation delete-stack --stack-name ${CFSTACK_NAME1}

#   1-2. Dual Cidr Cluster VPC 생성용 환경변수 설정하기
export CFSTACK_S3URL2="s3://resource-infra-data-d-myprj/cloudformation/eks-dualcidr/sk-IaC-infra-vpc-svc-EKSCluster-DualCIDR.yaml"
export CFSTACK_URL2=$(aws s3 presign ${CFSTACK_S3URL2})
export CFSTACK_NAME2="dualcidr-eks-stack"
export CFSTACK_PARAM2=' ParameterKey="ParentVpcStack",ParameterValue="'${CFSTACK_NAME1}'" ParameterKey="StackCreater",ParameterValue="ksk" '
export CFSTACK_TAGS2=' Key="Name",Value="ksk" Key="Env",Value="product" Key="Project",Value="'${CFSTACK_PROJECT1}'" '

#   1-2-1. CloudFormation 명령 실행하기
aws cloudformation create-stack \
--stack-name ${CFSTACK_NAME2}  \
--parameters  ${CFSTACK_PARAM2} \
--template-url ${CFSTACK_URL2} \
--tags ${CFSTACK_TAGS2}

#   1-2-2. VPC 생성 완료될 때까지 반복 확인
aws cloudformation describe-stack-events \
--stack-name ${CFSTACK_NAME2} | jq -r ".StackEvents[] | select(.LogicalResourceId==\"${CFSTACK_NAME2}\"  )  "
##   진행 중인 상황은 Output 문자열이 이렇게 나옴. =>   "ResourceStatus": "CREATE_IN_PROGRESS", "ResourceStatusReason": "User Initiated"
while true; do \
  results=$(aws cloudformation describe-stack-events \
          --stack-name ${CFSTACK_NAME2} | jq -r ".StackEvents[] | select(.LogicalResourceId==\"${CFSTACK_NAME2}\" and .ResourceStatusReason < 0 ) | .ResourceStatus " ); \
  echo "check status : ${results} "; \
  if [ "${results}" == "CREATE_COMPLETE" ]; then break; fi; \
  sleep 5; \
done
##   최종 확인 방법 Output 문자열이 이렇게 나와야 함. => CREATE_COMPLETE

##   => 1-2-3. 삭제하기 : aws cloudformation delete-stack --stack-name ${CFSTACK_NAME2}

# 2. EKS Cluster 생성하기 ( 앞서 생성한 VPC 환경을 Attach하여 생성한다. )

#  2-1. Cluster 정보 및 Cluster VPC 환경을 조회 후 Cluster Network 구성을 위한 환경변수 설정하기
export CLUSTER_NAME=dualcidr-cluster
export CLUSTER_VPC_NAME=dualcidr-p-vpc               # 존재하는 VPC의 ID를 얻기 위해 Tag Name을 기준으로 조회함. < 정보 확인 할 것 >
export CLUSTER_NODESNET_KEYWORD=-dataplane-      # 1. Dual Cidr EKS용 VPC의 CF로 만들어 지면 사전 예약어로 사용하고 있어서 Tag Name에 포함된 문자열을 기준으로 조회함.
export CLUSTER_PODSNET_KEYWORD=-podnetwork-      # 1. Dual Cidr EKS용 VPC의 CF로 만들어 지면 사전 예약어로 사용하고 있어서 Tag Name에 포함된 문자열을 기준으로 조회함.
export CLUSTER_REGION="ap-northeast-2"
export CLUSTER_TAGS="{ Env: develop, Cost: a.tcl, Project.purpose: Hello }"
export CLUSTER_KUBERNETES_VERSION='"1.16"'
export CLUSTER_VPC_ID=$(aws ec2 describe-vpcs | jq -r  " .Vpcs[] | select(.Tags[].Value==\"${CLUSTER_VPC_NAME}\") | .VpcId ")
export CLUSTER_NODESNET_PUBLIC=$(aws ec2 describe-subnets | jq -r " .Subnets[] | select(.VpcId==\"${CLUSTER_VPC_ID}\") | select(.Tags[].Value | contains(\"${CLUSTER_NODESNET_KEYWORD}\")) | { az : .AvailabilityZone, sid : .SubnetId, sname : .Tags[].Value} | select(.sname | contains(\"${CLUSTER_NODESNET_KEYWORD}\")) | select(.sname | contains(\"public\")) | .sid   " | tr '\n' ',' | sed 's/,$//g' )
export CLUSTER_NODESNET_PRIVATE=$(aws ec2 describe-subnets | jq -r " .Subnets[] | select(.VpcId==\"${CLUSTER_VPC_ID}\") | select(.Tags[].Value | contains(\"${CLUSTER_NODESNET_KEYWORD}\")) | { az : .AvailabilityZone, sid : .SubnetId, sname : .Tags[].Value} | select(.sname | contains(\"${CLUSTER_NODESNET_KEYWORD}\")) | select(.sname | contains(\"private\")) | .sid   " | tr '\n' ',' | sed 's/,$//g' )

export EKSCTL_CLUSTER_DEBUG_LOG_LEVEL=3

#  2-2-1. eksctl로 Cluster 생성 명령 실행하기
#####eksctl create cluster \
#####-n ${CLUSTER_NAME} \
#####--version ${CLUSTER_KUBERNETES_VERSION} \
#####--tags ${CLUSTER_TAGS} \
#####-r ${CLUSTER_REGION} \
#####--without-nodegroup \
#####--asg-access \
#####--full-ecr-access \
#####--vpc-private-subnets "${CLUSTER_NODESNET_PUBLIC}" \
#####--vpc-public-subnets  "${CLUSTER_NODESNET_PRIVATE}" \
#####-v ${EKSCTL_CLUSTER_DEBUG_LOG_LEVEL}   

export AZ1="ap-northeast-2a"
export AZ2="ap-northeast-2c"
export CLUSTER_NODESNET_PUBLIC1=$(aws ec2 describe-subnets | jq -r " .Subnets[] | select(.VpcId==\"${CLUSTER_VPC_ID}\") | select(.Tags[].Value | contains(\"${CLUSTER_NODESNET_KEYWORD}\")) | { az : .AvailabilityZone, sid : .SubnetId, sname : .Tags[].Value} | select(.sname | contains(\"${CLUSTER_NODESNET_KEYWORD}\")) | select(.az | contains(\"${AZ1}\")) | select(.sname | contains(\"public\")) | .sid ")
export CLUSTER_NODESNET_PUBLIC2=$(aws ec2 describe-subnets | jq -r " .Subnets[] | select(.VpcId==\"${CLUSTER_VPC_ID}\") | select(.Tags[].Value | contains(\"${CLUSTER_NODESNET_KEYWORD}\")) | { az : .AvailabilityZone, sid : .SubnetId, sname : .Tags[].Value} | select(.sname | contains(\"${CLUSTER_NODESNET_KEYWORD}\")) | select(.az | contains(\"${AZ2}\")) | select(.sname | contains(\"public\")) | .sid ")
export CLUSTER_NODESNET_PRIVATE1=$(aws ec2 describe-subnets | jq -r " .Subnets[] | select(.VpcId==\"${CLUSTER_VPC_ID}\") | select(.Tags[].Value | contains(\"${CLUSTER_NODESNET_KEYWORD}\")) | { az : .AvailabilityZone, sid : .SubnetId, sname : .Tags[].Value} | select(.sname | contains(\"${CLUSTER_NODESNET_KEYWORD}\")) | select(.az | contains(\"${AZ1}\")) | select(.sname | contains(\"private\")) | .sid ")
export CLUSTER_NODESNET_PRIVATE2=$(aws ec2 describe-subnets | jq -r " .Subnets[] | select(.VpcId==\"${CLUSTER_VPC_ID}\") | select(.Tags[].Value | contains(\"${CLUSTER_NODESNET_KEYWORD}\")) | { az : .AvailabilityZone, sid : .SubnetId, sname : .Tags[].Value} | select(.sname | contains(\"${CLUSTER_NODESNET_KEYWORD}\")) | select(.az | contains(\"${AZ2}\")) | select(.sname | contains(\"private\")) | .sid ")


cat << EOF > ekscluster.yml
apiVersion: eksctl.io/v1alpha5
kind: ClusterConfig
metadata:
  name: ${CLUSTER_NAME}
  region: ${CLUSTER_REGION}
  version: ${CLUSTER_KUBERNETES_VERSION}
  tags: ${CLUSTER_TAGS}
vpc:
  id: ${CLUSTER_VPC_ID}
  subnets:
    public:
        ap-northeast-2a:
            id: ${CLUSTER_NODESNET_PUBLIC1}
        ap-northeast-2c:
            id: ${CLUSTER_NODESNET_PUBLIC2}
    private:
      ap-northeast-2a:
          id: ${CLUSTER_NODESNET_PRIVATE1}
      ap-northeast-2c:
          id: ${CLUSTER_NODESNET_PRIVATE2}
  clusterEndpoints:
      privateAccess: true
      publicAccess: true
EOF

eksctl create cluster -f ekscluster.yml  

#    => 2-2-2. Cluster 삭제하기 : eksctl delete cluster --name ${CLUSTER_NAME} 
#                                 eksctl delete cluster -f ekscluster.yml 

# 3. Dual CIDR의 보조 VPC CIDR로 구성된 Pod용 subnet을 Cluster에 추가하고, POD 전용 NETWORK 설정을 위해 AWS용에서 제공하는 CNI를 사용하도록 설정하기
# 참고 URL : https://docs.aws.amazon.com/ko_kr/eks/latest/userguide/cni-custom-network.html

#  3-1. Pod Subnet을 Cluster에 추가하기 위하여 Subnet에 예약된 Tag 정보를 셋팅한다.
aws ec2 describe-subnets | jq -r " .Subnets[] | select(.VpcId==\"${CLUSTER_VPC_ID}\") | select(.Tags[].Value | contains(\"${CLUSTER_PODSNET_KEYWORD}\")) | { az : .AvailabilityZone, sid : .SubnetId, sname : .Tags[].Value} | select(.sname | contains(\"${CLUSTER_PODSNET_KEYWORD}\")) | .sid " | awk -v CLUSTER_NAME=${CLUSTER_NAME} '{ print "aws ec2 create-tags --resources ",$1, " --tags Key=kubernetes.io/cluster/"CLUSTER_NAME",Value=shared  " }' | sh
# => "${MY_VPC} 변수 값을 vpc tag 정보로 vpcid를 얻은 후 이를 ${CLUSTER_VPC_ID}에 저장하고, 해당 변수와 ${CLUSTER_PODSNET_KEYWORD} tag를 갖는 subnet id 정보 조회 후 tag 정보를 자동으로 추가하기 명령어 실행 ( kubernetes.io/cluster/${CLUSTER_PODSNET_KEYWORD}, shared )"

#  3-2. CNI 플러그인에 대한 사용자 지정 네트워크 구성을 활성화한다. 
kubectl set env daemonset aws-node -n kube-system AWS_VPC_K8S_CNI_CUSTOM_NETWORK_CFG=true

#  3-3.  기본적으로 Kubernetes는 가용 영역 노드의 failure-domain.beta.kubernetes.io/zone 레이블을 추가한다.
kubectl set env daemonset aws-node -n kube-system ENI_CONFIG_LABEL_DEF=failure-domain.beta.kubernetes.io/zone

#  3-4. 현재 설치되어 있는 CNI 버전 조회하기
kubectl describe daemonset aws-node --namespace kube-system | grep Image | cut -d "/" -f 2
kubectl describe daemonset aws-node --namespace kube-system

#  3-4. if CNI 버전 < 1.3 then ENIConfig 사용자 지정 리소스 정의를 설치하려면 다음 명령을 실행합니다.
#       CRD Object를 Cluster Scope로 ENIConfig를 생성한다.
cat << EOF | kubectl apply -f -
apiVersion: apiextensions.k8s.io/v1beta1
kind: CustomResourceDefinition
metadata:
  name: eniconfigs.crd.k8s.amazonaws.com
spec:
  scope: Cluster
  group: crd.k8s.amazonaws.com
  version: v1alpha1
  names:
    plural: eniconfigs
    singular: eniconfig
    kind: ENIConfig
EOF

#        Region의 Available Zone에 해당하는 Pod Network 정보를 셋팅한 ENIConfig Object를 생성한다.  
#        => 모든 서브넷 및 가용 영역에 대해 ENIConfig 사용자 지정 리소스를 생성하려면 다음 명령을 실행합니다.
export AZ1="ap-northeast-2a"
export AZ2="ap-northeast-2c"
export CUST_SNET1=$(aws ec2 describe-subnets | jq -r " .Subnets[] | select(.VpcId==\"${CLUSTER_VPC_ID}\") | select(.Tags[].Value | contains(\"${CLUSTER_PODSNET_KEYWORD}\")) | { az : .AvailabilityZone, sid : .SubnetId, sname : .Tags[].Value} | select(.sname | contains(\"${CLUSTER_PODSNET_KEYWORD}\")) | select(.az | contains(\"${AZ1}\")) | .sid ")
export CUST_SNET2=$(aws ec2 describe-subnets | jq -r " .Subnets[] | select(.VpcId==\"${CLUSTER_VPC_ID}\") | select(.Tags[].Value | contains(\"${CLUSTER_PODSNET_KEYWORD}\")) | { az : .AvailabilityZone, sid : .SubnetId, sname : .Tags[].Value} | select(.sname | contains(\"${CLUSTER_PODSNET_KEYWORD}\")) | select(.az | contains(\"${AZ2}\")) | .sid ")

#        eks Cluster 생성될 때 만들어진 security group 정보 얻기
TMP_FILE=/tmp/${CLUSTER_NAME}.log
aws ec2 describe-security-groups  | jq -r --arg VPC "${CLUSTER_VPC_ID}" --arg CLST "${CLUSTER_NAME}" '.SecurityGroups[] | select(.VpcId | startswith($VPC)) | select(.GroupName | contains($CLST)) | .GroupId' > ${TMP_FILE}
readarray -t SG_ARRAY < ${TMP_FILE}
rm -rf ${TMP_FILE}

echo "${SG_ARRAY[*]}"

#        포드를 예약하려는 각 서브넷에 대해 ENIConfig 사용자 지정 리소스를 생성합니다.
cat <<EOF  | kubectl apply -f -
apiVersion: crd.k8s.amazonaws.com/v1alpha1
kind: ENIConfig
metadata:
 name: $AZ1
spec:
  subnet: $CUST_SNET1
  securityGroups:
    - ${SG_ARRAY[0]}
    - ${SG_ARRAY[1]}
    - ${SG_ARRAY[2]}
EOF

cat <<EOF | kubectl apply -f -
apiVersion: crd.k8s.amazonaws.com/v1alpha1
kind: ENIConfig
metadata:
 name: $AZ2
spec:
  subnet: $CUST_SNET2
  securityGroups:
    - ${SG_ARRAY[0]}
    - ${SG_ARRAY[1]}
    - ${SG_ARRAY[2]}
EOF

#  4. eksctl로 Cluster의 Node Group 생성 명령 실행하기
#    4-1. Managed Node Group 환경변수 설정하기
export CLUSTER_NODEGROUP_NAME=dualcidr-mngrp
export CLUSTER_NODEGROUP_TAGS="{ Creater: kskng, Env: dev }" 
export CLUSTER_NODEGROUP_LABELS="{ ksk.node.role: WORKER, ksk.creater: ksk10 }"
export CLUSTER_NODE_INS_TYPE="t2.large"  # t2.large
export CLUSTER_NODESNET_PRIVATE_NETWORKING="true"
export CLUSTER_NODE_VOLUME=30
export CLUSTER_NODES_MIN_COUNT=1
export CLUSTER_NODES_MAX_COUNT=3
export CLUSTER_NODES_DESIRED_COUNT=2

# cluster managed node 생성하기 
cat << EOF > eksnodegroup-managed.yml
apiVersion: eksctl.io/v1alpha5
kind: ClusterConfig
metadata:
    name: ${CLUSTER_NAME}
    region: ${CLUSTER_REGION}
managedNodeGroups:
  - name: ${CLUSTER_NODEGROUP_NAME}
    desiredCapacity: ${CLUSTER_NODES_DESIRED_COUNT}
    minSize: ${CLUSTER_NODES_MIN_COUNT} 
    maxSize: ${CLUSTER_NODES_MAX_COUNT} 
    volumeSize: ${CLUSTER_NODE_VOLUME}
    labels: ${CLUSTER_NODEGROUP_LABELS}
    tags: ${CLUSTER_NODEGROUP_TAGS}    
    instanceType: ${CLUSTER_NODE_INS_TYPE}
    privateNetworking: ${CLUSTER_NODESNET_PRIVATE_NETWORKING}
EOF

eksctl create nodegroup --config-file=eksnodegroup-managed.yml
# managed node는 eks용 최신 AMI Linux2 기반의 AMI 최신버전을 선택하여 생성됨.
# managed node에서 custom AMI를 선택할 수 있는 방법 없음. 
#                  tag 정보도 unmagnaed node group 과 다르게 autoscaling group에서 만들어지는 Instance로 전파되지 않음. instance tag name을 수동 추가해야 함.

export CLUSTER_NODEGROUP_AZS='"ap-northeast-2a","ap-northeast-2c"'
export CLUSTER_NODE_INS_AMI='"ami-0c25ff54ef142ea27"'
export CLUSTER_NODE_SSH_PUBLIC_KEY=ffpoffice    # EC2 - Key Pairs

export EKSCTL_CLUSTER_NODEGROUP_DEBUG_LOG_LEVEL=3

######eksctl create ng \
######--region ${CLUSTER_REGION} \
######--cluster ${CLUSTER_NAME} \
######--name ${CLUSTER_NODEGROUP_NAME} \
######--node-type ${CLUSTER_NODE_INS_TYPE} \
######--ssh-access \
######--ssh-public-key ${CLUSTER_NODE_SSH_PUBLIC_KEY} \
######--node-private-networking \
######--node-zones ${CLUSTER_NODEGROUP_AZS} \
######--nodes ${CLUSTER_NODES_DESIRED_COUNT} \
######--nodes-min ${CLUSTER_NODES_MIN_COUNT} \
######--nodes-max ${CLUSTER_NODES_MAX_COUNT} \
######--node-ami ${CLUSTER_NODE_INS_AMI} \
######--node-volume-size ${CLUSTER_NODE_VOLUME} \
######--node-labels ${CLUSTER_NODEGROUP_LABELS} \
######--tags ${CLUSTER_NODEGROUP_TAGS} \
######-v ${EKSCTL_CLUSTER_NODEGROUP_DEBUG_LOG_LEVEL} 
######
######< unmanaged 인 상기 건은 Nodegroup 은 만들어 지지만, EC2가 생성되었음에도 node를 포함시킬 수 없다고 오류가 발생함 : 확인 필요 >

#    4-2. Unmanaged Managed Node Group 환경변수 설정하기
export CLUSTER_NODEGROUP_NAME1=dualcidr-ngrp
export CLUSTER_NODEGROUP_TAGS1="{ Creater: kskng, Env: dev }" 
export CLUSTER_NODEGROUP_LABELS1="{ ksk.node.role: WORKER, ksk.creater: ksk10 }"
export CLUSTER_NODE_INS_TYPE1="t2.large"  # t2.large
export CLUSTER_NODESNET_PRIVATE_NETWORKING1="true"
export CLUSTER_NODE_VOLUME1=30
export CLUSTER_NODES_MIN_COUNT1=1
export CLUSTER_NODES_MAX_COUNT1=3
export CLUSTER_NODES_DESIRED_COUNT1=2
export CLUSTER_NODEGROUP_AZS1='"ap-northeast-2a","ap-northeast-2c"'
export CLUSTER_NODE_INS_AMI1='"ami-0c25ff54ef142ea27"'
export CLUSTER_MAX_PODS_PER_NODE1=2
export CLUSTER_NODE_SSH_PUBLIC_KEY1=ffpoffice    # EC2 - Key Pairs

cat << EOF > eksnodegroup.yml
apiVersion: eksctl.io/v1alpha5
kind: ClusterConfig
metadata:
    name: ${CLUSTER_NAME}
    region: ${CLUSTER_REGION}
nodeGroups:
  - name: ${CLUSTER_NODEGROUP_NAME1}
    ami: ${CLUSTER_NODE_INS_AMI1}
    instanceType: ${CLUSTER_NODE_INS_TYPE1}
    privateNetworking: ${CLUSTER_NODESNET_PRIVATE_NETWORKING1}
    tags: ${CLUSTER_NODEGROUP_TAGS1}
    desiredCapacity: ${CLUSTER_NODES_DESIRED_COUNT1}
    minSize: ${CLUSTER_NODES_MIN_COUNT1} 
    maxSize: ${CLUSTER_NODES_MAX_COUNT1} 
    volumeSize: ${CLUSTER_NODE_VOLUME1}
    maxPodsPerNode: ${CLUSTER_MAX_PODS_PER_NODE1}
    labels: ${CLUSTER_NODEGROUP_LABELS1}
EOF

eksctl create nodegroup --config-file=eksnodegroup.yml 

# 4-2-1. cluster, node group 정보 조회하기
eksctl get cluster -n dualcidr-cluster
eksctl get nodegroup --cluster dualcidr-cluster
eksctl utils nodegroup-health --name=dualcidr-mngrp --cluster=dualcidr-cluster

#    => 4-2-2. Cluster Node Scale 조정하기 : eksctl scale nodegroup --cluster=${CLUSTER_NAME} --nodes=${CLUSTER_NODES_DESIRED_COUNT} --name=${CLUSTER_NODEGROUP_NAME}
#    => 4-2-3. Cluster NodeGroup  삭제하기 : eksctl delete nodegroup --cluster=${CLUSTER_NAME} --name=${CLUSTER_NODEGROUP_NAME}
#                                           eksctl delete nodegroup -f eksnodegroup-managed2.yml  --approve
#    => 4-2-4. Cluster NodeGroup을 Draining 실행하기 : eksctl drain nodegroup --cluster=${CLUSTER_NAME} --name=${CLUSTER_NODEGROUP_NAME}
#    => 4-2-5. Cluster NodeGroup을 Draining 실행을 취소하기 : eksctl drain nodegroup --cluster=${CLUSTER_NAME} --name=${CLUSTER_NODEGROUP_NAME} --undo
#    => 4-2-6. Cluster의 특정 Node만 Draining 실행하기 : 1. 조회하기 - kubectl get nodes  2. 실행하기 - kubectl drain <node_name> --ignore-daemonsets
#    => 4-2-7. Cluster NodeGroup 조회하기 : eksctl get nodegroup --cluster ${CLUSTER_NAME}

#######################################################################################
# 5. K8S 기본 구성
#######################################################################################
# 5-0. 신규 Instance에서 Cluster 정보를 Local에 설정하기 ( https://aws.amazon.com/ko/premiumsupport/knowledge-center/eks-api-server-unauthorized-error/ )
aws eks --region ap-northeast-2 update-kubeconfig --name dualcidr-cluster
#    5-0-1. Cluster 정보 조회 
#         전체 목록 조회            : kubectl config get-contexts
#         특정 Cluster환경으로 변경 : kubectl config use-context gcp-context
#    Cluster 생성자인 경우와 Cluster 생성자가 아닌 경우의 처리 방법 차이 있음.

################################################
# [ 5-1. HELM 설치 ]  ( https://helm.sh/docs/ , https://github.com/helm/charts )
#   - 작업경로 : 02.HELM3
################################################

# 5-1-1. 설치 (https://helm.sh/docs/intro/install/)
curl -fsSLk -o get_helm.sh https://raw.githubusercontent.com/helm/helm/master/scripts/get-helm-3
chmod 700 get_helm.sh
./get_helm.sh

# 5-1-2. chart의 원격 repostory를 stable 이름으로 추가 (https://helm.sh/docs/intro/quickstart/)
helm repo add stable https://kubernetes-charts.storage.googleapis.com/
helm search repo stable
helm repo update  # Make sure we get the latest list of charts

# 5-1-3. repoitory 목록 조회
helm repo list

################################################
# [ 5-2. Nginx ingress controller 설치 ]
#   - 작업경로 : 03.NGINX-INGRESS-CONTROLLER
################################################

# 5-2-1. "infra" namespace 생성(infra 관리용)
kubectl create namespace infra

# 5-2-2. nginx-ingress chart local로 다운하기
helm fetch stable/nginx-ingress

# 5-2-3. deploy external service
#     1. value.yaml 파일에 ingtress-controller 용 public nlb 설정. - non SSL
#        service:
#            enabled: true
#        
#            annotations:
#              service.beta.kubernetes.io/aws-load-balancer-type: nlb
#            labels:
#              app.kubernetes.io/creater: ksk
#              helm.sh/char: ingress-nginx-1.41.2
#     ========================[ https SSL 적용 방법 ]=======================
#     2. value.yaml 파일에 ingtress-controller 용 public nlb 설정. - SSL을 적용하려는 경우
#        service:
#            enabled: true
#        
#            annotations:
#              service.beta.kubernetes.io/aws-load-balancer-type: nlb
#              service.beta.kubernetes.io/aws-load-balancer-ssl-cert: "(SSL Domain)ACM을 사용한다면, ACM의 arn 정보"
#              service.beta.kubernetes.io/aws-load-balancer-backend-protocol: "tcp"
#              service.beta.kubernetes.io/aws-load-balancer-ssl-ports: "https"
#              service.beta.kubernetes.io/aws-load-balancer-connection-idle-timeout: "3600"
#            labels:
#              app.kubernetes.io/creater: ksk
#              helm.sh/char: ingress-nginx-1.41.2
#            targetPorts:
#              http: http
#              https: http      # NLB에서 SSL Offload를 하게 되면, 내부호출은 http로 변환 호출하도록 설정
helm install nginx-ingress-external-ssl stable/nginx-ingress -f  values.yaml.nginx-ingress-1.41.2.external.ssl -n infra

# 5-2-4.  deploy internal service
#     1. value.yaml 파일에 ingtress-controller 용 public nlb 설정
#        service:
#            enabled: true
#        
#            annotations:
#              service.beta.kubernetes.io/aws-load-balancer-type: nlb
#              service.beta.kubernetes.io/aws-load-balancer-internal: "true"
#            labels:
#              app.kubernetes.io/creater: ksk
#              helm.sh/char: ingress-nginx-1.41.2
#     ========================[ https SSL 적용 방법 ]=======================
#     2. value.yaml 파일에 ingtress-controller 용 public nlb 설정. - SSL을 적용하려는 경우
#        service:
#            enabled: true
#        
#            annotations:
#              service.beta.kubernetes.io/aws-load-balancer-type: nlb
#              service.beta.kubernetes.io/aws-load-balancer-internal: "true"
#              service.beta.kubernetes.io/aws-load-balancer-ssl-cert: "(SSL Domain)ACM을 사용한다면, ACM의 arn 정보"
#              service.beta.kubernetes.io/aws-load-balancer-backend-protocol: "tcp"
#              service.beta.kubernetes.io/aws-load-balancer-ssl-ports: "https"
#              service.beta.kubernetes.io/aws-load-balancer-connection-idle-timeout: "3600"
#            labels:
#              app.kubernetes.io/creater: ksk
#              helm.sh/char: ingress-nginx-1.41.2
#            targetPorts:
#              http: http
#              https: http      # NLB에서 SSL Offload를 하게 되면, 내부호출은 http로 변환 호출하도록 설정
helm install nginx-ingress-internal-ssl stable/nginx-ingress -f  values.yaml.nginx-ingress-1.41.2.internal.ssl -n infra


# 5-2-5. 설치 확인 -  helm list
helm list -n infra

# 6. Sample App 배포하기 
# 6-1. "app" namespace 생성(appliction 관리용)
export APP_NAMESPACE="fruits"
kubectl create namespace ${APP_NAMESPACE}

# 6-2. create service apple
cat <<EOF | kubectl apply -f -
kind: Pod
apiVersion: v1
metadata:
  name: apple-app
  namespace: ${APP_NAMESPACE}
  labels:
    app: apple
spec:
  containers:
    - name: apple-app
      image: hashicorp/http-echo
      args:
        - "-text=apple"
---
kind: Service
apiVersion: v1
metadata:
  name: apple-service
  namespace: ${APP_NAMESPACE}
spec:
  selector:
    app: apple
  ports:
    - port: 5678 # Default port for image	
EOF

# 6-3. create service banana
cat <<EOF | kubectl apply -f -
kind: Pod
apiVersion: v1
metadata:
  name: banana-app
  namespace: ${APP_NAMESPACE}
  labels:
    app: banana
spec:
  containers:
    - name: banana-app
      image: hashicorp/http-echo
      args:
        - "-text=banana"
---
kind: Service
apiVersion: v1
metadata:
  name: banana-service
  namespace: ${APP_NAMESPACE}
spec:
  selector:
    app: banana
  ports:
    - port: 5678 # Default port for image
EOF

# 6-4. Create Ingress in Public Ingress Controller
# 6-4-1. NLB hostname 
export PUBLIC_INGRESS_SVC_HOSTNAME=`kubectl -n infra get svc nginx-ingress-external-ssl-controller -o json | jq -r '.status.loadBalancer.ingress[].hostname'`
echo "${PUBLIC_INGRESS_SVC_HOSTNAME}"
cat <<EOF | kubectl apply -f -
apiVersion: extensions/v1beta1
kind: Ingress
metadata:
  name: nlb-ingress-pub-host
  namespace: ${APP_NAMESPACE}
  annotations:
    kubernetes.io/ingress.class: nginx
    #nginx.ingress.kubernetes.io/ssl-redirect: "false"
    #nginx.ingress.kubernetes.io/force-ssl-redirect: "false"
    #nginx.ingress.kubernetes.io/rewrite-target: /
spec:
  rules:
  - host: ${PUBLIC_INGRESS_SVC_HOSTNAME}
    http:
      paths:
        - path: /simple/apple
          backend:
            serviceName: apple-service 
            servicePort: 5678
        - path: /simple/banana
          backend:
            serviceName: banana-service 
            servicePort: 5678
  # This section is only required if TLS is to be enabled for the Ingress
  #tls:
  #    - hosts:
  #        - www.example.com
  #      secretName: example-tls
EOF

# 6-4-2. NLB DNS URL
# Route53 의 Hosted zones ( public dualcidr.com )에 sub domain을 등록한다. Domain의 target은 Public 용 NLB의 ARN 정보
export PUBLIC_INGRESS_SVC_DNSNAME="api.dualcidr.com"
echo "${PUBLIC_INGRESS_SVC_DNSNAME}"
cat <<EOF | kubectl apply -f -
apiVersion: extensions/v1beta1
kind: Ingress
metadata:
  name: nlb-ingress-pub-dns
  namespace: ${APP_NAMESPACE}
  annotations:
    kubernetes.io/ingress.class: nginx
    #nginx.ingress.kubernetes.io/ssl-redirect: "false"
    #nginx.ingress.kubernetes.io/force-ssl-redirect: "false"
    #nginx.ingress.kubernetes.io/rewrite-target: /
spec:
  rules:
  - host: ${PUBLIC_INGRESS_SVC_DNSNAME}
    http:
      paths:
        - path: /simple/apple
          backend:
            serviceName: apple-service 
            servicePort: 5678
        - path: /simple/banana
          backend:
            serviceName: banana-service 
            servicePort: 5678
  # This section is only required if TLS is to be enabled for the Ingress
  #tls:
  #    - hosts:
  #        - www.example.com
  #      secretName: example-tls
EOF

# 6-4-3. Applicaiton SVC Test
echo "http://${PUBLIC_INGRESS_SVC_HOSTNAME}/simple/apple"
echo "http://${PUBLIC_INGRESS_SVC_HOSTNAME}/simple/banana"
echo "http://${PUBLIC_INGRESS_SVC_DNSNAME}/simple/apple"
echo "http://${PUBLIC_INGRESS_SVC_DNSNAME}/simple/banana"

#  Bastion Server에서 Curl을 이용한 테스트를 진행할 때의 오류사항
#  접속 권한이 없어서 URL 호출 에러가 발생 :  Security Group 설정 필요
#   => Node Instance에서 설정이 되는 Security에 Basstion Security group을 Inboud 허용으로 추가하기
#      (Description : EKS created security group applied to ENI that is attached to EKS Control Plane master nodes, as well as any managed workloads.)

# 6-5. Create Ingress in Internal Ingress Controller
# 6-5-1. NLB hostname 
export PRIVATE_INGRESS_SVC_HOSTNAME=`kubectl -n infra get svc nginx-ingress-internal-ssl-controller -o json | jq -r '.status.loadBalancer.ingress[].hostname'`
echo "${PRIVATE_INGRESS_SVC_HOSTNAME}"
cat <<EOF | kubectl apply -f -
apiVersion: extensions/v1beta1
kind: Ingress
metadata:
  name: nlb-ingress-internal-host
  namespace: ${APP_NAMESPACE}
  annotations:
    kubernetes.io/ingress.class: nginx
    #nginx.ingress.kubernetes.io/ssl-redirect: "false"
    #nginx.ingress.kubernetes.io/force-ssl-redirect: "false"
    #nginx.ingress.kubernetes.io/rewrite-target: /
spec:
  rules:
  - host: ${PRIVATE_INGRESS_SVC_HOSTNAME}
    http:
      paths:
        - path: /simple/apple
          backend:
            serviceName: apple-service 
            servicePort: 5678
        - path: /simple/banana
          backend:
            serviceName: banana-service 
            servicePort: 5678
  # This section is only required if TLS is to be enabled for the Ingress
  #tls:
  #    - hosts:
  #        - www.example.com
  #      secretName: example-tls
EOF

# 6-5-2. NLB DNS URL
# Route53 의 Hosted zones ( private dualcidr.com )에 sub domain을 등록한다. :  Domain의 target은 interanl - Private 용 NLB의 ARN 정보
export PRIVATE_INGRESS_SVC_DNSNAME="api.dualcidr.com"
echo "${PRIVATE_INGRESS_SVC_DNSNAME}"
# Ingress Object는 DNS 이름이 동일하기 때문에 등록하지 않아도 됨.

# 6-5-3. Applicaiton SVC Test
echo "http://${PRIVATE_INGRESS_SVC_HOSTNAME}/simple/apple"
echo "http://${PRIVATE_INGRESS_SVC_HOSTNAME}/simple/banana"
echo "http://${PRIVATE_INGRESS_SVC_DNSNAME}/simple/apple"
echo "http://${PRIVATE_INGRESS_SVC_DNSNAME}/simple/banana"

#  resource 삭제
#  ingress 조회 :  kubectl get ingress --all-nampespaces
#  ingress 삭제 :  kubectl delete ingress nlb-ingress-internal-dns -n default

# 6-6. Sample App 추가 배포하기 : https://docs.aws.amazon.com/ko_kr/eks/latest/userguide/sample-deployment.html
# 6-6-1. my-serice sevice / deployment  배포
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Service
metadata:
  name: my-service
  namespace: ${APP_NAMESPACE}
  labels:
    app: my-app
spec:
  selector:
    app: my-app
  ports:
    - protocol: TCP
      port: 5680
      targetPort: 80
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: my-deployment
  namespace: ${APP_NAMESPACE}
  labels:
    app: my-app
spec:
  replicas: 3
  selector:
    matchLabels:
      app: my-app
  template:
    metadata:
      labels:
        app: my-app
        creater: ksk
    spec:
      containers:
      - name: nginx
        image: nginx:1.14.2
        ports:
        - containerPort: 80
EOF

# 6-6-2. nlb-ingress-pub-dns에  my-serice 정보 추가하기
# api.dualcidr.com이 Route53 서비스에 등록이 먼저 되어 있어야 함. 
# (Hosted zones 내부망/외부망용 dualcidr.com):  Domain의 target은 Public/Private 용 NLB의 ARN 정보
export PUBLIC_INGRESS_SVC_DNSNAME="api.dualcidr.com"
echo "${PUBLIC_INGRESS_SVC_DNSNAME}"
cat <<EOF | kubectl apply -f -
apiVersion: extensions/v1beta1
kind: Ingress
metadata:
  name: nlb-ingress-pub-dns
  namespace: ${APP_NAMESPACE}
  annotations:
    kubernetes.io/ingress.class: nginx
    #nginx.ingress.kubernetes.io/ssl-redirect: "false"
    #nginx.ingress.kubernetes.io/force-ssl-redirect: "false"
    #nginx.ingress.kubernetes.io/rewrite-target: /
spec:
  rules:
  - host: ${PUBLIC_INGRESS_SVC_DNSNAME}
    http:
      paths:
        - path: /simple/apple
          backend:
            serviceName: apple-service 
            servicePort: 5678
        - path: /simple/banana
          backend:
            serviceName: banana-service 
            servicePort: 5678
        - path: /simple
          backend:
            serviceName: my-service 
            servicePort: 5680
  # This section is only required if TLS is to be enabled for the Ingress
  #tls:
  #    - hosts:
  #        - www.example.com
  #      secretName: example-tls
EOF

# 6-6-3. 
kubectl get pod --all-namespaces -o wide
kubectl get svc --all-namespaces -o wide
kubectl get all -n my-namespace
kubectl -n my-namespace describe service my-service
kubectl -n my-namespace describe pod my-deployment-776d8f8fd8-cdwnn
kubectl exec -it my-deployment-776d8f8fd8-cdwnn -n my-namespace -- /bin/bash
cat /etc/resolv.conf
kubectl delete namespace my-namespace

#######################################################################################
# EKS에 EFS Provisioner + GitLab + Jenkins 구성
#######################################################################################

################################################
# [ 7. EFS 볼륨 생성 ]
################################################

# 7-1. EFS 생성 시 연계를 위한 EKS Cluster 의 VPC에서 연결이 되도록 생성
# 7-2. EFS 생성 후 접속을 위한 Target Mount Network을 생성한다.
#      이때 연결을 위한 EKS WorkGroup의 Node Subnet network를 설정하고, Security Group을 Node에 설정되는 Security Group을 선택한다. ( EFS Provisioner에서 EFS 볼륨을 사용하기 위함)
#                                     (dual cidr인 경우 pod network이 아닌 node network이어야 함)
# 생성한 file system ID 획득을 위한 조회
aws efs describe-file-systems | jq -r '.FileSystems[] | { tags : .Tags[].Value, fsysid : .FileSystemId } '
# 7-3. EFS Provisioner로 EFS 설치를 위한 준비 작업 : Node 정보에 Label 추가하기
# 7-3-1. 대상 노드 조회하기
kubectl get node -n infra
# 7-3-2. 배포 대상 노드를 efs-provisiorner가 Select 할 수 있도록 Label을 추가한다. ( role=devops label )
#   중요 : 단, 이 경우는 Node가 failover 되는 경우 Label 정보가 초기화되는 것과 같이 때문에, EKS Worker Node를 만들 때 Label롤 정의하고 이를 활용하도록 하는 것이 필요하다. 
kubectl label node XXXX role=devops
kubectl get node -n infra --show-labels
# 7-3-3. helm chart 조회 및 fetch하기  : https://helm.sh/ko/docs/chart_template_guide/builtin_objects/ 
#                                      => chart 설치 않고 검증만 : helm install --dry-run --debug good-puppy ./mychart
helm repo list
helm repo update
helm search repo stable/efs-provisioner
helm fetch  stable/efs-provisioner
# 7-3-4. value.yaml 수정하기
cp efs-provisioner/value.yaml ./values.yaml.efs-provisioner.0.13.0
diff ./values.yaml.efs-provisioner.0.13.0 efs-provisioner/values.yaml
#  43,46c43,46
#  <   efsFileSystemId: fs-45f5f224
#  <   awsRegion: ap-northeast-2
#  <   path: /efs-pv
#  <   provisionerName: dualcidr.com/aws-efs
#  ---
#  >   efsFileSystemId: fs-12345678
#  >   awsRegion: us-east-2
#  >   path: /example-pv
#  >   provisionerName: example.com/aws-efs
#  49c49
#  <     isDefault: true
#  ---
#  >     isDefault: false
#  54c54
#  <     reclaimPolicy: Retain
#  ---
#  >     reclaimPolicy: Delete
#  86,87c86
#  < nodeSelector:
#  <   ksk.node.role: WORKER
#  ---
#  > nodeSelector: {}


# 7-3-5. helm install efs-provisioner 설치
helm install efs-provisioner --namespace infra -f ./values.yaml.efs-provisioner.0.13.0 stable/efs-provisioner --version v0.13.0

# 7-3-6. EFS 기능 테스트 App 배포 ( https://kscory.com/dev/aws/eks-efs )
# 7-3-6-1. PVC 생성
export APP_NAMESPACE="fruits"
cat <<EOF | kubectl apply -f -
kind: PersistentVolumeClaim
apiVersion: v1
metadata:
  name: efs-sample
  namespace: ${APP_NAMESPACE}
  annotations:
    volume.beta.kubernetes.io/storage-class: "aws-efs"
spec:
  accessModes:
    - ReadWriteMany
  resources:
    requests:
      storage: 1Mi
EOF

# 7-3-6-2. mount한 EFS 경로에 파일을 쓰기 test-pod와 이를 조회하는 test-pod2 배포
cat <<EOF | kubectl apply -f -
kind: Pod
apiVersion: v1
metadata:
  name: test-pod
  namespace: ${APP_NAMESPACE}
spec:
  containers:
  - name: test-pod
    image: gcr.io/google_containers/busybox:1.24
    command:
      - "/bin/sh"
    args:
      - "-c"
      - "touch /mnt/SUCCESS && exit 0 || exit 1"
    volumeMounts:
      - name: efs-pvc
        mountPath: "/mnt"
  restartPolicy: "Never"
  volumes:
    - name: efs-pvc
      persistentVolumeClaim:
        claimName: efs-sample
---
kind: Pod
apiVersion: v1
metadata:
  name: test-pod2
  namespace: ${APP_NAMESPACE}
spec:
  containers:
  - name: test-pod
    image: nginx:1.13.9-alpine
    volumeMounts:
      - name: efs-pvc
        mountPath: "/mnt"
  restartPolicy: "Never"
  volumes:
    - name: efs-pvc
      persistentVolumeClaim:
        claimName: efs-sample
---
kind: Pod
apiVersion: v1
metadata:
  name: test-pod3
  namespace: ${APP_NAMESPACE}
spec:
  containers:
  - name: test-pod
    image: nginx:1.13.9-alpine
    volumeMounts:
      - name: efs-pvc
        mountPath: "/mnt"
  restartPolicy: "Never"
  volumes:
    - name: efs-pvc
      persistentVolumeClaim:
        claimName: efs-sample
EOF

kubectl exec -it -n ${APP_NAMESPACE} pod/test-pod2 -- /bin/sh
 > cd /mnt; ls ; echo "test-pod2 write." > a.log
 > test-pod3 write action 후  cat a.log로 작성된 데이타 확인
kubectl exec -it -n ${APP_NAMESPACE} pod/test-pod3 -- /bin/sh
 > cd /mnt; ls ; cat a.log ; echo "test-pod3 write." >> a.log

################################################
# [ 8. GITLAB 구성 ]  - https://docs.gitlab.com/ee/install/docker.html, https://docs.gitlab.com/13.0/charts/index.html 
#  => Helm gitlab/gitlab은 너무 무겁고, Sub-Pack 들이 많이 뜨니, Docker 버전을 Deployment로 띄우자
#   - 작업경로 : 05.CICD/02.gitlab-ce.12.10.11
################################################

## Helm Chart 설치
#  helm repo add gitlab https://charts.gitlab.io/
#  helm repo update
#  helm get values gitlab > gitlab.yaml
#  helm upgrade gitlab gitlab/gitlab -f gitlab.yaml

# docker pull gitlab/gitlab-ce:12.1.0-ce.0
# docker images | grep gitlab-ce
# curl -s https://registry.hub.docker.com/v1/repositories/gitlab/gitlab-ce/tags
# curl -s https://registry.hub.docker.com/v1/repositories/gitlab/gitlab-ce/tags | jq . | grep name 

#  8-1. git-configmap 설정하기
# Route53 서비스에서 먼저 sub domain을 등록한다. :  Domain의 target은 Public 용 NLB의 ARN 정보 (gitlab.dualcidr.com)
cat <<EOF > gitlab-configmap.yaml
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: gitlab-hosts
  namespace: infra
  labels:
    app: gitlab-ce
    ver: 12.10.11-ce
    file: hosts
data:
  hosts: |-
    127.0.0.1       localhost
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: gitlab-ce
  namespace: infra
  labels:
    app: gitlab-ce
    ver: 12.10.11-ce
    file: gitlab.rb
data:
  gitlab.rb: |-
    external_url = 'gitlab.dualcidr.com'  # 외부접속 Domain 정보. Ingress routing url 정보와 맞추기
    nginx['client_max_body_size'] = '2048m'

    ################################
    # Prometheus ( External )
    ################################
    prometheus['enable'] = false

    #gitlab_monitor['listen_address'] = 'prometheus-server.monitoring.svc.cluster.local'
    #sidekiq['listen_address'] = 'prometheus-server.monitoring.svc.cluster.local'
    #gitlab_monitor['listen_port'] = '9168'
    #node_exporter['listen_address'] = 'prometheus-server.monitoring.svc.cluster.local:9100'
    #redis_exporter['listen_address'] = 'prometheus-server.monitoring.svc.cluster.local:9121'
    #postgres_exporter['listen_address'] = 'prometheus-server.monitoring.svc.cluster.local:9187'
    #gitaly['prometheus_listen_addr'] = "prometheus-server.monitoring.svc.cluster.local:9236"
    #gitlab_workhorse['prometheus_listen_addr'] = "prometheus-server.monitoring.svc.cluster.local:9229"

    #gitlab_rails['monitoring_whitelist'] = ['127.0.0.0/8', '192.168.0.1']

    #nginx['status']['options'] = {
    #  "server_tokens" => "off",
    #  "access_log" => "off",
    #  "allow" => "192.168.0.1",
    #  "deny" => "all",
    #}

    ################################
    # Others
    ################################
    alertmanager['enable'] = false
    node_exporter['enable'] = false
    redis_exporter['enable'] = false
    postgres_exporter['enable'] = false
    pgbouncer_exporter['enable'] = false
    grafana['enable'] = false
EOF
kubectl apply -f gitlab-configmap.yaml

# 8-2. service & pvc & ingress 설정 하기
# Gitlab용 PVC를 만든다,
# Route53 서비스에서 먼저 sub domain을 등록한다. :  Domain의 target은 Public 용 NLB의 ARN 정보
cat <<EOF > gitlab-pvc-svc-ingress.yaml
# NFS FS exports should be "no_root_squash"
---
kind: PersistentVolumeClaim
apiVersion: v1
metadata:
  name: gitlab-ce-config
  namespace: infra
  annotations:
    volume.beta.kubernetes.io/storage-class: aws-efs
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 3Gi
---
kind: PersistentVolumeClaim
apiVersion: v1
metadata:
  name: gitlab-ce-log
  namespace: infra
  annotations:
    volume.beta.kubernetes.io/storage-class: aws-efs
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 2Gi
---
kind: PersistentVolumeClaim
apiVersion: v1
metadata:
  name: gitlab-ce-data
  namespace: infra
  annotations:
    volume.beta.kubernetes.io/storage-class: aws-efs
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 10Gi
---
kind: Service
apiVersion: v1
metadata:
  name: gitlab-ce
  namespace: infra
spec:
  type: ClusterIP
  selector:
    app: gitlab-ce
  ports:
  - name: ssh
    protocol: TCP
    port: 22
    # nodePort: 30022
  - name: http
    protocol: TCP
    port: 80
    # nodePort: 30080
  - name: https
    protocol: TCP
    port: 443
    # nodePort: 30443
---
apiVersion: extensions/v1beta1
kind: Ingress
metadata:
  annotations:
    ingress.kubernetes.io/rewrite-target: /
    ingress.kubernetes.io/ssl-redirect: "false"
    kubernetes.io/ingress.class: nginx
  labels:
    app.kubernetes.io/name: gitlab-ce
  name: gitlab-ce-pub-dns
  namespace: infra
spec:
  rules:
  - host: gitlab.dualcidr.com  # 외부 접속 Domain 정보
    http:
      paths:
      - backend:
          serviceName: gitlab-ce
          servicePort: 80
        path: /
EOF
kubectl apply -f gitlab-pvc-svc-ingress.yaml

# 8-3. deployment 설정하기
cat <<EOF > deploy.gitlab-ce.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: gitlab-ce
  namespace: infra
  labels:
    app: gitlab-ce
spec:
  replicas: 1
  selector:
    matchLabels:
      app: gitlab-ce
  template:
    metadata:
      labels:
        app: gitlab-ce
    spec:
      containers:
      - name: gitlab-ce
        ports:
          - containerPort: 22
            name: ssh
          - containerPort: 80
            name: http
          - containerPort: 443
            name: https
        image: gitlab/gitlab-ce:12.10.11-ce.0
        securityContext:
          runAsUser: 0
        volumeMounts:
        - name: config
          mountPath: /etc/gitlab
        - name: log
          mountPath: /var/log/gitlab
        - name: data
          mountPath: /var/opt/gitlab
        - name: gitlab-rb
          mountPath: /etc/gitlab/gitlab.rb # /etc/gitlab/gitlab -> gitlab.rb
          subPath: gitlab.rb
      volumes:
      - name: config
        persistentVolumeClaim:
          claimName: gitlab-ce-config
      - name: log
        persistentVolumeClaim:
          claimName: gitlab-ce-log
      - name: data
        persistentVolumeClaim:
          claimName: gitlab-ce-data
      - name: gitlab-rb
        configMap:
          name: gitlab-ce
          defaultMode: 0666
EOF
kubectl apply -f deploy.gitlab-ce.yaml

# 8-4. GitLab 시스템에 접속하여 점검 및 password 설정 하기
http://gitlab.dualcidr.com/ ( root / alskfl12~! )

# 8-4-1. gitlab 환경에 대한 조회
kubectl exec -it git-xxx  -n infra -- /bin/sh
#   root 유저 >  gitlab-ctl show-config  
#      ....
#      "nginx": {
#        "client_max_body_size": "2048m",   # git push body size
#        "proxy_set_headers": {
#          "Host": "$http_host_with_default",
#          "X-Real-IP": "$remote_addr",
#          "X-Forwarded-For": "$proxy_add_x_forwarded_for",
#          "Upgrade": "$http_upgrade",
#          "Connection": "$connection_upgrade",
#          "X-Forwarded-Proto": "http"
#        },
#     ....
# 8-4-2. git upload size 부족 오류가 발생하면 nginx 정보 수정 후 reboot한다.
#  gitlab-ctl restart ( https://docs.gitlab.com/13.0/omnibus/settings/configuration.html )
#  gitlab-configmap.yaml의 nginx['client_max_body_size'] = '2048m' 값 변경
#  => deploy.gitlab-ce.yaml의 volumeMounts중  gitlab.rb는 ConfigMap을 Mount하도록 subpath 잡혀있음
#  configMap을 mount한 경우는 이미 실행되어 있는 pod에는 반영이 안되고 신규 Pod만 반영된다.
#  Application에서 ConfigMap을 자동 reload하는 것이 아니라면, 기존 Pod를 삭제하여 재 부트 한다.
#  kubectl exec gitlab-ce-7b5bcc448b-wjckb -c gitlab-ce -n infra -- gitlab-ctl restart
#  kubectl exec gitlab-ce-7b5bcc448b-wjckb -c gitlab-ce -n infra -- gitlab-ctl show-config
#  잘 반영되었는지? 확인하기 
#  kubectl exec gitlab-ce-7b5bcc448b-wjckb -c gitlab-ce -n infra -- /bin/sh
#    # cat /etc/passwd -> gitlab-www:x:999:999::/var/opt/gitlab/nginx:/bin/false  home directory 확인
#    # cd /var/opt/gitlab/nginx/conf 
#    # vi gitlab-http.conf   -> client_max_body_size 적용된 것 확인하기
#  kubectl exec gitlab-ce-7b5bcc448b-wjckb -c gitlab-ce -n infra -- cat /var/opt/gitlab/nginx/conf/gitlab-http.conf

# 8-5 리소스 정리하기
# kubectl delete -f deploy.gitlab-ce.yaml 
# kubectl delete -f gitlab-pvc-svc-ingress.yaml 
# kubectl delete -f gitlab-configmap.yaml 

###############################################################################
# [ 9. ECR 생성 ]
###############################################################################
1. ECR 생성
2. ECR 프로젝트 생성
   - react-frontend-dualcidr
   - api-backend-dualcidr
3. 각 프로젝트에 Permission 설정
   - ECR > Repositories > react-frontend-dualcidr > Permissions > Edit poicy JSON
   - ECR > Repositories > api-backend-dualcidr  > Permissions > Edit poicy JSON

{
  "Version": "2008-10-17",
  "Statement": [
    {
      "Sid": "AllowPushPull",
      "Effect": "Allow",
      "Principal": "*",
      "Action": [
        "ecr:BatchCheckLayerAvailability",
        "ecr:BatchGetImage",
        "ecr:CompleteLayerUpload",
        "ecr:GetDownloadUrlForLayer",
        "ecr:InitiateLayerUpload",
        "ecr:PutImage",
        "ecr:UploadLayerPart"
      ]
    }
  ]
}

################################################
# [ 10. Jenkins 구성 ] => helm v2.0.1
################################################

# 10-1. helm chart 검색(search) / 다운로드(fetch)
helm search repo stable/jenkins
helm fetch stable/jenkins 

# 10-2. helm chart 설정 파일(values.yaml.edit) 수정
tar -zxvf jenkins-2.5.0.tgz

# Jenkins용 PVC(jenkins-workspace, jenkins-maven-repo) 생성
cat <<EOF > jenkins-pvc.yaml
# NFS FS exports should be "no_root_squash"
---
kind: PersistentVolumeClaim
apiVersion: v1
metadata:
  name: jenkins-workspace
  namespace: infra
  annotations:
    volume.beta.kubernetes.io/storage-class: aws-efs
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 10Gi
---
kind: PersistentVolumeClaim
apiVersion: v1
metadata:
  name: jenkins-maven-repo
  namespace: infra
  annotations:
    volume.beta.kubernetes.io/storage-class: aws-efs
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 5Gi
EOF
kubectl apply -f jenkins-pvc.yaml

cp jenkins/values.yaml values.yaml.jenkins.2.5.0
# Route53 서비스에서 먼저 sub domain을 등록한다. :  Domain의 target은 Public 용 NLB의 ARN 정보
[ec2-user@ip-10-16-0-27 chart-jenkins]$ diff values.yaml.jenkins.2.5.0 jenkins/values.yaml
#  105d104
#  <   adminPassword: "alskfl12~!"
#  154,156c153
#  <   deploymentLabels:
#  <     app.role: cicd
#  <     app.type: deployment
#  ---
#  >   deploymentLabels: {}
#  160,162c157
#  <   serviceLabels:
#  <     app.role: cicd
#  <     app.type: service
#  ---
#  >   serviceLabels: {}
#  165,167c160
#  <   podLabels:
#  <     app.role: cicd
#  <     app.type: pod
#  ---
#  >   podLabels: {}
#  254c247
#  <   master.loverwritePluginsFromImage: true
#  ---
#  >   overwritePluginsFromImage: true
#  388c381
#  <     enabled: true
#  ---
#  >     enabled: false
#  402,403c395,396
#  <     annotations:
#  <       kubernetes.io/ingress.class: nginx
#  ---
#  >     annotations: {}
#  >     # kubernetes.io/ingress.class: nginx
#  406,407c399
#  <     #  path: "/jenkins"
#  <     path: "/"       # path는 hostname과 같은 depth로 유지해야 한다. - ingress rule path정보로 사용됨.
#  ---
#  >     # path: "/jenkins"
#  409c401
#  <     hostName: jenkins.dualcidr.com  # 외부 등록 DNS 정보
#  ---
#  >     hostName:
#  607c599
#  <   existingClaim: "jenkins-workspace"  # manually create -- 앞서서 aws-efs에 만든 pvc 이름과 동일하게 설정
#  ---
#  >   existingClaim:
#  615c607
#  <   storageClass: aws-efs
#  ---
#  >   storageClass:

 
# 10-3. jenkins 설치
helm install jenkins -n infra -f values.yaml.jenkins.2.5.0 stable/jenkins --version v2.5.0

# 설치 후 출력 메시지
#  NAME: jenkins
#  LAST DEPLOYED: Sun Aug 16 08:38:31 2020
#  NAMESPACE: infra
#  STATUS: deployed
#  REVISION: 1
#  NOTES:
#  1. Get your 'admin' user password by running:
#    printf $(kubectl get secret --namespace infra jenkins -o jsonpath="{.data.jenkins-admin-password}" | base64 --decode);echo
#  
#  2. Visit http://jenkins.pub.tbiz-atcl.net
#  
#  3. Login with the password from step 1 and the username: admin
#  
#  4. Use Jenkins Configuration as Code by specifying configScripts in your values.yaml file, see documentation: http://jenkins.pub.tbiz-atcl.net/configuration-as-code and examples: https://github.com/jenkinsci/configuration-as-code-plugin/tree/master/demos
#  
#  For more information on running Jenkins on Kubernetes, visit:
#  https://cloud.google.com/solutions/jenkins-on-container-engine
#  For more information about Jenkins Configuration as Code, visit:
#  https://jenkins.io/projects/jcasc/

# 10-4. jenkins 시스템에 접속하여 점검 및 password 설정 하기
http://jenkins.dualcidr.com/ ( admin / alskfl12~! )
# 503 temporary 에러가 나는 경우는 
#  오류 1. PVC 이름 오류로 매핑이 안되었거나, PVC가 안 만들어진 경우 : 1-1) helm uninstall 후 values config 수정 후 재 설치 1-2) PVC 생성
#  오류 2. kubectl get pod -n infra 로 조회했을 때 jenkins-xxxx 가  1/2 로 전체 pod가 올라오지 않은 경우 : 시간을 가지고 대기

################################################
# [ 11. EKS에 sa/jenkins 에 cluster-admin 권한 부여 ]
################################################
cat <<EOF > ClusterRoleBinding.yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: jenkins-jnlp-clusterrolebinding
roleRef:
  kind: ClusterRole
  name: cluster-admin
  apiGroup: rbac.authorization.k8s.io
subjects:
- kind: ServiceAccount
  name: jenkins
  namespace: infra
EOF
kubectl apply -f ClusterRoleBinding.yaml

################################################
# [ 12. EKS에 구성한 Gitlab에 샘플 Application을 가져와서 push 등록하기 ]
################################################
# 12-1. GitLab 시스템에 접속하여 한 후 프로젝트 생성하기
https://gitlab.dualcidr.com/ ( root / alskfl12~! )

- Web Console에서 프로젝트 생성하기 
# 12-1-1. 신규 프로젝트 생성 : 프로젝트 명 - react-frontend , public
# 12-1-2. 서버에 소스 저장소 설정하기 
mkdir myrepository; cd myrepository; 
git init
# global 정보 setup
git config --global user.name "kimsangkyeong"
git config --global user.email "kimsangkyeong@gmail.com"
# 12-1-3. gitlab에 생성한 WebAPP용 프로젝트를 Local에 복사하기
git clone https://gitlab.dualcidr.com/root/react-frontend.git

# 12-1-4. GitHub에 미리 만들어 놓은 프로그램을 임시 저장소에 복사하기
mkdir sample; cd sample
git clone https://github.com/kimsangkyeong/react-frontend.git

# 12-1-5. gitlab에 local 저장소에 GitHub 파일들을 복사하기
cd ../react-frontend;
cp -Rp ../sample/react-frontend/* .
cp -Rp ../sample/react-frontend/.gitignore .
cp -Rp ../sample/react-frontend/.dockerignore .

# 12-1-6. Jenkins Pipeline의 git 저장소 정보를 수정하기
vi CICD/Jenkinsfile

#   def git_url        = "https://gitlab.dualcidr.com/root/react-frontend.git"   // 자신의 gitlab
#   def git_credential = "mygituser"                                             // jenkins Webconsole에서 등록한 credeintial ID
#   def ecr_url        = "847322629192.dkr.ecr.ap-northeast-2.amazonaws.com"
#   def ecr_repo       = "react-frontend-dualcidr"
#   def namespace      = "fruits"
#   def app            = "react-frontend"
#   def app_ver        = "1.0"
#   def ecr_credential = "not_yet"
#   
#   def image_tag      = "${ecr_url}/${ecr_repo}:${app_ver}"
#   def label          = "jenkins-slave-jnlp-${UUID.randomUUID().toString()}"
#   
#   podTemplate(label: label, cloud: 'kubernetes', serviceAccount: 'jenkins',
#           containers: [
#                  containerTemplate(name: 'jnlp', image: 'jenkins/jnlp-slave:3.27-1', args: '${computer.jnlpmac} ${computer.name}',
#                      envVars: [
#                              envVar(key: 'JVM_HEAP_MIN', value: '-Xmx192m'),
#                              envVar(key: 'JVM_HEAP_MAX', value: '-Xmx192m')
#                      ]
#                  ),
#                  containerTemplate(name: 'node', image: 'node:12.18.3-alpine',             ttyEnabled: true, command: 'cat'),
#                  containerTemplate(name: 'awscli', image: 'amazon/aws-cli:2.0.22',             ttyEnabled: true, command: 'cat'),
#                  containerTemplate(name: 'docker', image: 'docker:19.03',                      ttyEnabled: true, command: 'cat',
#                                    resourceLimitMemory: '128Mi'),
#                  containerTemplate(name: 'kubectl',image: 'lachlanevenson/k8s-kubectl:latest', ttyEnabled: true, command: 'cat',
#                                    resourceLimitMemory: '128Mi')
#           ],
#           volumes:[
#                   hostPathVolume(mountPath: '/var/run/docker.sock', hostPath: '/var/run/docker.sock'),
#                   hostPathVolume(mountPath: '/etc/hosts',           hostPath: '/etc/hosts'),
#                   persistentVolumeClaim(mountPath: '/home/jenkins/agent/workspace', claimName:'jenkins-workspace'),
#                   persistentVolumeClaim(mountPath: '/root/.m2',                     claimName:'jenkins-maven-repo')
#           ]
#   )
#   {
#           node(label) {
#                   stage('CheckOut Source') {
#                       git branch: "master", url: "${git_url}", credentialsId: "${git_credential}"
#                   }
#   
#                   environment {
#                       CI = 'true'
#                   }
#   
#                   stage('build the source code via npm') {
#                       container('node') {
#                           sh 'npm install'
#                           sh 'npm install react-scripts@3.4.3 -g'
#                           sh 'npm run-script build'
#                       }
#                   }
#   
#                   stage('ECR Login') {
#                       container('awscli') {
#                           sh "aws ecr get-login-password --region ap-northeast-2"
#                           ecr_credential = sh(script: "aws ecr get-login-password --region ap-northeast-2", returnStdout:true)
#                       }
#                   }
#   
#                   stage('Build Docker Image') {
#                       container('docker') {
#                           sh "docker build -t ${image_tag} -f ./CICD/Dockerfile ."
#                           sh "docker login -u AWS -p '${ecr_credential}' ${ecr_url}"
#                           sh "docker push ${image_tag}"
#                       }
#                   }
#   
#                   stage('k8s deploy image = ${image_tag}') {
#                       container('kubectl') {
#                           try {
#                               sh "kubectl delete -f CICD/Deployment.yaml"
#                           } catch (e) {
#                               println "kuectl delete error .."
#                           }
#                           sh "kubectl apply -f CICD/Deployment.yaml"
#                           //sh "kubectl get pod,svc,ingress,deployment -n ${namespace} -l app=${app}"
#                           sh "kubectl get pod,svc,ingress,deployment -n ${namespace} --show-labels"
#                       }
#                   }
#           }
#   }


# 12-1-7. 현재 remote origin 이 어디로 설정되어 있는지? 확인
git remote -v
# 이때 origin  https://gitlab.dualcidr.com/root/react-frontend.git  이렇게 설정이 되어 있으면 맞게 된 상태

# 12-1-8. gitlab에 WebApp 프로그램 소스를 upload 한다.
git add *
git add .gitignore
git add .dockerignore
git status
git commit -sm "WebApp frontend application first upload"
git push  ( # gitlab 사용자 정보 : root / alskfl12~! ) 

# 12-2-1. 신규 프로젝트 생성 : 프로젝트 명 - api-backend , public
# 12-2-2. gitlab에 생성한 WebAPP용 프로젝트를 Local에 복사하기
cd ..;
git clone https://gitlab.dualcidr.com/root/api-backend.git 

# 12-2-3. GitHub에 미리 만들어 놓은 프로그램을 임시 저장소에 복사하기
cd sample
git clone https://github.com/kimsangkyeong/Restapi-ksk-employees.git

# 12-2-4. gitlab에 local 저장소에 GitHub 파일들을 복사하기
cd ../api-backend;
cp -Rp ../sample/Restapi-ksk-employees/* .
cp -Rp ../sample/Restapi-ksk-employees/.gitignore .

# 12-2-5. Jenkins Pipeline의 git 저장소 정보를 수정하기
vi CICD/Jenkinsfile

#   def git_url        = "https://gitlab.dualcidr.com/root/api-backend.git"      // 자신의 gitlab
#   def git_credential = "mygituser"                                             // jenkins Webconsole에서 등록한 credeintial ID
#   def ecr_url        = "847322629192.dkr.ecr.ap-northeast-2.amazonaws.com"
#   def ecr_repo       = "api-backend-dualcidr"
#   def namespace      = "fruits"
#   def app            = "restapi-ksk-employees"
#   def app_ver        = "1.2"
#   def ecr_credential = "not_yet"
#   
#   def image_tag      = "${ecr_url}/${ecr_repo}:${app_ver}"
#   def label          = "jenkins-slave-jnlp-${UUID.randomUUID().toString()}"
#   
#   podTemplate(label: label, cloud: 'kubernetes', serviceAccount: 'jenkins',
#           containers: [
#                  containerTemplate(name: 'jnlp', image: 'jenkins/jnlp-slave:3.27-1', args: '${computer.jnlpmac} ${computer.name}',
#                      envVars: [
#                              envVar(key: 'JVM_HEAP_MIN', value: '-Xmx192m'),
#                              envVar(key: 'JVM_HEAP_MAX', value: '-Xmx192m')
#                      ]
#                  ),
#                  containerTemplate(name: 'maven', image: 'maven:3.6.3-openjdk-14-slim',        ttyEnabled: true, command: 'cat'),
#                  containerTemplate(name: 'awscli', image: 'amazon/aws-cli:2.0.22',             ttyEnabled: true, command: 'cat'),
#                  containerTemplate(name: 'docker', image: 'docker:18.06',                      ttyEnabled: true, command: 'cat',
#                                    resourceLimitMemory: '128Mi'),
#                  containerTemplate(name: 'kubectl',image: 'lachlanevenson/k8s-kubectl:latest', ttyEnabled: true, command: 'cat',
#                                    resourceLimitMemory: '128Mi')
#           ],
#           volumes:[
#                   hostPathVolume(mountPath: '/var/run/docker.sock', hostPath: '/var/run/docker.sock'),
#                   hostPathVolume(mountPath: '/etc/hosts',           hostPath: '/etc/hosts'),
#                   persistentVolumeClaim(mountPath: '/home/jenkins/agent/workspace', claimName:'jenkins-workspace'),
#                   persistentVolumeClaim(mountPath: '/root/.m2',                     claimName:'jenkins-maven-repo')
#           ]
#   )
#   {
#           node(label) {
#                   stage('CheckOut Source') {
#                       git branch: "master", url: "${git_url}", credentialsId: "${git_credential}"
#                   }
#   
#                   stage('build the source code via maven') {
#                       container('maven') {
#                           sh 'mvn clean package -DskipTests'
#                       }
#                   }
#   
#                   stage('ECR Login') {
#                       container('awscli') {
#                           sh "aws ecr get-login-password --region ap-northeast-2"
#                           ecr_credential = sh(script: "aws ecr get-login-password --region ap-northeast-2", returnStdout:true)
#                       }
#                   }
#   
#                   stage('Build Docker Image') {
#                       container('docker') {
#                           sh "docker build -t ${image_tag} -f ./CICD/Dockerfile ."
#                           sh "docker login -u AWS -p '${ecr_credential}' ${ecr_url}"
#                           sh "docker push ${image_tag}"
#                       }
#                   }
#   
#                   stage('k8s deploy image = ${image_tag}') {
#                       container('kubectl') {
#                           try {
#                               sh "kubectl delete -f CICD/Deployment.yaml"
#                           } catch (e) {
#                               println "."
#                           }
#                           sh "kubectl apply -f CICD/Deployment.yaml"
#                           //sh "kubectl get pod,svc,ingress,deployment -n ${namespace} -l app=${app}"
#                           sh "kubectl get pod,svc,ingress,deployment -n ${namespace} --show-labels"
#                       }
#                   }
#           }
#   }


# 12-2-5. 현재 remote origin 이 어디로 설정되어 있는지? 확인
git remote -v
# 이때 origin  https://gitlab.dualcidr.com/root/api-backend.git   이렇게 설정이 되어 있으면 맞게 된 상태

# 12-2-6. gitlab에 Rest API backend 프로그램 소스를 upload 한다.
git add -f *
git add .gitignore
git status
git commit -sm "Rest API backend application first upload"
git push  ( # gitlab 사용자 정보 : root / alskfl12~! ) 

## git push 중 오류 메시지 처리
#  error: RPC failed; HTTP 413 curl 22 The requested URL returned error: 413 Request Entity Too Large
#  gitlab-configmap.yaml의     nginx['client_max_body_size'] = '2048m' 정보 확인한다.
#  https://gitlab.com/help/user/admin_area/settings/continuous_integration#maximum-artifacts-size 
#   Console > Admin Area > Settings > General > Account and limit > Maximum push size(MB) > 10

################################################
# [ 13. Jenkins Pipeline 구성 ]
################################################
# 13-1.  Jenkins 시스템에 접속한다. 
https://jenkins.dualcidr.com/ ( admin / alskfl12~! )

# 13-2. react-frontend 신규 Build Pipeline을 생성한다. (( Credential ID는 Jenkinsfile에서 사용하고 있기 때문에 mygituser로 반드시 저장해야 함.))
1. 신규 item(Pipeline)을 생성 
   - Name : react-frontend
   - TYPE : Pipeline
           Pipeline > Definition > pipeline script from SCM
           - SCM : git
                  > Repository URL : https://gitlab.dualcidr.com/root/react-frontend.git 
                  > Credential     : Add > jenkins 누르고 ( Username : gitlab ID, Password : gitlab PWD, ID : mygituser ) 저장후 > 선택
                  > Script Path    : CICD/Jenkinsfile
2. Build 실행하기

# 13-3. Restapi-ksk-employees 신규 Build Pipeline을 생성한다.
1. 신규 item(Pipeline)을 생성 
   - Name : Restapi-ksk-employees
   - TYPE : Pipeline
           Pipeline > Definition > pipeline script from SCM
           - SCM : git
                  > Repository URL : https://gitlab.dualcidr.com/root/api-backend.git 
                  > Credential     : mygituser 선택
                  > Script Path    : CICD/Jenkinsfile
2. Build 실행하기

###############################################################################
# 14. 배포한 App 서비스 호출
###############################################################################
# 14-1. Web 화면 호출 ( WEB에서 RestAPI 호출한걸 JSP 통해서 WEB 화면으로 View )
# Route53 서비스에서 먼저 sub domain을 등록한다. :  Domain의 target은 Public 용 NLB의 ARN 정보
# 등록할 sub domain 정보 : webapp.dualcidr.com, api.dualcidr.com
https://webapp.dualcidr.com 
( React Web에서 restapi를 호출하는 직원관리 어플리케이션 구동됨 : 데이타가 안나오는 경우는 RDS가 down되었는지? 확인 )

#######################################################################################
# 15. Kubernetes Web UI / Prometheus / Grafana 구성
#######################################################################################
# 15-1. Kubernetes Dashboard (Web UI) : https://docs.aws.amazon.com/ko_kr/eks/latest/userguide/dashboard-tutorial.html
#                                       https://kubernetes.io/ko/docs/tasks/access-application-cluster/web-ui-dashboard/ 
#                                       https://github.com/freepsw/kubernetes_exercise 
# 15-1-1. Metric Server 설치하기 : https://docs.aws.amazon.com/ko_kr/eks/latest/userguide/metrics-server.html
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/download/v0.3.6/components.yaml
# 15-1-2. 정상 배포되었는지? 확인하기
kubectl get deployment metrics-server -n kube-system
# 15-1-3. Dashboard 배포하기
kubectl apply -f https://raw.githubusercontent.com/kubernetes/dashboard/v2.0.0-beta8/aio/deploy/recommended.yaml
# 15-1-4. eks-admin service account 생성 및 cluster role binding
cat <<EOF > eks-admin-service-account.yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: eks-admin
  namespace: kube-system
---
apiVersion: rbac.authorization.k8s.io/v1beta1
kind: ClusterRoleBinding
metadata:
  name: eks-admin
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: cluster-admin
subjects:
- kind: ServiceAccount
  name: eks-admin
  namespace: kube-system
EOF
kubectl apply -f eks-admin-service-account.yaml

# 15-1-5. eks-admin service account의 보안 토큰 값을 얻는다. <authentication_token> 
kubectl -n kube-system describe secret $(kubectl -n kube-system get secret | grep eks-admin | awk '{print $1}')

#####################
# Windows Local PC에 kubectl, aws cli 환경 구성한 후 실행
#####################
# 15-1-6-1. kubernetes proxy 실행 ( Local PC에서 수행한다. )
kubectl proxy

# 15-1-6-2. Proxy에 Web 콘솔로 접속한다. ( Local PC에서 수행한다. )
http://localhost:8001/api/v1/namespaces/kubernetes-dashboard/services/https:kubernetes-dashboard:/proxy/#!/login
로그인 화면에서 15-1-5에서 얻은 token을 복사하여 넣는다.

################################################
# 15-2. prometheus 설치 : https://www.eksworkshop.com/intermediate/240_monitoring/
#                         https://github.com/prometheus/prometheus 
################################################
# 15-2-1. namespace 생성
kubectl create namespace prometheus

# 15-2-2. prometheus 설치 ( w/helm )
helm install prometheus stable/prometheus \
    --namespace prometheus \
    --set alertmanager.persistentVolume.storageClass="gp2",server.persistentVolume.storageClass="gp2"
#  Hemlm Install 후 Display 정보
#  NAME: prometheus
#  LAST DEPLOYED: Thu Aug 20 01:27:50 2020
#  NAMESPACE: prometheus
#  STATUS: deployed
#  REVISION: 1
#  TEST SUITE: None
#  NOTES:
#  The Prometheus server can be accessed via port 80 on the following DNS name from within your cluster:
#  prometheus-server.prometheus.svc.cluster.local
#  
#  
#  Get the Prometheus server URL by running these commands in the same shell:
#    export POD_NAME=$(kubectl get pods --namespace prometheus -l "app=prometheus,component=server" -o jsonpath="{.items[0].metadata.name}")
#    kubectl --namespace prometheus port-forward $POD_NAME 9090
#  
#  
#  The Prometheus alertmanager can be accessed via port 80 on the following DNS name from within your cluster:
#  prometheus-alertmanager.prometheus.svc.cluster.local
#  
#  
#  Get the Alertmanager URL by running these commands in the same shell:
#    export POD_NAME=$(kubectl get pods --namespace prometheus -l "app=prometheus,component=alertmanager" -o jsonpath="{.items[0].metadata.name}")
#    kubectl --namespace prometheus port-forward $POD_NAME 9093
#  #################################################################################
#  ######   WARNING: Pod Security Policy has been moved to a global property.  #####
#  ######            use .Values.podSecurityPolicy.enabled with pod-based      #####
#  ######            annotations                                               #####
#  ######            (e.g. .Values.nodeExporter.podSecurityPolicy.annotations) #####
#  #################################################################################
#  
#  
#  The Prometheus PushGateway can be accessed via port 9091 on the following DNS name from within your cluster:
#  prometheus-pushgateway.prometheus.svc.cluster.local
#  
#  
#  Get the PushGateway URL by running these commands in the same shell:
#    export POD_NAME=$(kubectl get pods --namespace prometheus -l "app=prometheus,component=pushgateway" -o jsonpath="{.items[0].metadata.name}")
#    kubectl --namespace prometheus port-forward $POD_NAME 9091
#  
#  For more information on running Prometheus, visit:
#  https://prometheus.io/

# 15-2-3. prometheus 접속용 ingress 생성
# Route53 서비스에서 먼저 sub domain을 등록한다. :  Domain의 target은 Public 용 NLB의 ARN 정보
kubectl get all -n prometheus

cat <<EOF > ingress-prometheus.yaml
apiVersion: extensions/v1beta1
kind: Ingress
metadata:
  name: prometheus
  namespace: prometheus
  annotations:
    kubernetes.io/ingress.class: nginx
    #nginx.ingress.kubernetes.io/ssl-redirect: "false"
    #nginx.ingress.kubernetes.io/force-ssl-redirect: "false"
    #nginx.ingress.kubernetes.io/rewrite-target: /
spec:
  rules:
  - host: prometheus.dualcidr.com       # ingress-nginx-controller DNS
    http:
      paths:
        - path: /
          backend:
            serviceName: prometheus-server   # Hemlm으로 배포한 prometheus service name
            servicePort: 80
EOF
kubectl apply -f ingress-prometheus.yaml

# 15-2-4. prometheus 서버에 접속하기
https://prometheus.dualcidr.com/ 

################################################
# 15-3. grafana 설치 : https://www.eksworkshop.com/intermediate/240_monitoring/
################################################
# 15-3-1. namespace 생성
kubectl create namespace grafana

# 15-3-2. grafana에서 참조하여 가져올 datasource 정보를 생성한다.
cat <<EOF > grafana.yaml
datasources:
  datasources.yaml:
    apiVersion: 1
    datasources:
    - name: Prometheus
      type: prometheus
      url: http://prometheus-server.prometheus.svc.cluster.local  # prometheus 생성하고 동일 cluster에 생성시 접근할 DNS 정보
      access: proxy
      isDefault: true
EOF

# 15-3-3. Install grafana, values parameter 정보 assign ( datasource 정보 )
helm install grafana stable/grafana \
    --namespace grafana \
    --set persistence.storageClassName="gp2" \
    --set persistence.enabled=true \
    --set adminPassword='alskfl12~!' \
    --values grafana.yaml 
#  Helm 설치 후 Display
#  NAME: grafana
#  LAST DEPLOYED: Thu Aug 20 01:44:22 2020
#  NAMESPACE: grafana
#  STATUS: deployed
#  REVISION: 1
#  NOTES:
#  1. Get your 'admin' user password by running:
#  
#     kubectl get secret --namespace grafana grafana -o jsonpath="{.data.admin-password}" | base64 --decode ; echo
#  
#  2. The Grafana server can be accessed via port 80 on the following DNS name from within your cluster:
#  
#     grafana.grafana.svc.cluster.local
#  
#     Get the Grafana URL to visit by running these commands in the same shell:
#  
#       export POD_NAME=$(kubectl get pods --namespace grafana -l "app.kubernetes.io/name=grafana,app.kubernetes.io/instance=grafana" -o jsonpath="{.items[0].metadata.name}")
#       kubectl --namespace grafana port-forward $POD_NAME 3000
#  
#  3. Login with the password from step 1 and the username: admin

# 15-3-4. grafana 접속용 ingress 생성
# Route53 서비스에서 먼저 sub domain을 등록한다. :  Domain의 target은 Public 용 NLB의 ARN 정보
kubectl get all -n grafana

cat <<EOF > ingress-grafana.yaml
apiVersion: extensions/v1beta1
kind: Ingress
metadata:
  name: grafana
  namespace: grafana
  annotations:
    kubernetes.io/ingress.class: nginx
    #nginx.ingress.kubernetes.io/ssl-redirect: "false"
    #nginx.ingress.kubernetes.io/force-ssl-redirect: "false"
    #nginx.ingress.kubernetes.io/rewrite-target: /
spec:
  rules:
  - host: grafana.dualcidr.com
    http:
      paths:
        - path: /
          backend:
            serviceName: grafana     # Hemlm으로 배포한 grafana service name
            servicePort: 80
EOF
kubectl apply -f ingress-grafana.yaml

# 15-3-5. grafana 서버에 접속하기
https://grafana.dualcidr.com/  => admin / alskfl12~!
# 15-3-5-1. passwd 찾기  
# kubectl get secret --namespace grafana grafana -o jsonpath="{.data.admin-password}" | base64 --decode ; echo

# 15-3-6. grafana 대쉬보드 설정하기 : https://www.eksworkshop.com/intermediate/240_monitoring/dashboards/ 
# 15-3-6-1. Cluster Monitoring Dashboard
  Step 1. Click ’+’ button on left panel and select ‘Import’.
  Step 2. Enter 3119 dashboard id under Grafana.com Dashboard.
  Step 3. Click ‘Load’.
  Step 4. Select ‘Prometheus’ as the endpoint under prometheus data sources drop down.
  Step 5. Click ‘Import’.
# 15-3-6-2. Pods Monitoring Dashboard
  Step 1. Click ’+’ button on left panel and select ‘Import’.
  Step 2. Enter 6417 dashboard id under Grafana.com Dashboard.
  Step 3. Click ‘Load’.
  Step 4. Enter Kubernetes Pods Monitoring as the Dashboard name.
  Step 5. Click change to set the Unique identifier (uid).
  Step 6. Select ‘Prometheus’ as the endpoint under prometheus data sources drop down.s
  Step 7. Click ‘Import’.


# 15-4. 리소스 종료하기
#  helm uninstall prometheus --namespace prometheus
#  helm uninstall grafana --namespace grafana

#######################################################################################
# 16. Logging 구성 ( AWS Elasticsearch Service 사용 ) : https://www.eksworkshop.com/intermediate/230_logging/
#######################################################################################
# 16-1. AWS Elasticsearch 서비스 생성하기
# 16-1-1. ES Domain 이름 : es-dualcidr
# 16-1-2. Public Access : 기본
#         VPC Assign : EKS Cluster VPC의 pod network에 생성,  sg는 cluster의 worker group용으로 eks-cluster-sg-dualcidr-cluster-xxxx
# 16-1-3. Create master user : admin , passwd : Alskfl12~!
# 16-1-4. Access Policy : Allow open access to the domain 셋팅 . 생성 후 접속 제어
# 오류 해결 Tip : ES가 생성된 후 Cluster health 등의 정보 탭을 선택시 발생하는 오류 대응
#   오류 메시지 : /_cluster/health: {"error":{"root_cause":[{"type":"security_exception",
#               "reason":"no permissions for [cluster:monitor/health] and User [name=arn:aws:iam::847322629192:user/ksk, backend_roles=[], requestedTenant=null]"}],
#               "type":"security_exception","reason":"no permissions for [cluster:monitor/health] and User [name=arn:aws:iam::847322629192:user/ksk, backend_roles=[], requestedTenant=null]"},"status":403}
#   오류 원인   : AWS Console Login IAM User의 ES의 모니터링 조회 권한이 없어서 발생하는 문제
#   해결 방안   : ES에 연결된 kibana Web consol을 이용하여 Role binding을 한다.
#                kibana > Security > Role Mappings > all_access : edit icon click
#                   => Add User Click 후 IAM User ARN 추가 : arn:aws:iam::xxxxx:user/selfusername

# 16-2. Enabling IAM roles for service accounts on your cluster
export AWS_REGION=ap-northeast-2
export ACCOUNT_ID=`aws sts get-caller-identity | jq -r .Account`
export CLUSTER_NAME=dualcidr-cluster
export ES_DOMAIN_NAME="es-dualcidr"
export ES_VERSION="7.7"
export ES_DOMAIN_USER="admin"
export ES_DOMAIN_PASSWORD='Alskfl12~!'
export IAM_FLUENT_BIT_POLICY="dualcidr-fluent-bit-policy"

# 16-3.  Cluster And AWS Role/ Policy 설정하기
# 16-3-1. Enabling IAM roles for service accounts on your cluster
eksctl utils associate-iam-oidc-provider \
    --cluster ${CLUSTER_NAME} \
    --approve

# 16-3-2. Creating AWS IAM Policy for service account
mkdir ./logging/
cat <<EOF > ./logging/fluent-bit-policy.json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "es:ESHttp*"
            ],
            "Resource": "arn:aws:es:${AWS_REGION}:${ACCOUNT_ID}:domain/${ES_DOMAIN_NAME}"
        }
    ]
}
EOF

aws iam create-policy   \
  --policy-name ${IAM_FLUENT_BIT_POLICY} \
  --policy-document file://./logging/fluent-bit-policy.json

# 16-3-3. Creating IAM Role & Policy for Cluster Service Account
kubectl create namespace logging

eksctl create iamserviceaccount \
    --name fluent-bit \
    --namespace logging \
    --cluster ${CLUSTER_NAME} \
    --attach-policy-arn "arn:aws:iam::${ACCOUNT_ID}:policy/${IAM_FLUENT_BIT_POLICY}" \
    --approve \
    --override-existing-serviceaccounts

# 16-3-4. EKS 클러스터에 fluent bit 에 대한 ServiceAccount 생성 확인
kubectl -n logging describe sa fluent-bit

# 16-4. AWS Elasticsearch 서비스 CLI로 신규 domain 생성하기 : https://www.eksworkshop.com/intermediate/230_logging/setup_es/
# 이미 생성했으면 Skip
# 16-4-1. AWS ES Service Domain 생성
curl -sS https://www.eksworkshop.com/intermediate/230_logging/deploy.files/es_domain.json \
  | envsubst > ./logging/es_domain.json

aws es create-elasticsearch-domain \
  --cli-input-json  file://./logging/es_domain.json

# 16-4-2. ES 생성 확인 ( 약 12분 정도 걸림 )
while true
do
  if [ $(aws es describe-elasticsearch-domain --domain-name ${ES_DOMAIN_NAME} --query 'DomainStatus.Processing') == "false" ]
    then
      tput setaf 2; echo "[`date +%H:%M:%S`] The Elasticsearch cluster is ready"   ; tput setaf 9
	  break;
    else
      tput setaf 1; echo "[`date +%H:%M:%S`] The Elasticsearch cluster is NOT ready"; tput setaf 9
  fi
  sleep 10
done

# 16-5. ES의 접속 권한 설정 ( Mapping Roles to Users )
#  We need to retrieve the Fluent Bit Role ARN
export FLUENTBIT_ROLE=$(eksctl get iamserviceaccount --cluster ${CLUSTER_NAME} --namespace logging -o json | jq '.iam.serviceAccounts[].status.roleARN' -r)
#  Get the Elasticsearch Endpoint
export ES_ENDPOINT=$(aws es describe-elasticsearch-domain --domain-name ${ES_DOMAIN_NAME} --output text --query "DomainStatus.Endpoint")
#  Update the Elasticsearch internal database
curl -sS -u "${ES_DOMAIN_USER}:${ES_DOMAIN_PASSWORD}" \
    -X PATCH \
    https://${ES_ENDPOINT}/_opendistro/_security/api/rolesmapping/all_access?pretty \
    -H 'Content-Type: application/json' \
    -d'
[
  {
    "op": "add", "path": "/backend_roles", "value": ["'${FLUENTBIT_ROLE}'"]
  }
]
'
# 16-6. Fluent bit 배포하기 : https://www.eksworkshop.com/intermediate/230_logging/deploy/
#                            https://docs.fluentbit.io/ 
# 16-6-1. 배포하기
#   get the Elasticsearch Endpoint
export ES_ENDPOINT=$(aws es describe-elasticsearch-domain --domain-name ${ES_DOMAIN_NAME} --output text --query "DomainStatus.Endpoint")
curl -Ss https://www.eksworkshop.com/intermediate/230_logging/deploy.files/fluentbit.yaml \
    | envsubst > ./logging/fluentbit.yaml

# 16-6-2. diff fluentbit.yaml fluentbit.yaml.raw
#    <     app: fluent-bit
#    ---
#    >     k8s-app: fluent-bit
#    49d48
#    <     @INCLUDE output-stdout.conf
#    79c78
#    <         Host            search-es-dualcidr-jxxahzqazsiueppb4iipk23pq4.ap-northeast-2.es.amazonaws.com
#    ---
#    >         Host            ${ES_ENDPOINT}
#    83c82
#    <         AWS_Region      ap-northeast-2
#    ---
#    >         AWS_Region      ${AWS_REGION}
#    86,90d84
#    <   output-stdout.conf: |
#    <     [OUTPUT]
#    <         Name            stdout
#    <         Match           *
#    <
#    144c138
#    <     app: fluent-bit-logging
#    ---
#    >     k8s-app: fluent-bit-logging
#    151c145
#    <       app: fluent-bit-logging
#    ---
#    >       k8s-app: fluent-bit-logging
#    155c149
#    <         app: fluent-bit-logging
#    ---
#    >         k8s-app: fluent-bit-logging

# 참고1)   prometheus는 stdout으로 Output을 설정한다.
# ---<< 파일 추가 내용 >>
#      @INCLUDE output-stdout.conf
# 
#    output-stdout.conf: |
#      [OUTPUT]
#          Name            stdout
#          Match           *
# 참고2) ElaticSerch에서 Data Parse 오류 메시지
# ES의 Kibana에서 조회 시 app.kubernetes.io 관련 오류 메시지
#  => Aug 23, 2020 @ 23:44:28.768	@timestamp:Aug 23, 2020 @ 23:44:28.768 log:{"took":6,"errors":true,"items":[{"index":{"_index":"fluent-bit","_type":"_doc","_id":"KqrHG3QBaFYBOZdYH_3Y","status":400,"error":{"type":"mapper_parsing_exception","reason":"Could not dynamically add mapping for field [app.kubernetes.io/component]. Existing mapping for [kubernetes.labels.app] must be of type object but found [text]."}}},{"index":{"_index":"fluent-bit","_type":"_doc","_id":"K6rHG3QBaFYBOZdYH_3Y","status":400,"error":{"type":"mapper_parsing_exception","reason":"Could not dynamically add mapping for field [app.kubernetes.io/component]. Existing mapping for [kubernetes.labels.app] must be of type object but found [text]."}}},{"index":{"_index":"fluent-bit","_type":"_doc","_id":"LKrHG3QBaFYBOZdYH_3Y","status":400,"error":{"type":"mapper_parsing_exception","reason":"Could not dynamically add mapping for field [app.kubernetes.io/component]. Existing mapping for [kubernetes.labels.app] must be of type object but found [text]."}}},{"index":{"_index":"fluent-bit","_type":"_doc","_id":"LarHG3QBaFYBOZdYH_3Y","status":400,"error":{"type":"mapper_parsing_exception","reason":"Could not dynamically add mapping for field [app.kubernetes.io/component]. Existing mapping for [kubernetes.labels.app] must be of type object but found [text]."}}},{"index":{"_index":"fluent-bit","_type":"_doc","_id":"LqrHG3QBaFYBOZdYH_3Y","status":400,"error":{"type":"mapper_parsing_exception","reason":"Could not dynamically add mapping for field [app.kubernetes.io/component]. Existing mapping for [kubernetes.labels.app] must be of type object but found [text]."}}},{"index":{"_index":"fluent-bit","_type":"_doc","_id":"L6rHG3QBaFYBOZdYH_3Y","status":400,"error":{"type":"mapper_parsing_exception","reason":"Could not dynamically add mapping for field [app.kubernetes.io/component]. Existing mapping for [kubernetes.labels.app] must be of type object but found [text]."}}},{"index":{"_index":"fluent-bit","_type":"_doc","_id":"MKrHG3QBaFYBOZdYH_3Y","status":400,"error":{"type":"mapper_parsing_exception","reason":"Could not dynamically add mapping for field [app.kubernetes.io/component]. Existing mapping for [kubernetes.labels.app] must be of type object but found [text]."}}},{"index":{"_index":"fluent-bit","_type":"_doc","_id":"MarHG3QBaFYBOZdYH_3Y","status":400,"error":{"type":"mapper_parsing_exception","reason":"Could not dynamically add mapping for field [app.kubernetes.io/component]. Existing mapping for [kubernetes.labels.app] must be of type object but found [text]."}}},{"index":{"_index":"fluent-bit","_type":"_doc","_id":"MqrHG3QBaFYBOZdYH_3Y","status":400,"error":{"type":"mapper_parsing_exception","reason":"Could not dynamically add mapping for field [app.kubernetes.io/component]. Existing mapping for [kubernetes.labels.app] must be of type object but found [text]."}}},{"index":{"_index":"fluent-bit","_type":"_doc","_id":"M6rHG3QBaFYBOZdYH_3Y","status":400,"error":{"type":"mapper_parsing_exception","reason":"Could not dynamically add mapping for field [app.kubernetes.io/component]. Existing mapping for [kubernetes.labels.app] must be of type object but found [text]."}}},{"index":{"_index":"fluent-bit","_type":"_doc","_id":"NKrHG3QBaFYBOZdYH_3Y","status":400,"error":{"type":"mapper_parsing_exception","reason":"Could not dynamically add mapping for field [app.kubernetes.io/component]. Existing mapping for [kubernetes.labels.app] must be of type object but found [text]."}}},{"index":{"_index":"fluent-bit","_type":"_doc","_id":"NarHG3QBaFYBOZdYH_3Y","status":400,"error":{"type":"mapper_parsing_exception","reason":"Could not dynamically add mapping for field [app.kubernetes.io/component]. Existing mapping for [kubernetes.labels.app] must be of type object but found [text]."}}},{"index":{"_index":"fluent-bit","_type":"_doc","_id":"NqrHG3QBaFYBOZdYH_3Y","status":400,"error":{"type":"mapper_parsing_exception","reason":"Could not dynamically add mapping for field [app.kubern stream:stderr time:Aug 23, 2020 @ 23:44:28.768 kubernetes.pod_name:fluent-bit-9gr48 kubernetes.namespace_name:logging kubernetes.pod_id:58dc1380-e06b-4731-a05f-fea1eeb8e8e9 kubernetes.labels.controller-revision-hash:79cf8d5b8c kubernetes.labels.k8s-app:fluent-bit-logging kubernetes.labels.kubernetes.io/cluster-service:true kubernetes.labels.pod-template-generation:1 kubernetes.labels.version:v1 kubernetes.annotations.kubernetes.io/psp:eks.privileged kubernetes.annotations.prometheus.io/path:/api/v1/metrics/prometheus kubernetes.annotations.prometheus.io/port:2020 kubernetes.annotations.prometheus.io/scrape:true kubernetes.host:ip-100-64-32-95.ap-northeast-2.compute.internal kubernetes.container_name:fluent-bit kubernetes.docker_id:44c9c0edbee58cb37e1caf0bfb6ee64edc9e93934ec8280a5526baee7d5bc34f kubernetes.container_hash:amazon/aws-for-fluent-bit@sha256:eb4b03ac332eb8687a3d143cb238e9fb58ff937609384ec29d20fc2b470a6c21 kubernetes.container_image:amazon/aws-for-fluent-bit:2.5.0 _id:SKrHG3QBaFYBOZdYI_28 _type:_doc _index:fluent-bit _score: -
# 오류 원인 : parsing 시 daemonset 및 서비스의 lable 정보로 사용하는 k8s-app을 해석하지 못함. 
# 해결 방안 : fluentbit.yaml 파일에서  Label key로 사용되는 k8s-app => app으로 수정한 후 재 배포하기

# 16-6-2. 실행 후 daemonset으로 각 노드에 1개씩 잘 뜨는지 확인
kubectl apply -f ./logging/fluentbit.yaml

kubectl -n logging get daemonset,pod -o wide


# 16-6-3. grafana 서버에 접속하기
http://grafana.dualcidr.com/  => admin / alskfl12~!
# 16-6-3-1. passwd 찾기  
# kubectl get secret --namespace grafana grafana -o jsonpath="{.data.admin-password}" | base64 --decode ; echo

# 16-6-3-2. grafana 대쉬보드 설정하기 : https://docs.fluentbit.io/manual/administration/monitoring 
# 16-6-3-3. Fluendt-bit Logging Operator Dashboard
  Step 1. Click ’+’ button on left panel and select ‘Import’.
  Step 2. Enter 7752 dashboard id under Grafana.com Dashboard.
  Step 3. Click ‘Load’.
  Step 4. Select ‘Prometheus’ as the endpoint under prometheus data sources drop down.
  Step 5. Click ‘Import’.


# 17. Kibana 에서 Index Pattern 생성 및 사용 
# 17-1. kibana URL 및 user/passwd 확인 후 접속 (웹브라우저)
echo "Kibana URL: https://${ES_ENDPOINT}/_plugin/kibana/
Kibana user: ${ES_DOMAIN_USER}
Kibana password: ${ES_DOMAIN_PASSWORD}"

# 17-2. Index Pattern 생성 및 검색
1. 메인화면의 Home Main Icon Click 후(필요시) "Connect to your Elasticsearch index" 클릭
2. Index pattern 에 "*fluent-bit*" 입력 후 "Next step" 클릭
3. Time Filter field name 에 "@timestamp" 선택 후 "Create Index Pattern" 클릭


# 17-3. Logging 환경 삭제하기
#  # fluentbit 삭제
#  kubectl delete -f ./logging/fluentbit.yaml
#  
#  # ES 삭제
#  aws es delete-elasticsearch-domain \
#      --domain-name ${ES_DOMAIN_NAME}
#  
#  # iam service account 삭제
#  eksctl delete iamserviceaccount \
#      --name fluent-bit \
#      --namespace logging \
#      --cluster ${CLUSTER_NAME} \
#      --wait
#  
#  # iam policy 삭제
#  aws iam delete-policy   \
#    --policy-arn "arn:aws:iam::${ACCOUNT_ID}:policy/${IAM_FLUENT_BIT_POLICY}"
#  
#  # logging namespace 삭제
#  kubectl delete namespace logging


# 20. ETC - Instance Stop / Start 처리하기 
export CONTROL_EC2_INS_KEYWORD=bastion

# 20-1. EC2 Stop 처리하기
aws ec2 describe-instances | jq -r ".Reservations[].Instances[] | {iid:.InstanceId, value:.Tags[].Value} | select(.value | contains(\"${CONTROL_EC2_INS_KEYWORD}\")) | .iid  " | awk '{ print "aws ec2 stop-instances --instance-ids ", $1 }' | sh

# 20-2. EC2 Start 처리하기
aws ec2 describe-instances | jq -r ".Reservations[].Instances[] | {iid:.InstanceId, value:.Tags[].Value} | select(.value | contains(\"${CONTROL_EC2_INS_KEYWORD}\")) | .iid  " | awk '{ print "aws ec2 start-instances --instance-ids ", $1 }' | sh
