# AWS Managed Blockchain for smart contract POC
## Introduction


## What will be created
* VPC
* EC2 instance and security group
* Amazon Blockchain Managed network, user, node
* Userdata installs all essential packages

## Steps
1. Install AWS CLI and configure it with your access key, secret key, and region.
2. Build an Amazon Managed Blockchain network

Note: There is no TerraForm resource to build this at this time. So we will use AWS CLI.
```bash
cd scripts

./create_managed_blockchain.sh 
```
3. Install Terraform and initialize it in a new directory.

Declare EC2 userdata variables in ec2.tf with the information from the following commands

NETWORK_ID
```bash
aws --region us-east-1 managedblockchain list-networks --output text --query 'Networks[*].Id'
```

MEMBER_ID
```bash
aws --region us-east-1 managedblockchain list-members --network-id <NETWORK_ID> --output text --query 'Members[*].Id'
```
```bash
#!/bin/bash

AWS_REGION=us-east-1
MEMBER_ID=
NETWORK_ID=
```
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

5. Test connectivity
   1. Connect using SSM to EC2 instance
![ssm_connect.jpg](images%2Fssm_connect.jpg)
   2. Use ec2-user
   ```bash
   sudo -i #to become root
   su ec2-user
   cd ~
   source .bash_profile
   ```
   3. Check connectivity
   ```bash
   curl https://$CASERVICEENDPOINT/cainfo -k
   ```
   Result: JSON payload with CAName, CAChain, IssuerRevocationPublicKey, and Version
6. Setup the client
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
cp -r aws_blockchain_poc/blockchain/src/* .
cp -r aws_blockchain_poc/blockchain/admin-msp/ .
```

7. Setup CLI
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
8. Enroll the admin user
```bash
aws s3 cp s3://us-east-1.managedblockchain/etc/managedblockchain-tls-chain.pem  /home/ec2-user/managedblockchain-tls-chain.pem

# Confirm
openssl x509 -noout -text -in /home/ec2-user/managedblockchain-tls-chain.pem

# Enroll user
ls admin-msp/cacerts/
vim admin-msp/config.yaml
# replace certificate name placeholder

fabric-ca-client enroll \
  -u "https://admin:Password123@$CASERVICEENDPOINT" \
  --tls.certfiles /home/ec2-user/managedblockchain-tls-chain.pem -M /home/ec2-user/admin-msp

docker exec cli configtxgen \
   -outputCreateChannelTx /opt/home/mychannel.pb \
   -profile OneOrgChannel -channelID mychannel \
   --configPath /opt/home/
```
![certificates.jpg](images%2Fcertificates.jpg)
8. Create a channel
```bash
cd /home/ec2-user

vim configtx.yaml
# replace MemberId with your MEMBER_ID

docker exec cli peer channel create -c mychannel \
   -f /opt/home/mychannel.pb -o $ORDERER \
   --cafile /opt/home/managedblockchain-tls-chain.pem --tls

docker exec cli peer channel join -b mychannel.block
```
Output should look something like this
```bash
2023-06-03 14:39:49.926 UTC [channelCmd] InitCmdFactory -> INFO 001 Endorser and orderer connections initialized
2023-06-03 14:39:50.021 UTC [cli.common] readBlock -> INFO 002 Expect block, but got status: &{NOT_FOUND}
2023-06-03 14:39:50.037 UTC [channelCmd] InitCmdFactory -> INFO 003 Endorser and orderer connections initialized
2023-06-03 14:39:52.250 UTC [cli.common] readBlock -> INFO 004 Received block: 0
```
9. Package the chaincode
```bash
cd /home/ec2-user/src

curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.3/install.sh | bash

export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"  # This loads nvm
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"  # This loads nvm bash_completion

nvm install 12
nvm use 12
npm install

cd /home/ec2-user

tar czf code.tar.gz src
tar czf contract.tar.gz code.tar.gz metadata.json 
```
10. Install the chaincode
```bash
docker exec cli peer lifecycle chaincode install contract.tar.gz

# Verify
docker exec cli peer lifecycle chaincode queryinstalled
```
11. Approve and commit chaincode
```bash
export CC_PACKAGE_ID=<PACKAGE_ID>

# Approve
docker exec cli peer lifecycle chaincode approveformyorg \
   --orderer $ORDERER --tls --cafile /opt/home/managedblockchain-tls-chain.pem \
   --channelID mychannel --name mycc --version v0 --sequence 1 --package-id $CC_PACKAGE_ID

# Check readiness
docker exec cli peer lifecycle chaincode checkcommitreadiness \
   --orderer $ORDERER --tls --cafile /opt/home/managedblockchain-tls-chain.pem \
   --channelID mychannel --name mycc --version v0 --sequence 1

# Commit the chaincode
docker exec cli peer lifecycle chaincode commit \
   --orderer $ORDERER --tls --cafile /opt/home/managedblockchain-tls-chain.pem \
   --channelID mychannel --name mycc --version v0 --sequence 1
   
# Verify
docker exec cli peer lifecycle chaincode querycommitted \
  --channelID mychannel
```
Verify should respond with something like this
```bash
Committed chaincode definitions on channel 'mychannel':
Name: mycc, Version: v0, Sequence: 1, Endorsement Plugin: escc, Validation Plugin: vscc
```
12. Invoke/test
```bash
docker exec cli peer chaincode invoke \
   --tls --cafile /opt/home/managedblockchain-tls-chain.pem \
   --channelID mychannel \
   --name mycc -c '{"function":"hello","Args":["World"]}'
```