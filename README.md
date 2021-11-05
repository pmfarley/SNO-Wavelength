# SNO-Wavelength
Installing Single Node OpenShift (SNO) on AWS into an existing VPC and a Wavelength Zone.

  INSTALLING INTO AN EXISTING VPC ON AWS:  https://docs.openshift.com/container-platform/4.8/installing/installing_aws/installing-aws-vpc.html
  
  REQUIREMENTS FOR INSTALLING ON A SINGLE NODE:  https://docs.openshift.com/container-platform/4.9/installing/installing_sno/install-sno-preparing-to-install-sno.html


## **PREREQUISITES:**
Single-Node OpenShift requires the following minimum host resources: 
- CPU: 8 CPU cores
- Memory: 32GB of RAM
- Storage: 120 GB 

AWS Wavelength supports the following instances types for edge workloads that meet the minimum SNO resource requirements:  
- `r5.2xlarge` for applications that need cost effective general purpose compute.
- `g4dn.2xlarge` for applications that need GPUs, such as game streaming and machine learning (ML) inference at the edge.

You'll also need the AWS CLI installed. https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html


## **STEP 1. CREATE THE VPC AND ASSOCIATED RESOURCES:**

**a. In order to get started, you need to first set some environment variables.**

  Change to the directory that contains the installation program and run the following command:

  ```bash
  export REGION="us-east-1"
  export WL_ZONE="us-east-1-wl1-was-wlz-1"
  export NBG="us-east-1-wl1-was-wlz-1"
  export SNO_IMAGE_ID="ami-0c72f473496a7b1c2"       #RHEL CoreOS 4.9
  export BASTION_IMAGE_ID="ami-0ae9702360611e715"   #RHEL 8.4
  export KEY_NAME=pmf-key
   ```
Other variables created/used:
  ```bash
  $VPC_ID
  $IGW_ID
  $CAGW_ID
  $SNO_SG_ID
  $WL_SUBNET_ID
  $WL_RT_ID
  $BASTION_SUBNET_ID
  $BASTION_RT_ID
  $SNO_ENI_ID
  $SNO_CIP_ALLOC_ID
   ```

**b. Use the AWS CLI to create the VPC.**

```bash
export VPC_ID=$(aws ec2 --region $REGION \
--output text create-vpc --cidr-block 10.0.0.0/16 \
--query 'Vpc.VpcId') && echo '\nVPC_ID='$VPC_ID
```


**c. Create an internet gateway and attach it to the VPC.**

```bash
export IGW_ID=$(aws ec2 --region $REGION \
--output text create-internet-gateway \
--query 'InternetGateway.InternetGatewayId') && echo '\nIGW_ID='$IGW_ID

aws ec2 --region $REGION  attach-internet-gateway \
 --vpc-id $VPC_ID  --internet-gateway-id $IGW_ID
```

**d. Add the carrier gateway.**

```bash
export CAGW_ID=$(aws ec2 --region $REGION \
--output text create-carrier-gateway --vpc-id $VPC_ID \
--query 'CarrierGateway.CarrierGatewayId') && echo '\nCAGW_ID='$CAGW_ID
```


## **STEP 2. DEPLOY THE SECURITY GROUPS:**

In this section, you add two security groups:
- `Bastion SG` allows SSH traffic from your local machine to the bastion host from the Internet
- `SNO SG` allows SSH traffic from the Bastion SG and opens up ports (80, 443, 6443, 22623) and icmp.

**a. Create the Bastion security group along with ingress rules.**

Note: You can adjust the `–-cidr` parameter in the second command to restrict SSH access to only be allowed from your current IP address. 

```bash
export BASTION_SG_ID=$(aws ec2 --region $REGION \
--output text create-security-group --group-name bastion-sg \
--description "Security group for Bastion host" --vpc-id $VPC_ID \
--query 'GroupId') && echo '\nBASTION_SG_ID='$BASTION_SG_ID 

aws ec2 --region $REGION  authorize-security-group-ingress \
--group-id $BASTION_SG_ID  --protocol tcp  --port 22  --cidr 0.0.0.0/0
```
   
**b. Create the SNO security group along with ingress rules.**

This allows SSH from the bastion security group, 
and opening up other ports the SNO host communicates on (80, 443, 6443, 22623) and icmp.

```bash
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
```

## **STEP 3. ADD THE SUBNETS AND ROUTING TABLES:**

In the following steps, you’ll create two subnets along with their associated routing tables and routes.

**a. Create the subnet for the Wavelength Zone.**

```bash
export WL_SUBNET_ID=$(aws ec2 --region $REGION \
--output text create-subnet --cidr-block 10.0.0.0/24 \
--availability-zone $WL_ZONE --vpc-id $VPC_ID \
--query 'Subnet.SubnetId') && echo '\nWL_SUBNET_ID='$WL_SUBNET_ID
```

**b. Create the route table for the Wavelength subnet.**

```bash
export WL_RT_ID=$(aws ec2 --region $REGION \
--output text create-route-table --vpc-id $VPC_ID \
--query 'RouteTable.RouteTableId') && echo '\nWL_RT_ID='$WL_RT_ID
```

**c. Associate the route table with the Wavelength subnet and a route to route traffic to the carrier gateway which in turns routes traffic to the carrier mobile network.**

```bash
aws ec2 --region $REGION  associate-route-table \
--route-table-id $WL_RT_ID  --subnet-id $WL_SUBNET_ID 

aws ec2 --region $REGION create-route  --route-table-id $WL_RT_ID \
--destination-cidr-block 0.0.0.0/0  --carrier-gateway-id $CAGW_ID
```

**d. Create the bastion subnet.**

```bash
export BASTION_SUBNET_ID=$(aws ec2 --region $REGION \
--output text create-subnet --cidr-block 10.0.1.0/24 --vpc-id $VPC_ID \
--query 'Subnet.SubnetId') && echo '\nBASTION_SUBNET_ID='$BASTION_SUBNET_ID
```

**e. Deploy the bastion subnet route table and a route to direct traffic to the internet gateway.**

```bash
export BASTION_RT_ID=$(aws ec2 --region $REGION \
--output text create-route-table --vpc-id $VPC_ID \
--query 'RouteTable.RouteTableId') && echo '\nBASTION_RT_ID='$BASTION_RT_ID 

aws ec2 --region $REGION  create-route --route-table-id $BASTION_RT_ID \
--destination-cidr-block 0.0.0.0/0 --gateway-id $IGW_ID 

aws ec2 --region $REGION  associate-route-table --subnet-id $BASTION_SUBNET_ID \
--route-table-id $BASTION_RT_ID
```

**f. Modify the bastion’s subnet to assign public IPs by default.**

```bash
aws ec2 --region $REGION  modify-subnet-attribute \
--subnet-id $BASTION_SUBNET_ID  --map-public-ip-on-launch
```


## **STEP 4. CREATE THE ELASTIC IPS AND NETWORKING INTERFACES:**

The final step before deploying the actual instances is to create two carrier IPs, IP addresses associated with the carrier network. These IP addresses will be assigned to two Elastic Network Interfaces (ENIs), and the ENIs will be assigned to our SNO and Bootstrap server (the Bastion host will have its public IP assigned upon creation by the bastion subnet).

**a. Create the carrier IP for the SNO server.**

```bash
export SNO_CIP_ALLOC_ID=$(aws ec2 --region $REGION \
--output text allocate-address --domain vpc --network-border-group $NBG \
--query 'AllocationId') && echo '\nSNO_CIP_ALLOC_ID='$SNO_CIP_ALLOC_ID
```

**b. Create the elastic network interfaces (ENIs).**

```bash
export SNO_ENI_ID=$(aws ec2 --region $REGION \
--output text create-network-interface --subnet-id $WL_SUBNET_ID --groups $SNO_SG_ID \
--query 'NetworkInterface.NetworkInterfaceId') && echo '\nSNO_ENI_ID='$SNO_ENI_ID
```

**c. Associate the carrier IP with the ENIs.**

```bash
aws ec2 --region $REGION associate-address  --allocation-id $SNO_CIP_ALLOC_ID \
--network-interface-id $SNO_ENI_ID
```

## **STEP 5. DEPLOY THE SNO INSTANCE:**

With the VPC and underlying networking and security deployed, you can now move on to deploying your SNO instance. 
The SNO server is a g4dn.2xlarge instance and the Bootstrap server is a t3.medium instance; both running RHEL 8.4 AMI. 

**a. Deploy the SNO instance.**

```bash
aws ec2 --region $REGION  run-instances  --instance-type g4dn.2xlarge \
--network-interface '[{"DeviceIndex":0,"NetworkInterfaceId":"'$SNO_ENI_ID'"}]' \
--image-id $BASTION_IMAGE_ID --key-name $KEY_NAME \
--block-device-mappings '[{"DeviceName": "/dev/sda1", "Ebs":{"VolumeSize": 120, "VolumeType": "gp2"}}]' \
--tag-specifications 'ResourceType=instance,Tags=[{Key="kubernetes.io/cluster/wavelength-sno",Value=shared}]'
```


## **STEP 6. DEPLOY THE BASTION INSTANCE:**

Next, you'll deploy the Bastion host to allow you to SSH into your SNO instance. 
Remember that the carrier gateway in a Wavelength Zone only allows ingress from the carrier’s 5G network. 
This means that in order to SSH into the SNO server, you'll need to first SSH into the Bastion host, and then from there, SSH into your Wavelength SNO instance.
The Bastion host is a t3.medium instance; running RHEL 8.4 AMI. 

**a. Deploy the BASTION instance.**

```bash
aws ec2 --region $REGION run-instances  --instance-type t3.medium \
--associate-public-ip-address --subnet-id $BASTION_SUBNET_ID \
--image-id $BASTION_IMAGE_ID --security-group-ids $BASTION_SG_ID --key-name $KEY_NAME
```


