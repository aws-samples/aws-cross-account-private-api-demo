#!/bin/bash
#
# Use this script to test invocation of the client Lambda functions

if [ $# -ne 1 ]; then
    echo "Usage: invoke.sh <AWS CLI profile>"
    exit 1
fi

CONSUMER_PROFILE=$1

RED=$'\e[1;31m'
GREEN=$'\e[1;32m'
NC=$'\e[0m'

declare -A OUTPUTS=()
echo "*** Retrieving CloudFormation stack outputs from private-api-client..."
while read -r key val; do OUTPUTS[$key]=$val; done < <(aws cloudformation describe-stacks \
    --stack-name private-api-client \
    --query 'Stacks[0].Outputs[*].[OutputKey,OutputValue]' \
    --output text \
    --profile $CONSUMER_PROFILE)
if [ $? -ne 0 ]; then 
    echo "${RED}*** ERROR - could not retrieve stack outputs, please check your profile / region${NC}"
    exit 1; 
fi

if [ -z ${OUTPUTS[PythonDirectAuthClient]} ]; then
    echo "${RED}*** ERROR - Output PythonDirectAuthClient not found - please check the profile and stack${NC}"
    exit 1
fi

echo "*** Invoking direct auth function: ${OUTPUTS[PythonDirectAuthClient]}"
rm output.txt 2>/dev/null
aws lambda invoke \
    --function-name ${OUTPUTS[PythonDirectAuthClient]} \
    --profile $CONSUMER_PROFILE \
    output.txt
echo "Direct auth client API response:"
cat output.txt
echo ""
if grep -q '"statusCode": 200' output.txt; then 
    echo "${GREEN}*** SUCCESS - direct auth API call succeeded with status code 200${NC}"
else
    echo "${RED}*** FAILED - direct auth API call failed, check the output above${NC}"
fi
echo ""

if [ -z ${OUTPUTS[PythonAssumeRoleClient]} ]; then
    echo "${RED}***Output PythonAssumeRoleClient not found - please check the profile and stack${NC}"
    exit 1
fi

echo "*** Invoking assume role function: ${OUTPUTS[PythonAssumeRoleClient]}"
rm output.txt 2>/dev/null
aws lambda invoke \
    --function-name ${OUTPUTS[PythonAssumeRoleClient]} \
    --profile $CONSUMER_PROFILE \
    output.txt
echo "Assume role client API respone:"
cat output.txt
echo ""
if grep -q '"statusCode": 200' output.txt; then 
    echo "${GREEN}*** SUCCESS - assume role API call succeeded with status code 200${NC}"
else
    echo "${RED}*** FAILED - assume role API call failed, check the output above${NC}"
fi
echo ""
  