#######################################################################
## Edit these variables as needed

export REGION="us-east-1"
export WL_ZONE="us-east-1-wl1-was-wlz-1"
export NBG="us-east-1-wl1-was-wlz-1"
export SNO_IMAGE_ID="ami-0c72f473496a7b1c2"       #RHEL CoreOS 4.9
export BASTION_IMAGE_ID="ami-0ae9702360611e715"   #RHEL 8.4
export KEY_NAME=pmf-key

#######################################################################
## Create the VPC.

export VPC_ID=$(aws ec2 --region $REGION \
--output text create-vpc --cidr-block 10.0.0.0/16 \
--query 'Vpc.VpcId') && echo '\nVPC_ID='$VPC_ID

#######################################################################
## Create an internet gateway and attach it to the VPC.

export IGW_ID=$(aws ec2 --region $REGION \
--output text create-internet-gateway \
--query 'InternetGateway.InternetGatewayId') && echo '\nIGW_ID='$IGW_ID

aws ec2 --region $REGION  attach-internet-gateway \
 --vpc-id $VPC_ID  --internet-gateway-id $IGW_ID

#######################################################################
## Add the carrier gateway.

export CAGW_ID=$(aws ec2 --region $REGION \
--output text create-carrier-gateway --vpc-id $VPC_ID \
--query 'CarrierGateway.CarrierGatewayId') && echo '\nCAGW_ID='$CAGW_ID

#######################################################################
## Create the Bastion security group along with ingress rules.

export BASTION_SG_ID=$(aws ec2 --region $REGION \
--output text create-security-group --group-name bastion-sg \
--description "Security group for Bastion host" --vpc-id $VPC_ID \
--query 'GroupId') && echo '\nBASTION_SG_ID='$BASTION_SG_ID 

aws ec2 --region $REGION  authorize-security-group-ingress \
--group-id $BASTION_SG_ID  --protocol tcp  --port 22  --cidr 0.0.0.0/0

#######################################################################
## Create the SNO security group along with ingress rules.

export SNO_SG_ID=$(aws ec2 --region $REGION \
--output text create-security-group --group-name sno-sg \
--description "Security group for SNO host" --vpc-id $VPC_ID \
--query 'GroupId') && echo '\nSNO_SG_ID='$SNO_SG_ID

aws ec2 --region $REGION authorize-security-group-ingress \
--group-id $SNO_SG_ID --protocol tcp --port 22 --source-group $BASTION_SG_ID

aws ec2 --region $REGION authorize-security-group-ingress \
--group-id $SNO_SG_ID --protocol tcp --port 6443 --cidr 0.0.0.0/0

aws ec2 --region $REGION authorize-security-group-ingress \
--group-id $SNO_SG_ID --protocol tcp --port 22623 --cidr 0.0.0.0/0

aws ec2 --region $REGION authorize-security-group-ingress \
--group-id $SNO_SG_ID --protocol tcp --port 80 --cidr 0.0.0.0/0

aws ec2 --region $REGION authorize-security-group-ingress \
--group-id $SNO_SG_ID --protocol tcp --port 443 --cidr 0.0.0.0/0

aws ec2 --region $REGION authorize-security-group-ingress \
--group-id $SNO_SG_ID --protocol icmp --port 0 --cidr 0.0.0.0/0

#######################################################################
## Create the subnet for the Wavelength Zone.

export WL_SUBNET_ID=$(aws ec2 --region $REGION \
--output text create-subnet --cidr-block 10.0.0.0/24 \
--availability-zone $WL_ZONE --vpc-id $VPC_ID \
--query 'Subnet.SubnetId') && echo '\nWL_SUBNET_ID='$WL_SUBNET_ID

#######################################################################
## Create the route table for the Wavelength subnet.

export WL_RT_ID=$(aws ec2 --region $REGION \
--output text create-route-table --vpc-id $VPC_ID \
--query 'RouteTable.RouteTableId') && echo '\nWL_RT_ID='$WL_RT_ID

#######################################################################
## Associate the route table with the Wavelength subnet 
## and a route to direct traffic to the carrier gateway
## which in turns routes traffic to the carrier mobile network.

aws ec2 --region $REGION  associate-route-table \
--route-table-id $WL_RT_ID  --subnet-id $WL_SUBNET_ID 

aws ec2 --region $REGION create-route  --route-table-id $WL_RT_ID \
--destination-cidr-block 0.0.0.0/0  --carrier-gateway-id $CAGW_ID

#######################################################################
## Create the bastion subnet.

export BASTION_SUBNET_ID=$(aws ec2 --region $REGION \
--output text create-subnet --cidr-block 10.0.1.0/24 \
--vpc-id $VPC_ID --query 'Subnet.SubnetId') \
&& echo '\nBASTION_SUBNET_ID='$BASTION_SUBNET_ID

#######################################################################
## Deploy the bastion subnet route table 
## and a route to direct traffic to the internet gateway.

export BASTION_RT_ID=$(aws ec2 --region $REGION \
--output text create-route-table --vpc-id $VPC_ID \
--query 'RouteTable.RouteTableId') \
&& echo '\nBASTION_RT_ID='$BASTION_RT_ID 

aws ec2 --region $REGION  create-route \
--route-table-id $BASTION_RT_ID \
--destination-cidr-block 0.0.0.0/0 --gateway-id $IGW_ID 

aws ec2 --region $REGION  associate-route-table \
--subnet-id $BASTION_SUBNET_ID \
--route-table-id $BASTION_RT_ID

#######################################################################
## Modify the bastion’s subnet to assign public IPs by default.

aws ec2 --region $REGION  modify-subnet-attribute \
--subnet-id $BASTION_SUBNET_ID  --map-public-ip-on-launch

#######################################################################
## Create the carrier IP for the SNO server.

export SNO_CIP_ALLOC_ID=$(aws ec2 --region $REGION \
--output text allocate-address --domain vpc \
--network-border-group $NBG --query 'AllocationId') \
&& echo '\nSNO_CIP_ALLOC_ID='$SNO_CIP_ALLOC_ID

#######################################################################
## Create the elastic network interfaces (ENIs).

export SNO_ENI_ID=$(aws ec2 --region $REGION \
--output text create-network-interface --subnet-id $WL_SUBNET_ID \
--groups $SNO_SG_ID --query 'NetworkInterface.NetworkInterfaceId') \
&& echo '\nSNO_ENI_ID='$SNO_ENI_ID


#######################################################################
## Associate the carrier IP with the ENIs.

aws ec2 --region $REGION associate-address  \
--allocation-id $SNO_CIP_ALLOC_ID \
--network-interface-id $SNO_ENI_ID

#######################################################################
## Deploy the SNO instance.

aws ec2 --region $REGION  run-instances  --instance-type g4dn.2xlarge \
--network-interface '[{"DeviceIndex":0,"NetworkInterfaceId":"'$SNO_ENI_ID'"}]' \
--image-id $BASTION_IMAGE_ID --key-name $KEY_NAME \
--block-device-mappings '[{"DeviceName": "/dev/sda1", "Ebs":{"VolumeSize": 120, "VolumeType": "gp2"}}]' \
--tag-specifications 'ResourceType=instance,Tags=[{Key="kubernetes.io/cluster/wavelength-sno",Value=shared}]'

#######################################################################
## Deploy the BASTION instance.

aws ec2 --region $REGION run-instances  --instance-type t3.medium \
--associate-public-ip-address --subnet-id $BASTION_SUBNET_ID \
--image-id $BASTION_IMAGE_ID --security-group-ids $BASTION_SG_ID --key-name $KEY_NAME

#######################################################################
