#!/bin/bash

# Set variables
REGION="us-east-1"

# Create a new network
echo "Creating a new network..."
CREATE_RESPONSE=$(aws managedblockchain create-network \
    --cli-input-json '{
        "Name": "aws_blockchain_poc",
        "Description": "AWS Blockchain POC",
        "Framework": "HYPERLEDGER_FABRIC",
        "FrameworkVersion": "2.2",
        "FrameworkConfiguration": {
            "Fabric": {
                "Edition": "STARTER"
            }
        },
        "VotingPolicy": {
            "ApprovalThresholdPolicy": {
                "ThresholdPercentage": 50,
                "ProposalDurationInHours": 24,
                "ThresholdComparator": "GREATER_THAN"
            }
        },
        "MemberConfiguration": {
            "Name": "org1",
            "Description": "org1 member of network",
            "FrameworkConfiguration": {
                "Fabric": {
                    "AdminUsername": "admin",
                    "AdminPassword": "Password123"
                }
            },
            "LogPublishingConfiguration": {
                "Fabric": {
                    "CaLogs": {
                        "Cloudwatch": {
                            "Enabled": true
                        }
                    }
                }
            }
        }
    }' \
    --region $REGION)

NETWORK_ID=$(echo "$CREATE_RESPONSE" | jq -r .NetworkId)
MEMBER_ID=$(echo "$CREATE_RESPONSE" | jq -r .MemberId)

# Wait for network to become available
echo "Waiting for network to become available..."
echo "This can take up to 30 minutes."

status=""
while [[ $status != "AVAILABLE" ]]; do
    sleep 60
    status=$(aws managedblockchain get-network --network-id $NETWORK_ID --query 'Network.Status' --region $REGION --output text)
done

echo "Setup complete."

# Create a new blockchain client
echo "Creating a new blockchain client..."
CLIENT_RESPONSE=$(aws managedblockchain create-node \
    --network-id $NETWORK_ID \
    --member-id $MEMBER_ID \
    --node-configuration '{"InstanceType": "bc.t3.small", "AvailabilityZone": "us-east-1a"}' \
    --region $REGION)

NODE_ID=$(echo $CLIENT_RESPONSE | jq -r .Node.Id)

echo "Node ID: $NODE_ID"

echo "Blockchain client created successfully."