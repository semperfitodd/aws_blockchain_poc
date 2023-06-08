# AWS Managed Blockchain for smart contract POC
## Table of Contents
1. [Introduction](#Introduction)
2. [Prerequisites](#Prerequisites)
3. [Architecture](#Architecture)
4. [Setup](#Setup)
   - [AWS Setup](#AWS-Setup)
   - [Terraform Setup](#Terraform-Setup)
5. [Testing Connectivity](#Testing-Connectivity)
6. [Client Setup](#Client-Setup)
7. [Channel Creation](#Channel-Creation)
8. [Chaincode Packaging](#Chaincode-Packaging)
9. [Chaincode Installation](#Chaincode-Installation)
10. [Invoke and Test Smart Contract](#Invoke-and-Test-Smart-Contract)
11. [Troubleshooting](#Troubleshooting)

## Introduction
This guide provides steps to set up a smart contract proof of concept using AWS Managed Blockchain.

## Prerequisites
* AWS account with access to create resources.
* Basic knowledge of AWS services such as EC2, VPC, and Managed Blockchain.
* Basic understanding of blockchain technology.
* AWS CLI installed and configured.
* Terraform installed.

## Architecture
![architecture.png](images%2Farchitecture.png)
This POC will set up the following AWS resources:
* VPC
* EC2 instance and security group
* Amazon Blockchain Managed network, user, node
* Userdata installs all essential packages

## Setup
### AWS Setup
1. Install AWS CLI and configure it with your access key, secret key, and region.
2. Build an Amazon Managed Blockchain network

   **Note: There is no TerraForm resource to build this at this time. So we will use AWS CLI.**
   ```bash
   cd scripts
   ./create_managed_blockchain.sh 
   ```
### Terraform Setup
1. Install Terraform and initialize it in a new directory.
2. Declare EC2 userdata variables in `ec2.tf` with the information from the following commands to get `NETWORK_ID` and `MEMBER_ID`.

   ```bash
   aws --region us-east-1 managedblockchain list-networks --output text --query 'Networks[*].Id'
   aws --region us-east-1 managedblockchain list-members --network-id <NETWORK_ID> --output text --query 'Members[*].Id'
   ```
   
   ```bash
   #!/bin/bash
   
   AWS_REGION=us-east-1
   MEMBER_ID=
   NETWORK_ID=
   ```
3. Run the Terraform scripts.
   ```bash
   cd terraform
   
   terraform init
   terraform plan -out=plan.out
   terraform apply plan.out
   ```

4. Enable VPC endpoint
![vpc_endpoint.png](images%2Fvpc_endpoint.png)
      * Select all 3 private subnets
      * Select security group created by Terraform

## Testing connectivity
   1. Connect to EC2 instance using SSM
![ssm_connect.jpg](images%2Fssm_connect.jpg)
   ```bash
   # Use ec2-user
   sudo -i #to become root
   su ec2-user
   cd ~
   source .bash_profile
   ```
   2. Check connectivity by making a request to the CA service endpoint.
   ```bash
   curl https://$CASERVICEENDPOINT/cainfo -k
   ```
   You should receive a JSON payload with `CAName`, `CAChain`, `IssuerRevocationPublicKey`, and `Version`.
## Client Setup
1. Set up the client directory and download the required packages.
   ```bash
   mkdir -p /home/ec2-user/go/src/github.com/hyperledger/fabric-ca
   cd /home/ec2-user/go/src/github.com/hyperledger/fabric-ca
   wget https://github.com/hyperledger/fabric-ca/releases/download/v1.4.7/hyperledger-fabric-ca-linux-amd64-1.4.7.tar.gz
   tar -xzf hyperledger-fabric-ca-linux-amd64-1.4.7.tar.gz
   
   echo 'export PATH=$PATH:/home/ec2-user/go/src/github.com/hyperledger/fabric-ca/bin' >> /home/ec2-user/.bash_profile
   
   cd /home/ec2-user
   git clone --branch v2.2.3 https://github.com/hyperledger/fabric-samples.git
   git clone https://github.com/semperfitodd/aws_blockchain_poc.git
   cp -r aws_blockchain_poc/blockchain/*.* .
   cp -r aws_blockchain_poc/blockchain/admin-msp/ .
   ```

2. Setup CLI
   ```bash
   vim /home/ec2-user/docker-compose-cli.yaml
   # make sure to update placeholders MyMemberID and MyPeerNodeEndpoint
   # MyPeerNodeEndpoint is created by combining the following information <NODE_ID>.<MEMBER_ID>.<NETWORK_ID>.managedblockchain.us-east-1.amazonaws.com:30003
   # Network ID
   aws --region us-east-1 managedblockchain list-networks --output text --query 'Networks[*].Id'
   # Member ID
   aws --region us-east-1 managedblockchain list-members --network-id <NETWORK_ID> --output text --query 'Members[*].Id'
   # Node ID
   aws --region us-east-1 managedblockchain get-node --network-id <NETWORK_ID> --member-id <MEMBER_ID> --output text --query 'Nodes[*].Id'
   
   # Run docker compose
   sudo /usr/local/bin/docker-compose -f docker-compose-cli.yaml up -d
   ```
3. Enroll the admin user
   ```bash
   aws s3 cp s3://us-east-1.managedblockchain/etc/managedblockchain-tls-chain.pem  /home/ec2-user/managedblockchain-tls-chain.pem
   
   # Confirm
   openssl x509 -noout -text -in /home/ec2-user/managedblockchain-tls-chain.pem
   
   # Enroll user
   fabric-ca-client enroll \
     -u "https://admin:Password123@$CASERVICEENDPOINT" \
     --tls.certfiles /home/ec2-user/managedblockchain-tls-chain.pem -M /home/ec2-user/admin-msp
   ```
4. Copy certificates and confirm their installation.
   ```bash
   ls admin-msp/cacerts/
   vim admin-msp/config.yaml
   # replace certificate name placeholder
   
   vim configtx.yaml
   # replace MemberId with your MEMBER_ID
   
   docker exec cli configtxgen \
      -outputCreateChannelTx /opt/home/mychannel.pb \
      -profile OneOrgChannel -channelID mychannel \
      --configPath /opt/home/
   ```
   ![certificates.jpg](images%2Fcertificates.jpg)
## Channel Creation
1. Create a channel
   ```bash
   cd /home/ec2-user
   
   docker exec cli peer channel create -c mychannel \
      -f /opt/home/mychannel.pb -o $ORDERER \
      --cafile /opt/home/managedblockchain-tls-chain.pem --tls
   
   docker exec cli peer channel join -b mychannel.block
   ```
   The output should look something like this:
   ```bash
   2023-06-03 14:39:49.926 UTC [channelCmd] InitCmdFactory -> INFO 001 Endorser and orderer connections initialized
   2023-06-03 14:39:50.021 UTC [cli.common] readBlock -> INFO 002 Expect block, but got status: &{NOT_FOUND}
   2023-06-03 14:39:50.037 UTC [channelCmd] InitCmdFactory -> INFO 003 Endorser and orderer connections initialized
   2023-06-03 14:39:52.250 UTC [cli.common] readBlock -> INFO 004 Received block: 0
   ```
## Chaincode Packaging
1. Package the chaincode
   ```bash
   export GOPATH=$HOME/go
   export PATH=$GOROOT/bin:$PATH
   export PATH=$PATH:/home/ec2-user/go/src/github.com/hyperledger/fabric-ca/bin
   sudo chown -R ec2-user:ec2-user fabric-samples/
   cd fabric-samples/chaincode/abstore/go/
   # change go version in go.mod to 1.14
   GO111MODULE=on go mod vendor
   cd -
   
   docker exec cli peer lifecycle chaincode package ./abstore.tar.gz \
   --path fabric-samples/chaincode/abstore/go/ \
   --label abstore_1
   ```
## Chaincode Installation
1. Install the chaincode
   ```bash
   docker exec cli peer lifecycle chaincode install abstore.tar.gz
   ```
2. Verify the installation
   ```bash
   docker exec cli peer lifecycle chaincode queryinstalled
   ```
3. Approve the chaincode
   ```bash
   export CC_PACKAGE_ID=<PACKAGE_ID>
   
   docker exec cli peer lifecycle chaincode approveformyorg \
      --orderer $ORDERER --tls --cafile /opt/home/managedblockchain-tls-chain.pem \
      --channelID mychannel --name mycc --version v0 --sequence 1 --package-id $CC_PACKAGE_ID
   ```
4. Check readiness
   ```bash
   docker exec cli peer lifecycle chaincode checkcommitreadiness \
      --orderer $ORDERER --tls --cafile /opt/home/managedblockchain-tls-chain.pem \
      --channelID mychannel --name mycc --version v0 --sequence 1
   ````
5. Commit the chaincode
   ```bash
   docker exec cli peer lifecycle chaincode commit \
      --orderer $ORDERER --tls --cafile /opt/home/managedblockchain-tls-chain.pem \
      --channelID mychannel --name mycc --version v0 --sequence 1
   ```
6.  Verify the commit
   ```bash
   docker exec cli peer lifecycle chaincode querycommitted \
     --channelID mychannel
   ```
   Verification should respond with something like this:
   ```bash
   Committed chaincode definitions on channel 'mychannel':
   Name: mycc, Version: v0, Sequence: 1, Endorsement Plugin: escc, Validation Plugin: vscc
   ```
## Invoke and Test Smart Contract
1. Initialize smart contract
   ```bash
   docker exec cli peer chaincode invoke \
      --tls --cafile /opt/home/managedblockchain-tls-chain.pem \
      --channelID mychannel \
      --name mycc -c '{"Args":["init", "a", "100", "b", "200"]}'
   ```
2. First query

   Will return "100"
   ```bash
   docker exec cli peer chaincode query \
      --tls --cafile /opt/home/managedblockchain-tls-chain.pem \
      --channelID mychannel \
      --name mycc -c '{"Args":["query", "a"]}'
   ```
3. Invoke the chaincode
```bash
   docker exec cli peer chaincode invoke \
      --tls --cafile /opt/home/managedblockchain-tls-chain.pem \
      --channelID mychannel \
      --name mycc -c '{"Args":["invoke", "a", "b", "10"]}'
   ```
   Query again

   Will return "90"

## Troubleshooting
If you receive 500 errors, it is likely due to one of two reasons
1. Wrong version of GO was used on EC2 and/or cli docker image.
2. Not all dependencies were pulled and packaged.