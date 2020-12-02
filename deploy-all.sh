#!/bin/bash
# This script performs a complete deployment of the demonstration.  Largely this consists
# of retrieving stack outputs from one stack and using them as inputs to the other (which is
# in a different AWS account, so we can't import directly).
#
# At a high level:
# 1) Call build scripts to install dependencies and package deployment artefacts 
# 2) Deploy the API Provider with base (default) configuration 
# 3) Deploy the API Consumer, configuring it with the API Providers details
# 4) Update the API Provider stack with the consumers role and VPC endpoint details
#

if [ $# -ne 2 ]; then
    echo "Usage: deploy-all.sh <consumer profile> <provider profile>"
    echo "<consumer profile>: CLI profile for the API consumer AWS account"
    echo "<provider profile>: CLI profile for the API provider AWS account"
    exit 1
fi

CONSUMER_PROFILE=$1
PROVIDER_PROFILE=$2
unset AWS_PROFILE

echo "*** Checking region setting..."
if [ -z $AWS_DEFAULT_REGION ]; then
    CONSUMER_REGION=$(aws configure get region --profile $CONSUMER_PROFILE)
    PROVIDER_REGION=$(aws configure get region --profile $PROVIDER_PROFILE)
    if [[ -z $CONSUMER_REGION || -z $PROVIDER_REGION || $CONSUMER_REGION != $PROVIDER_REGION ]]; then
        echo "ERROR: region not configured or profile mismatch.  Try setting AWS_DEFAULT_REGION."
        exit 1
    else
        echo "Deploying to region $PROVIDER_REGION (based on profile config)"
    fi
else
    echo "Deploying to region $AWS_DEFAULT_REGION (based on environment)"
    CONSUMER_REGION=$AWS_DEFAULT_REGION
    PROVIDER_REGION=$AWS_DEFAULT_REGION
fi

echo "*** Checking account profiles..."
CONSUMER_ACCTID=$(aws sts get-caller-identity --profile $CONSUMER_PROFILE --query 'Account' --output text)
if [[ $CONSUMER_ACCTID =~ ^[0-9]{12}$ ]]; then
    echo "Consumer account ID: $CONSUMER_ACCTID"
else
    echo "ERROR: invalid profile $CONSUMER_PROFILE"
    exit 1
fi

PROVIDER_ACCTID=$(aws sts get-caller-identity --profile $PROVIDER_PROFILE --query 'Account' --output text)
if [[ $PROVIDER_ACCTID =~ ^[0-9]{12}$ ]]; then
    echo "Provider account ID: $PROVIDER_ACCTID"
else
    echo "ERROR: invalid profile $PROVIDER_PROFILE"
    exit 1
fi

echo "*** Creating S3 buckets for deployment artefacts..."
CONSUMER_BUCKET="private-api-deployment-${CONSUMER_REGION}-${CONSUMER_ACCTID}"
if aws s3api head-bucket --bucket $CONSUMER_BUCKET --profile $CONSUMER_PROFILE 2>/dev/null; then
    echo "re-using existing consumer bucket $CONSUMER_BUCKET"
else 
    aws s3 mb s3://$CONSUMER_BUCKET --profile $CONSUMER_PROFILE
    if [ $? -ne 0 ]; then exit 1; fi
fi

PROVIDER_BUCKET="private-api-deployment-${PROVIDER_REGION}-${PROVIDER_ACCTID}"
if aws s3api head-bucket --bucket $PROVIDER_BUCKET --profile $PROVIDER_PROFILE 2>/dev/null; then
    echo "re-using existing provider bucket $PROVIDER_BUCKET"
else 
    aws s3 mb s3://$PROVIDER_BUCKET --profile $PROVIDER_PROFILE
    if [ $? -ne 0 ]; then exit 1; fi
fi

echo "*** Packaging API consumer code for deployment..."
export AWS_PROFILE=$CONSUMER_PROFILE
./build-client.sh $CONSUMER_BUCKET
if [ $? -ne 0 ]; then exit 1; fi

echo "*** Packaging API provider code for deployment..."
export AWS_PROFILE=$PROVIDER_PROFILE
./build-backend.sh $PROVIDER_BUCKET
if [ $? -ne 0 ]; then exit 1; fi
unset AWS_PROFILE

echo "*** Deploying the API provider backend..."
sam deploy \
    --template-file api-backend/api-backend-deploy.yaml \
    --stack-name private-api-backend \
    --no-fail-on-empty-changeset \
    --capabilities CAPABILITY_NAMED_IAM CAPABILITY_AUTO_EXPAND \
    --profile $PROVIDER_PROFILE
if [ $? -ne 0 ]; then exit 1; fi

echo "*** Retrieving provider stack outputs..."
declare -A PROVIDER_OUTPUTS=()
while read -r key val; do 
    PROVIDER_OUTPUTS[$key]=$val
done < <(aws cloudformation describe-stacks \
            --stack-name private-api-backend \
            --query 'Stacks[0].Outputs[*].[OutputKey,OutputValue]' \
            --output text \
            --profile $PROVIDER_PROFILE)
if [ $? -ne 0 ]; then exit 1; fi
echo "API ID: ${PROVIDER_OUTPUTS[APIGatewayID]}"
echo "API Gateway FQDN: ${PROVIDER_OUTPUTS[APIGatewayFQDN]}"
echo "API Access Role: ${PROVIDER_OUTPUTS[APIAccessRole]}"

echo "*** Deploying the API consumer clients..."
sam deploy \
    --template-file api-client/vpc-api-client-deploy.yaml \
    --stack-name private-api-client \
    --no-fail-on-empty-changeset \
    --capabilities CAPABILITY_NAMED_IAM CAPABILITY_AUTO_EXPAND \
    --profile $CONSUMER_PROFILE \
    --parameter-overrides \
      pAPIHost=${PROVIDER_OUTPUTS[APIGatewayFQDN]} \
      pAPIAccountID=${PROVIDER_ACCTID} \
      pAPIRoleARN=${PROVIDER_OUTPUTS[APIAccessRole]}
if [ $? -ne 0 ]; then exit 1; fi

echo "*** Retrieving consumer stack outputs..."
declare -A CONSUMER_OUTPUTS=()
while read -r key val; do 
    CONSUMER_OUTPUTS[$key]=$val 
done < <(aws cloudformation describe-stacks \
            --stack-name private-api-client \
            --query 'Stacks[0].Outputs[*].[OutputKey,OutputValue]' \
            --output text \
            --profile $CONSUMER_PROFILE)
if [ $? -ne 0 ]; then exit 1; fi
echo "API Gateway VPC Endpoint ID: ${CONSUMER_OUTPUTS[APIGatewayEndpointID]}"
echo "API Client Function Role: ${CONSUMER_OUTPUTS[DirectAuthClientRole]}"

echo "*** Updating API provider stack with consumer authorization details..."
sam deploy \
    --template-file api-backend/api-backend-deploy.yaml \
    --stack-name private-api-backend \
    --no-fail-on-empty-changeset \
    --capabilities CAPABILITY_NAMED_IAM CAPABILITY_AUTO_EXPAND \
    --profile $PROVIDER_PROFILE \
    --parameter-overrides \
      pTrustedPrincipals=$CONSUMER_ACCTID \
      pAPIAccessList=${CONSUMER_OUTPUTS[DirectAuthClientRole]} \
      pAllowedVPCEndpoints=${CONSUMER_OUTPUTS[APIGatewayEndpointID]}
if [ $? -ne 0 ]; then exit 1; fi

echo "*** Deploying updates to the API Gateway stage..."
aws apigateway create-deployment \
    --rest-api-id ${PROVIDER_OUTPUTS[APIGatewayID]} \
    --stage-name Prod \
    --profile $PROVIDER_PROFILE
if [ $? -ne 0 ]; then exit 1; fi

echo "*** Success!"
exit 0
