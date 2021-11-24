#!/bin/bash
#######################################################################
## Edit these variables as needed

export REGION="us-east-1"
export WL_ZONE="us-east-1-wl1-was-wlz-1"
export NBG="us-east-1-wl1-was-wlz-1"
export SNO_IMAGE_ID="ami-0ae9702360611e715"       #RHEL 8.4
export BASTION_IMAGE_ID="ami-0ae9702360611e715"   #RHEL 8.4
export SNO_INSTANCE_TYPE=r5.2xlarge 
export BASTION_INSTANCE_TYPE=t3.medium 
export KEY_NAME=pmf-key

#######################################################################
echo ##################################################################
#### Create the VPC.
echo Create the VPC

export VPC_ID=$(aws ec2 --region $REGION \
--output text create-vpc --cidr-block 10.0.0.0/16 \
--query 'Vpc.VpcId') && echo '\nVPC_ID='$VPC_ID

#######################################################################
echo ##################################################################
#### Create an internet gateway and attach it to the VPC.
echo Create an internet gateway 

export IGW_ID=$(aws ec2 --region $REGION \
--output text create-internet-gateway \
--query 'InternetGateway.InternetGatewayId') && echo '\nIGW_ID='$IGW_ID

echo Attach the internet gateway to the VPC
aws ec2 --region $REGION  attach-internet-gateway \
 --vpc-id $VPC_ID  --internet-gateway-id $IGW_ID

#######################################################################
echo ##################################################################
#### Create the carrier gateway.
echo Create the carrier gateway

export CAGW_ID=$(aws ec2 --region $REGION \
--output text create-carrier-gateway --vpc-id $VPC_ID \
--query 'CarrierGateway.CarrierGatewayId') && echo '\nCAGW_ID='$CAGW_ID

#######################################################################
echo ##################################################################
#### Create the Bastion security group along with ingress rules.
echo Create the Bastion security group

export BASTION_SG_ID=$(aws ec2 --region $REGION \
--output text create-security-group --group-name bastion-sg \
--description "Security group for Bastion host" --vpc-id $VPC_ID \
--query 'GroupId') && echo '\nBASTION_SG_ID='$BASTION_SG_ID 

echo Create the Bastion security group ingress rules
aws ec2 --region $REGION  authorize-security-group-ingress \
--group-id $BASTION_SG_ID  --protocol tcp  --port 22  --cidr 0.0.0.0/0

#######################################################################
echo ##################################################################
#### Create the SNO security group along with ingress rules.
echo Create the SNO security group

export SNO_SG_ID=$(aws ec2 --region $REGION \
--output text create-security-group --group-name sno-sg \
--description "Security group for SNO host" --vpc-id $VPC_ID \
--query 'GroupId') && echo '\nSNO_SG_ID='$SNO_SG_ID

echo Create the SNO security group ingress rules
aws ec2 --region $REGION authorize-security-group-ingress \
--group-id $SNO_SG_ID --protocol tcp --port 22 --source-group $BASTION_SG_ID

#aws ec2 --region $REGION authorize-security-group-ingress \
#--group-id $SNO_SG_ID --protocol tcp --port 6443 --cidr 0.0.0.0/0

#aws ec2 --region $REGION authorize-security-group-ingress \
#--group-id $SNO_SG_ID --protocol tcp --port 22623 --cidr 0.0.0.0/0

aws ec2 --region $REGION authorize-security-group-ingress \
--group-id $SNO_SG_ID --protocol tcp --port 80 --cidr 0.0.0.0/0

aws ec2 --region $REGION authorize-security-group-ingress \
--group-id $SNO_SG_ID --protocol tcp --port 443 --cidr 0.0.0.0/0

aws ec2 --region $REGION authorize-security-group-ingress \
--group-id $SNO_SG_ID --protocol icmp --port 0 --cidr 0.0.0.0/0

#######################################################################
echo ##################################################################
#### Create the Wavelength Zone subnet.
echo Create the Wavelength Zone subnet

export WL_SUBNET_ID=$(aws ec2 --region $REGION \
--output text create-subnet --cidr-block 10.0.0.0/24 \
--availability-zone $WL_ZONE --vpc-id $VPC_ID \
--query 'Subnet.SubnetId') && echo '\nWL_SUBNET_ID='$WL_SUBNET_ID

#######################################################################
echo ##################################################################
#### Create the Wavelength Zone subnet route table.
echo Create the Wavelength Zone subnet route table

export WL_RT_ID=$(aws ec2 --region $REGION \
--output text create-route-table --vpc-id $VPC_ID \
--query 'RouteTable.RouteTableId') && echo '\nWL_RT_ID='$WL_RT_ID

#######################################################################
echo ##################################################################
#### Associate the Wavelength Zone subnet route table 
#### and a route to direct traffic to the carrier gateway
#### which in turns routes traffic to the carrier mobile network.

echo Associate the Wavelength subnet route table
aws ec2 --region $REGION  associate-route-table \
--route-table-id $WL_RT_ID  --subnet-id $WL_SUBNET_ID \
--output text --query 'AssociationId'

echo Create route to direct traffic to the carrier gateway and carrier network 
aws ec2 --region $REGION create-route  --route-table-id $WL_RT_ID \
--destination-cidr-block 0.0.0.0/0  --carrier-gateway-id $CAGW_ID

#######################################################################
echo ##################################################################
#### Create the bastion subnet.
echo Create the bastion subnet

export BASTION_SUBNET_ID=$(aws ec2 --region $REGION \
--output text create-subnet --cidr-block 10.0.1.0/24 \
--vpc-id $VPC_ID --query 'Subnet.SubnetId') \
&& echo '\nBASTION_SUBNET_ID='$BASTION_SUBNET_ID

#######################################################################
echo ##################################################################
#### Create the bastion subnet route table 

echo Create the bastion subnet route table 
export BASTION_RT_ID=$(aws ec2 --region $REGION \
--output text create-route-table --vpc-id $VPC_ID \
--query 'RouteTable.RouteTableId') \
&& echo '\nBASTION_RT_ID='$BASTION_RT_ID 


#######################################################################
echo ##################################################################
#### Associate the bastion subnet route table 
#### and a route to direct traffic to the internet gateway.

echo Associate the bastion subnet route table 
aws ec2 --region $REGION  associate-route-table \
--subnet-id $BASTION_SUBNET_ID --route-table-id $BASTION_RT_ID \
--output text --query 'AssociationId'

echo Create route to direct traffic to the internet gateway 
aws ec2 --region $REGION  create-route \
--route-table-id $BASTION_RT_ID \
--destination-cidr-block 0.0.0.0/0 --gateway-id $IGW_ID 

#######################################################################
echo ##################################################################
#### Modify the bastion subnet to assign public IPs by default.
echo Modify the bastion subnet to assign public IPs by default

aws ec2 --region $REGION  modify-subnet-attribute \
--subnet-id $BASTION_SUBNET_ID  --map-public-ip-on-launch

#######################################################################
echo ##################################################################
#### Create the carrier IP for the SNO server.
echo Create the carrier IP for the SNO server

export SNO_CIP_ALLOC_ID=$(aws ec2 --region $REGION \
--output text allocate-address --domain vpc \
--network-border-group $NBG --query 'AllocationId') \
&& echo '\nSNO_CIP_ALLOC_ID='$SNO_CIP_ALLOC_ID

#######################################################################
echo ##################################################################
#### Create the elastic network interfaces ENIs.
echo Create the elastic network interfaces ENIs

export SNO_ENI_ID=$(aws ec2 --region $REGION \
--output text create-network-interface --subnet-id $WL_SUBNET_ID \
--groups $SNO_SG_ID --query 'NetworkInterface.NetworkInterfaceId') \
&& echo '\nSNO_ENI_ID='$SNO_ENI_ID

#######################################################################
echo ##################################################################
#### Associate the carrier IP with the ENIs.
echo Associate the carrier IP with the ENIs

#aws ec2 --region $REGION associate-address  \
#--allocation-id $SNO_CIP_ALLOC_ID \
#--network-interface-id $SNO_ENI_ID

export SNO_CIP_ASSOC_ID=$(aws ec2 --region $REGION associate-address  \
--allocation-id $SNO_CIP_ALLOC_ID --network-interface-id $SNO_ENI_ID \
--output text --query 'AssociationId') \
&& echo '\nSNO_CIP_ASSOC_ID='$SNO_CIP_ASSOC_ID

#######################################################################
echo ##################################################################
#### Deploy the SNO instance.
echo Deploy the SNO instance 

export SNO_INSTANCE_ID=$(aws ec2 --region $REGION  run-instances  --instance-type $SNO_INSTANCE_TYPE \
--network-interface '[{"DeviceIndex":0,"NetworkInterfaceId":"'$SNO_ENI_ID'"}]' \
--image-id $BASTION_IMAGE_ID --key-name $KEY_NAME --output text --query Instances[*].[InstanceId] \
--block-device-mappings '[{"DeviceName": "/dev/sda1", "Ebs":{"VolumeSize": 120, "VolumeType": "gp2"}}]' \
--tag-specifications 'ResourceType=instance,Tags=[{Key="kubernetes.io/cluster/wavelength-sno",Value=shared}]') \
&& echo '\nSNO_INSTANCE_ID='$SNO_INSTANCE_ID

#######################################################################
echo ##################################################################
#### Deploy the BASTION instance.
echo Deploy the BASTION instance 

export BASTION_INSTANCE_ID=$(aws ec2 --region $REGION run-instances  --instance-type $BASTION_INSTANCE_TYPE \
--associate-public-ip-address --subnet-id $BASTION_SUBNET_ID --output text --query Instances[*].[InstanceId] \
--image-id $BASTION_IMAGE_ID --security-group-ids $BASTION_SG_ID --key-name $KEY_NAME) \
&& echo '\nBASTION_INSTANCE_ID='$BASTION_INSTANCE_ID

#######################################################################
echo ##################################################################
