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
- `r5.2xlarge` for applications that need cost effective general purpose compute
- `g4dn.2xlarge` for applications that need GPUs such as game streaming and ML inference at the edge



## **STEP 1. GENERATE THE CLUSTER INSTALLATION CONFIGURATION FILE:**

**a. Create the `install-config.yaml` file.**

  Change to the directory that contains the installation program and run the following command:

  ```bash
  ./openshift-install create install-config --dir=<installation_directory>
   ```

**b. Modify the install-config.yaml file.**

  You can find more information about the available parameters in the "Installation configuration parameters" section.


SAMPLE INSTALL-CONFIG.YAML FILE:

```bash
apiVersion: v1
baseDomain: example.com 
credentialsMode: Mint 
controlPlane:   
  hyperthreading: Enabled 
  name: master
  platform:
    aws:
      zones:
      - us-west-2a
      rootVolume:
        size: 120
      type: r5.2xlarge
  replicas: 1
compute: 
  hyperthreading: Enabled 
  name: worker
  platform:
    aws:
      rootVolume:
        size: 120
      type: r5.2xlarge
      zones:
      - us-west-2a
  replicas: 0
metadata:
  name: test-cluster 
networking:
  clusterNetwork:
  - cidr: 10.128.0.0/14
    hostPrefix: 23
  machineNetwork:
  - cidr: 10.0.0.0/16
  networkType: OpenShiftSDN
  serviceNetwork:
  - 172.30.0.0/16
platform:
  aws:
    region: us-east-1 
    userTags:
      adminContact: jdoe
      costCenter: 7536
    subnets: 
    - subnet-1
    amiID: ami-96c6f8f7 
    serviceEndpoints: 
      - name: ec2
        url: https://vpce-id.ec2.us-east-1.vpce.amazonaws.com
    hostedZone: Z3URY6TWQ91KVV 
fips: false 
sshKey: ssh-ed25519 AAAA... 
pullSecret: '{"auths": ...}' 
```


## **STEP 3. GATHER THE PULL SECRET FROM THE OPENSHIFT CLUSTER MANAGER SITE:**
  https://console.redhat.com/openshift/install/pull-secret

**a. Click on Download pull secret, and save as filename pull-secret.txt in your current folder.**
**a. Click on the Copy to Clipboard icon to the right of the token.**


   ```bash

   ```
