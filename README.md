# SNO-Wavelength
Installing Single Node OpenShift (SNO) on AWS into a Wavelength Zone using the OpenShift Assisted-Installer.
 
  REQUIREMENTS FOR INSTALLING ON A SINGLE NODE:  https://docs.openshift.com/container-platform/4.9/installing/installing_sno/install-sno-preparing-to-install-sno.html


## **PREREQUISITES:**
Single-Node OpenShift requires the following minimum host resources: 
- CPU: 8 CPU cores
- Memory: 32GB of RAM
- Storage: 120 GB 

r5.2xlarge
- CPU: 8 vCPUs
- Memory: 64GB

g4dn.2xlarge
- GPU: 1 NVIDIA T4 Tensor Core GPU
- CPU: 8 vCPUs
- Memory: 32GB
- Storage: 225GB NVMe SSD

AWS Wavelength supports the following instances types for edge workloads that meet the minimum SNO resource requirements:  
- `r5.2xlarge` for applications that need cost effective general purpose compute.
- `g4dn.2xlarge` for applications that need GPUs, such as game streaming and machine learning (ML) inference at the edge.

You'll also need to install the AWS CLI. https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html

![image](https://user-images.githubusercontent.com/48925593/140574901-4d6f8c39-6ffe-4e6a-87a5-5a9de79b6ab4.png)

If you've cloned or downloaded this repo, you can edit the variables in the provided script:  `deploySNOonAWS.sh`

Then to run the script with the following command:
 ```bash
 . ./deploySNOonAWS.sh
 ```

This script will execute the commands for Step 1 thru Step 5 below.  


## **STEP 1. CREATE THE VPC AND ASSOCIATED RESOURCES:**

**a. In order to get started, you need to first set some environment variables.**

  Run the following commands:

  ```bash
  export REGION="us-east-1"
  export WL_ZONE="us-east-1-wl1-was-wlz-1"          #Boston Wavelength Zone
  export NBG="us-east-1-wl1-was-wlz-1"
  export SNO_IMAGE_ID="ami-0ae9702360611e715"       #RHEL 8.4
  export BASTION_IMAGE_ID="ami-0ae9702360611e715"   #RHEL 8.4
  export SNO_INSTANCE_TYPE=r5.2xlarge 
  export BASTION_INSTANCE_TYPE=t3.medium 
  export KEY_NAME=pmf-key
   ```
Other variables that are created/used:
  ```bash
  $VPC_ID
  $IGW_ID
  $CAGW_ID
  $BASTION_SG_ID
  $SNO_SG_ID
  $WL_SUBNET_ID
  $WL_RT_ID
  $BASTION_SUBNET_ID
  $BASTION_RT_ID
  $SNO_CIP_ALLOC_ID
  $SNO_ENI_ID
  $SNO_CIP_ASSOC_ID
  $BASTION_INSTANCE_ID
  $SNO_INSTANCE_ID
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

**d. Create the carrier gateway.**

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

**b. Create the route table for the Wavelength Zone subnet.**

```bash
export WL_RT_ID=$(aws ec2 --region $REGION \
--output text create-route-table --vpc-id $VPC_ID \
--query 'RouteTable.RouteTableId') && echo '\nWL_RT_ID='$WL_RT_ID
```

**c. Associate the route table with the Wavelength Zone subnet and a route to direct traffic to the carrier gateway which in turns routes traffic to the carrier mobile network.**

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

**e. Create the bastion subnet route table and a route to direct traffic to the internet gateway.**

```bash
export BASTION_RT_ID=$(aws ec2 --region $REGION \
--output text create-route-table --vpc-id $VPC_ID \
--query 'RouteTable.RouteTableId') && echo '\nBASTION_RT_ID='$BASTION_RT_ID 

aws ec2 --region $REGION  associate-route-table --subnet-id $BASTION_SUBNET_ID \
--route-table-id $BASTION_RT_ID

aws ec2 --region $REGION  create-route --route-table-id $BASTION_RT_ID \
--destination-cidr-block 0.0.0.0/0 --gateway-id $IGW_ID
```

**f. Modify the bastion subnet to assign public IPs by default.**

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
export SNO_CIP_ASSOC_ID=$(aws ec2 --region $REGION associate-address  \
--allocation-id $SNO_CIP_ALLOC_ID --network-interface-id $SNO_ENI_ID \
--output text --query 'AssociationId') \
&& echo '\nSNO_CIP_ASSOC_ID='$SNO_CIP_ASSOC_ID
```

## **STEP 5. DEPLOY THE SNO AND BASTION INSTANCEs:**

With the VPC and underlying networking and security deployed, you can now move on to deploying your SNO instance. 
The SNO server is a g4dn.2xlarge instance and the Bootstrap server is a t3.medium instance; both running RHEL 8.4 AMI. 

**a. Deploy the SNO instance.**

```bash
export SNO_INSTANCE_ID=$(aws ec2 --region $REGION  run-instances  --instance-type $SNO_INSTANCE_TYPE \
--network-interface '[{"DeviceIndex":0,"NetworkInterfaceId":"'$SNO_ENI_ID'"}]' \
--image-id $BASTION_IMAGE_ID --key-name $KEY_NAME --output text --query Instances[*].[InstanceId] \
--block-device-mappings '[{"DeviceName": "/dev/sda1", "Ebs":{"VolumeSize": 120, "VolumeType": "gp2"}}]' \
--tag-specifications 'ResourceType=instance,Tags=[{Key="kubernetes.io/cluster/wavelength-sno",Value=shared}]') \
&& echo '\nSNO_INSTANCE_ID='$SNO_INSTANCE_ID
```

Remember that the carrier gateway in a Wavelength Zone only allows ingress from the carrier’s 5G network. 
This means that in order to SSH into the SNO server, you'll need to first SSH into the Bastion host, and then from there, SSH into your Wavelength SNO instance.
The Bastion host is a t3.medium instance; running RHEL 8.4 AMI. 

**b. Deploy the BASTION instance.**

```bash
export BASTION_INSTANCE_ID=$(aws ec2 --region $REGION run-instances  --instance-type $BASTION_INSTANCE_TYPE \
--associate-public-ip-address --subnet-id $BASTION_SUBNET_ID --output text --query Instances[*].[InstanceId] \
--image-id $BASTION_IMAGE_ID --security-group-ids $BASTION_SG_ID --key-name $KEY_NAME) \
&& echo '\nBASTION_INSTANCE_ID='$BASTION_INSTANCE_ID
```

## **STEP 6. GENERATE DISCOVERY ISO FROM THE ASSISTED INSTALLER:**

Open the OpenShift Assisted Installer website: https://console.redhat.com/openshift/assisted-installer/clusters/. 
You will be prompted for your Red Hat ID and password to login.

**a. Select 'Create cluster'.**

 ![image](https://user-images.githubusercontent.com/48925593/140575947-b4f8e666-637c-451f-b797-d30feff712d3.png)


**b. Enter the cluster name, and the base domain; then select 'Install single node OpenShift (SNO)' and 'OpenShift 4.9.4', and click 'Next'.**

 ![image](https://user-images.githubusercontent.com/48925593/143304033-01bd05b8-71ad-4a9d-94e5-e9ee4b38e729.png)



**c. Select 'Generate Discovery ISO'.**

 ![image](https://user-images.githubusercontent.com/48925593/143304631-df063601-d2a5-49d7-af05-db699fd9e01e.png)


**d. Select 'Minimal Image File' and 'Generate Discovery ISO'.**

 ![image](https://user-images.githubusercontent.com/48925593/140576887-3764d5fc-b271-4b7e-806a-f79ecde64be8.png)


**e. Click on the 'Copy to clipboard' icon to the right of the 'Command to download the ISO'.**

This will be used in a later step from the SNO instance.

 ![image](https://user-images.githubusercontent.com/48925593/143304940-fe1e3bbc-31c5-4127-8a09-f6885be762e0.png)



**e. Click 'Close' to return to the previous screen.**


## **STEP 7. BOOT THE SNO INSTANCE FROM THE DISCOVERY ISO:**

AWS EC2 instances are NOT able to directly boot from an ISO image. So, we'll use the following steps to download the Discovery ISO image to the instance.
Then we'll add an entry to the grub configuration to allow it to boot boot from the image. 


**a. SSH into the SNO instance.**

```bash
ssh -i <your-sshkeyfile.pem> ec2user@<ip address>
```


**b. Install wget and download the Discovery Image ISO.**

You'll need the download url provided previously in step 6e.  You'll need to edit the path and filename before you run the command to download the ISO file.  Notice that the file is being downloaded as `discovery-image.iso` into the `/var/tmp/` folder. 

```bash
sudo yum install wget -y

sudo wget -O /var/tmp/discovery-image.iso 'https://<long s3 url provided by AI SaaS>'
```


**c. Edit the grub configuration.**

Edit the 40_custom file.

```bash
sudo vi /etc/grub.d/40_custom
```
Add the following to the end of the file: 
 
```bash
menuentry "Discovery Image RHCOS" {
        set root='(hd0,2)'
        set iso="/var/tmp/discovery-image.iso"
        loopback loop ${iso}
        linux (loop)/images/pxeboot/vmlinuz boot=images iso-scan/filename=${iso} persistent noeject noprompt ignition.firstboot ignition.platform.id=metal coreos.live.rootfs_url='https://mirror.openshift.com/pub/openshift-v4/dependencies/rhcos/4.9/4.9.0/rhcos-live-rootfs.x86_64.img'
        initrd (loop)/images/pxeboot/initrd.img (loop)/images/ignition.img (loop)/images/assisted_installer_custom.img
        }
```


**d. Save the grub configuration, and reboot the SNO instance.**

Execute these commands to generate and save the new menuentry.

```bash
sudo grub2-set-default 'Discovery Image RHCOS'
sudo grub2-mkconfig -o /boot/grub2/grub.cfg
sudo reboot
```


## **STEP 8. RETURN TO THE ASSISTED INSTALLER TO FINISH THE INSTALLATION:**

Return to the OpenShift Assisted Installer.
 
 **a. You should see the SNO instance displayed in the list of discovered servers. 
      From the _Host discovery_ menu, once the SNO instance is discovered, click 'Next'.**
 
  ![image](https://user-images.githubusercontent.com/48925593/143311949-ce94272a-0548-4b4e-9be2-9a76503617c2.png)

 
 **b. From the _Networking_ menu, select the discovered `network subnet`, and click on _Next_ to proceed.**

![image](https://user-images.githubusercontent.com/48925593/143313096-6ed9e605-50ee-43e1-8e05-9fd260c09d93.png)


![image](https://user-images.githubusercontent.com/48925593/143312805-d65410b7-0263-48bb-bbe1-56e885c99276.png)


**c. Review the configuration, and select _Install Cluster_.**

 ![image](https://user-images.githubusercontent.com/48925593/143313250-269de01d-5827-4001-bea4-69dde1982d2f.png)


**d. Monitor the installation progress.**

 ![image](https://user-images.githubusercontent.com/48925593/143313390-7b40a8a7-381c-4b97-908e-b6f4d14d6a68.png)
 
 ![image](https://user-images.githubusercontent.com/48925593/143314810-30cfc435-b66a-4069-a8fa-157e7e84fa1b.png)

 ![image](https://user-images.githubusercontent.com/48925593/143314890-e5389a58-fe0e-47f7-b863-7f317de7a7bf.png)

 ![image](https://user-images.githubusercontent.com/48925593/143315164-77fea973-cfc1-4c1c-8980-2b5852c052ab.png)

 ![image](https://user-images.githubusercontent.com/48925593/143316128-d1a5f578-4234-4acd-8ec1-86f7b52c0c49.png)


**e. Installation Complete.**

Upon completion, you'll see the summary of the installation, and you'll be able to download the kubeconfig file, 
and retreive the kubeadmin password.

 ![image](https://user-images.githubusercontent.com/48925593/143317424-36b69123-21d1-4213-83ac-26cb980f1e4f.png)




 
