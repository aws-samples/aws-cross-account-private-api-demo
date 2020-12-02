# Code adapted from:
# https://github.com/awslabs/aws-cloudformation-templates/blob/master/aws/solutions/PrefixListResource/FunctionCode/lambda_function.py
# 
# This code has been modified to use the updated (simpler) crhelper module:
# https://aws.amazon.com/blogs/infrastructure-and-automation/aws-cloudformation-custom-resource-creation-with-python-aws-lambda-and-crhelper/
# https://github.com/aws-cloudformation/custom-resource-helper

from boto3 import client
from botocore.exceptions import ClientError
import os
from crhelper import CfnResource
import logging

logger = logging.getLogger(__name__)
helper = CfnResource()

def get_pl_id(pl_name, region):
    """
    Get PrefixListID for given PrefixListName
    """
    logger.info("Get PrefixListId for PrefixListName: %s in %s" % (pl_name, region)) 
    try:
        ec2 = client('ec2', region_name=region)
        response = ec2.describe_prefix_lists(
            Filters=[
                {
                    'Name': 'prefix-list-name',
                    'Values': [
                        pl_name
                    ]
                }
            ]
        )
    except ClientError as e:
        raise Exception("Error retrieving prefix list: %s" % e)
    prefix_list_id = response['PrefixLists'][0]['PrefixListId']
    logger.info("PrefixListID = %s" % prefix_list_id)
    return prefix_list_id

@helper.create
def create(event, context):
    logger.info("Got Create")
    region = os.environ['AWS_REGION']
    prefix_list_name = event['ResourceProperties']['PrefixListName']
    prefix_list_id = get_pl_id(prefix_list_name, region)
    helper.Data['PrefixListID'] = prefix_list_id
    return "RetrievedPrefixList"

@helper.update
def update(event, context):
    logger.info("Got Update")

@helper.delete
def delete(event, context):
    logger.info("Got Delete")

def handler(event, context):
    helper(event, context)